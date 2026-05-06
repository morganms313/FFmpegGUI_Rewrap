import Foundation
import Observation

@Observable
class AppState {
    // MARK: Queue
    var jobs: [ProcessingJob] = []
    var selectedJobID: UUID?

    // MARK: Settings
    var defaultOutputDirectory: String = ""

    // MARK: UI state
    var triggerFileImport: Bool = false
    var showCommandPreview: Bool = true
    var isProcessingAll: Bool = false

    // MARK: Computed
    var selectedJob: ProcessingJob? {
        jobs.first { $0.id == selectedJobID }
    }

    /// Resolved binary URLs via FFmpegLocator (bundle → App Support → Homebrew)
    var ffmpegURL:  URL? { FFmpegLocator.ffmpegURL }
    var ffprobeURL: URL? { FFmpegLocator.ffprobeURL }

    var ffmpegPath:  String { ffmpegURL?.path  ?? "" }
    var ffprobePath: String { ffprobeURL?.path ?? "" }

    // MARK: Queue management

    func addFiles(_ urls: [URL]) {
        for url in urls {
            let file = MediaFile(url: url)
            let job  = ProcessingJob(mediaFile: file)
            jobs.append(job)
            Task { await probeJob(job) }
        }
        if selectedJobID == nil {
            selectedJobID = jobs.first?.id
        }
    }

    func removeSelected() {
        guard let id = selectedJobID else { return }
        jobs.removeAll { $0.id == id }
        selectedJobID = jobs.first?.id
    }

    func clearQueue() {
        jobs.removeAll()
        selectedJobID = nil
    }

    // MARK: Probing

    func probeJob(_ job: ProcessingJob) async {
        guard let ffprobePath = ffprobeURL?.path else {
            job.status = .failed(error: "ffprobe not found. Run 'make fetch-ffmpeg' or install FFmpeg.")
            return
        }
        job.status = .probing
        let parser = FFprobeParser(ffprobePath: ffprobePath)
        do {
            let data = try await parser.probe(url: job.mediaFile.url)
            job.mediaFile.probeData = data
            if job.settings.audioTracks.isEmpty {
                job.settings.audioTracks = job.mediaFile.defaultAudioTrackSettings()
            }
            job.status = .ready
        } catch {
            job.mediaFile.probeError = error.localizedDescription
            job.status = .failed(error: "Probe failed: \(error.localizedDescription)")
        }
    }

    // MARK: Processing

    func processAll() async {
        isProcessingAll = true
        defer { isProcessingAll = false }
        for job in jobs where !job.status.isFinished && !job.status.isRunning {
            await processJob(job)
        }
    }

