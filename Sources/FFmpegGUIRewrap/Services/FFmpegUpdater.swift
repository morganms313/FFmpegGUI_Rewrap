import Foundation

// MARK: - evermeet.cx API models

private struct EvermeetRelease: Decodable {
    let version: String
    let download: [DownloadItem]

    struct DownloadItem: Decodable {
        let type: String   // "zip", "7z", etc.
        let url: String
        let size: Int?
    }

    var zipURL: URL? {
        guard let item = download.first(where: { $0.type == "zip" }),
              let url  = URL(string: item.url) else { return nil }
        return url
    }
    var zipSize: Int? { download.first(where: { $0.type == "zip" })?.size }
}

// MARK: - Update state

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate(version: String)
    case available(ffmpegVersion: String, ffprobeVersion: String)
    case downloading(tool: String, progress: Double)
    case installing
    case complete(version: String)
    case error(String)
}

// MARK: - FFmpegUpdater

@MainActor
class FFmpegUpdater: ObservableObject {
    @Published var state: UpdateState = .idle

    private let session = URLSession.shared
    private var latestFFmpegInfo:  EvermeetRelease?
    private var latestFFprobeInfo: EvermeetRelease?

    // MARK: - Public

    func checkForUpdates() async {
        state = .checking
        do {
            async let ffmpegInfo  = fetchReleaseInfo("ffmpeg")
            async let ffprobeInfo = fetchReleaseInfo("ffprobe")
            let (fm, fp) = try await (ffmpegInfo, ffprobeInfo)
            latestFFmpegInfo  = fm
            latestFFprobeInfo = fp

            let currentFFmpeg = FFmpegLocator.version(of: "ffmpeg") ?? "unknown"
            // Compare: if current matches latest, we're up to date
            if currentFFmpeg == fm.version {
                state = .upToDate(version: fm.version)
            } else {
                state = .available(ffmpegVersion: fm.version, ffprobeVersion: fp.version)
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func installUpdate() async {
        guard let ffmpegInfo  = latestFFmpegInfo,
              let ffprobeInfo = latestFFprobeInfo else {
            state = .error("No update info available — check for updates first.")
            return
        }

        do {
            // Ensure destination directory exists
            let destDir = try ensureAppSupportBinDir()

            // Download + install ffmpeg
            let ffmpegBin = try await downloadAndExtract(
                info: ffmpegInfo, tool: "ffmpeg", destDir: destDir)

            // Download + install ffprobe
            let ffprobeBin = try await downloadAndExtract(
                info: ffprobeInfo, tool: "ffprobe", destDir: destDir)

            state = .installing

            // Make executable
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: ffmpegBin.path)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: ffprobeBin.path)

            state = .complete(version: ffmpegInfo.version)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Private helpers

    private func fetchReleaseInfo(_ tool: String) async throws -> EvermeetRelease {
        let url = URL(string: "https://evermeet.cx/ffmpeg/info/\(tool)/release")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badResponse
        }
        return try JSONDecoder().decode(EvermeetRelease.self, from: data)
    }

    private func downloadAndExtract(
        info: EvermeetRelease,
        tool: String,
        destDir: URL
    ) async throws -> URL {
        guard let zipURL = info.zipURL else {
            throw UpdateError.noDownloadURL(tool)
        }

        // Stream download with progress
        let (asyncBytes, response) = try await session.bytes(from: zipURL)
        let totalBytes = response.expectedContentLength
        var receivedBytes: Int64 = 0
        var data = Data()
        data.reserveCapacity(totalBytes > 0 ? Int(totalBytes) : 60_000_000)

        for try await byte in asyncBytes {
            data.append(byte)
            receivedBytes += 1
            if receivedBytes % 100_000 == 0 {
                let progress = totalBytes > 0
                    ? Double(receivedBytes) / Double(totalBytes)
                    : 0.5
                state = .downloading(tool: tool, progress: progress)
            }
        }

        // Write zip to temp
        let tmpZip = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(tool)-update.zip")
        try data.write(to: tmpZip)

        // Extract using /usr/bin/unzip
        let tmpExtractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(tool)-extracted")
        try? FileManager.default.removeItem(at: tmpExtractDir)
        try FileManager.default.createDirectory(
            at: tmpExtractDir, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", tmpZip.path, "-d", tmpExtractDir.path]
        unzip.standardOutput = Pipe()
        unzip.standardError  = Pipe()
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            throw UpdateError.extractionFailed(tool)
        }
        try? FileManager.default.removeItem(at: tmpZip)

        // Find the binary inside the extracted directory
        let extractedBin = tmpExtractDir.appendingPathComponent(tool)
        guard FileManager.default.fileExists(atPath: extractedBin.path) else {
            throw UpdateError.binaryNotFoundInZip(tool)
        }

        // Move to App Support, replacing any existing version
        let destBin = destDir.appendingPathComponent(tool)
        try? FileManager.default.removeItem(at: destBin)
        try FileManager.default.moveItem(at: extractedBin, to: destBin)
        try? FileManager.default.removeItem(at: tmpExtractDir)

        return destBin
    }

    private func ensureAppSupportBinDir() throws -> URL {
        guard let dir = FFmpegLocator.appSupportBinURL else {
            throw UpdateError.noAppSupportPath
        }
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Errors

    enum UpdateError: LocalizedError {
        case badResponse
        case noDownloadURL(String)
        case extractionFailed(String)
        case binaryNotFoundInZip(String)
        case noAppSupportPath

        var errorDescription: String? {
            switch self {
            case .badResponse:              return "Could not reach the update server."
            case .noDownloadURL(let t):     return "No download URL found for \(t)."
            case .extractionFailed(let t):  return "Failed to extract \(t) archive."
            case .binaryNotFoundInZip(let t): return "\(t) binary not found in archive."
            case .noAppSupportPath:         return "Could not locate Application Support folder."
            }
        }
    }
}
