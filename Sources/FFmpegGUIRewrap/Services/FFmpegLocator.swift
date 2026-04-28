import Foundation

/// Locates ffmpeg and ffprobe binaries using a priority-ordered search.
///
/// Search order:
///   1. ~/Library/Application Support/FFmpegGUI-Rewrap/bin/  (user-updated)
///   2. <app bundle>/Contents/Resources/bin/                  (factory bundled)
///   3. Common Homebrew paths                                  (developer fallback)
///   4. `which` command                                        (last resort)
enum FFmpegLocator {

    // MARK: - Public API

    static var ffmpegURL:  URL? { locate("ffmpeg") }
    static var ffprobeURL: URL? { locate("ffprobe") }

    static func locate(_ tool: String) -> URL? {
        let candidates: [URL?] = [
            appSupportBinURL?.appendingPathComponent(tool),
            bundledBinURL?.appendingPathComponent(tool),
            URL(fileURLWithPath: "/opt/homebrew/opt/ffmpeg/bin/\(tool)"),
            URL(fileURLWithPath: "/opt/homebrew/bin/\(tool)"),
            URL(fileURLWithPath: "/usr/local/bin/\(tool)"),
            URL(fileURLWithPath: "/opt/ffmpeg/bin/\(tool)"),
            whichURL(tool),
        ]
        return candidates.compactMap { $0 }.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    /// Returns the version string by running `<binary> -version`.
    static func version(of tool: String) -> String? {
        guard let url = locate(tool) else { return nil }
        let process = Process()
        process.executableURL = url
        process.arguments = ["-version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch { return nil }
        let data   = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        // First line: "ffmpeg version 7.1.1 Copyright ..."
        let firstLine = output.components(separatedBy: "\n").first ?? ""
        let parts     = firstLine.components(separatedBy: " ")
        // parts[0] = "ffmpeg", parts[1] = "version", parts[2] = "7.1.1"
        return parts.count >= 3 ? parts[2] : nil
    }

    // MARK: - Paths

    /// ~/Library/Application Support/FFmpegGUI-Rewrap/bin  (user-writable, not code-signed)
    static var appSupportBinURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("FFmpegGUI-Rewrap/bin", isDirectory: true)
    }

    /// <bundle>/Contents/Resources/bin  (factory default, part of signed bundle)
    static var bundledBinURL: URL? {
        // Works both when running from a packaged .app and during `make run`
        let resourcesURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/bin", isDirectory: true)
        return FileManager.default.fileExists(atPath: resourcesURL.path)
            ? resourcesURL : nil
    }

    // MARK: - Helpers

    private static func whichURL(_ tool: String) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [tool]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }
}