    func processJob(_ job: ProcessingJob) async {
        // Fast paths: skip FFmpeg, only frameRateOverride is honoured.
        switch job.settings.frameRateConformMode {
        case .fastClone:
            guard let outputURL = job.resolvedOutputURL() else {
                job.status = .failed(error: "Could not resolve output path.")
                return
            }
            await processFastFrameRateOnly(job: job, outputURL: outputURL, inPlace: false)
            return
        case .inPlace:
            await processFastFrameRateOnly(job: job, outputURL: job.mediaFile.url, inPlace: true)
            return
        case .rewrap:
            break
        }

        guard let outputURL = job.resolvedOutputURL() else {
            job.status = .failed(error: "Could not resolve output path.")
            return
        }

        guard let ffmpegPath = ffmpegURL?.path else {
            job.status = .failed(error: "ffmpeg not found. Run 'make fetch-ffmpeg' or install FFmpeg.")
            return
        }

        let builder = CommandBuilder()
        let result  = builder.build(mediaFile: job.mediaFile, settings: job.settings, outputURL: outputURL)
        job.ffmpegCommand = result.args
        job.status = .running(progress: 0)

        let runner   = FFmpegRunner(ffmpegPath: ffmpegPath)
        let duration = job.mediaFile.probeData?.format.durationSeconds

        for await event in runner.run(args: result.args) {
            switch event {
            case .progress(let time):
                if let dur = duration, dur > 0 {
                    job.status = .running(progress: min(time / dur, 1.0))
                }
            case .output(let line):
                job.appendLog(line)
            case .finished(let code):
                job.status = code == 0
                    ? .done(outputURL: outputURL)
                    : .failed(error: "FFmpeg exited with code \(code)")
            case .error(let msg):
                job.status = .failed(error: msg)
            }
        }

        // After the runner loop — apply QT conform if needed
        if case .done = job.status,
           [OutputFormat.mov, .mp4].contains(job.settings.outputFormat),
           let fps = job.settings.frameRateOverride, !fps.isEmpty {
            // Read the source file's mvhd timescale so QTConformer can restore it
            // if FFmpeg's muxer normalised it (e.g. ARRI 24000 → FFmpeg default 1000).
            let srcTimescale = QTConformer.readMovieTimescale(url: job.mediaFile.url)
            let outTimescale = QTConformer.readMovieTimescale(url: outputURL)
            job.appendLog("QTConformer: source mvhd timescale = \(srcTimescale.map(String.init) ?? "<unreadable>")")
            job.appendLog("QTConformer: ffmpeg output mvhd timescale = \(outTimescale.map(String.init) ?? "<unreadable>")")
            do {
                try QTConformer.conform(url: outputURL, targetFPS: fps,
                                        originalMovieTimescale: srcTimescale)
                let finalTimescale = QTConformer.readMovieTimescale(url: outputURL)
                job.appendLog("QTConformer: final mvhd timescale = \(finalTimescale.map(String.init) ?? "<unreadable>")")
                job.appendLog("QT frame-rate conform applied: \(fps) fps")
            } catch {
                job.status = .failed(error: "Frame rate conform failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Fast frame-rate-only path

    /// Skips FFmpeg, only honours `frameRateOverride`.
    /// - inPlace=false: clones source → output (APFS clone if same volume) and patches the clone
    /// - inPlace=true: patches the source file directly (destructive, no new file)
    private func processFastFrameRateOnly(job: ProcessingJob, outputURL: URL, inPlace: Bool) async {
        guard [OutputFormat.mov, .mp4].contains(job.settings.outputFormat) else {
            job.status = .failed(error: "Fast frame-rate mode only supports .mov / .mp4 output.")
            return
        }
        guard let fps = job.settings.frameRateOverride, !fps.isEmpty else {
            job.status = .failed(error: "Fast frame-rate mode requires a Frame Rate value.")
            return
        }

        job.status = .running(progress: 0)
        job.ffmpegCommand = []  // no ffmpeg invocation

        // Read source timescale BEFORE any patching so we can preserve it.
        // (For inPlace, this read happens before the source is modified.)
        let srcTimescale = QTConformer.readMovieTimescale(url: job.mediaFile.url)

        if inPlace {
            job.appendLog("In-place mode: patching \(job.mediaFile.url.path) directly (no new file).")
        } else {
            job.appendLog("Fast clone mode: cloning source → \(outputURL.path)")
            // Remove any existing file at output
            if FileManager.default.fileExists(atPath: outputURL.path) {
                do { try FileManager.default.removeItem(at: outputURL) }
                catch {
                    job.status = .failed(error: "Could not overwrite existing output: \(error.localizedDescription)")
                    return
                }
            }
            // FileManager.copyItem uses copyfile() which auto-uses APFS CLONE on same volume
            do {
                try FileManager.default.copyItem(at: job.mediaFile.url, to: outputURL)
                job.appendLog("Clone complete.")
            } catch {
                job.status = .failed(error: "Clone failed: \(error.localizedDescription)")
                return
            }
        }

        job.appendLog("QTConformer: source mvhd timescale = \(srcTimescale.map(String.init) ?? "<unreadable>")")
        do {
            try QTConformer.conform(url: outputURL, targetFPS: fps,
                                    originalMovieTimescale: srcTimescale)
            let finalTimescale = QTConformer.readMovieTimescale(url: outputURL)
            job.appendLog("QTConformer: final mvhd timescale = \(finalTimescale.map(String.init) ?? "<unreadable>")")
            job.appendLog("\(inPlace ? "In-place" : "Fast clone") frame-rate conform applied: \(fps) fps")
            job.status = .done(outputURL: outputURL)
        } catch {
            job.status = .failed(error: "Frame rate conform failed: \(error.localizedDescription)")
        }
    }

    // MARK: FFmpeg availability

    func validateFFmpegPaths() -> (ffmpegOK: Bool, ffprobeOK: Bool) {
        (ffmpegURL != nil, ffprobeURL != nil)
    }
}
