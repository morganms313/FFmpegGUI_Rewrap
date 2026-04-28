import Foundation

enum JobStatus: Equatable {
    case idle
    case probing
    case ready
    case running(progress: Double)   // 0.0–1.0
    case done(outputURL: URL)
    case failed(error: String)

    var displayLabel: String {
        switch self {
        case .idle:                 return "Idle"
        case .probing:              return "Probing…"
        case .ready:                return "Ready"
        case .running(let p):       return String(format: "Processing %.0f%%", p * 100)
        case .done:                 return "Done"
        case .failed(let e):        return "Failed: \(e)"
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
    var isFinished: Bool {
        switch self { case .done, .failed: return true; default: return false }
    }
}

@Observable
class ProcessingJob: Identifiable {
    let id: UUID = UUID()
    let mediaFile: MediaFile
    var settings: JobSettings
    var status: JobStatus = .idle
    var logOutput: String = ""
    var ffmpegCommand: [String] = []

    init(mediaFile: MediaFile, settings: JobSettings = JobSettings()) {
        self.mediaFile = mediaFile
        self.settings = settings
    }

    func appendLog(_ line: String) {
        logOutput += line + "\n"
    }

    var outputURL: URL? {
        if case .done(let url) = status { return url }
        return nil
    }

    func resolvedOutputURL() -> URL? {
        let sourceURL = mediaFile.url
        let ext = settings.outputFormat.fileExtension
        let stem = sourceURL.deletingPathExtension().lastPathComponent

        let templateStr: String
        switch settings.filenameTemplate {
        case .nameRewrap: templateStr = "{name}_rewrap"
        case .nameDate:   templateStr = "{name}_\(todayString())"
        case .nameSuffix: templateStr = "{name}_out"
        case .custom:     templateStr = settings.customFilenameTemplate
        }

        let filename = templateStr
            .replacingOccurrences(of: "{name}", with: stem)
            .replacingOccurrences(of: "{date}", with: todayString())
            + ".\(ext)"

        let dir: URL
        if let d = settings.outputDirectory {
            dir = URL(fileURLWithPath: d)
        } else {
            dir = sourceURL.deletingLastPathComponent()
        }
        return dir.appendingPathComponent(filename)
    }

    private func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: Date())
    }
}
