import Foundation

class FFprobeParser {
    let ffprobePath: String

    init(ffprobePath: String = "/usr/local/bin/ffprobe") {
        self.ffprobePath = ffprobePath
    }

    func probe(url: URL) async throws -> ProbeData {
        let args: [String] = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_streams",
            "-show_format",
            "-show_programs",
            url.path
        ]

        let (stdout, _, exitCode) = try await runProcess(executable: ffprobePath, args: args)

        guard exitCode == 0 else {
            throw ProbeError.nonZeroExit(exitCode)
        }
        guard let data = stdout.data(using: .utf8) else {
            throw ProbeError.noOutput
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ProbeData.self, from: data)
        } catch {
            throw ProbeError.parseError(error.localizedDescription)
        }
    }

    // MARK: - Process helper

    private func runProcess(executable: String, args: [String]) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError  = stderrPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ProbeError.launchFailed(error.localizedDescription))
                return
            }

            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            continuation.resume(returning: (stdout, stderr, process.terminationStatus))
        }
    }

    enum ProbeError: LocalizedError {
        case launchFailed(String)
        case nonZeroExit(Int32)
        case noOutput
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .launchFailed(let e):  return "Could not launch ffprobe: \(e)"
            case .nonZeroExit(let c):   return "ffprobe exited with code \(c)"
            case .noOutput:             return "ffprobe produced no output"
            case .parseError(let e):    return "JSON parse error: \(e)"
            }
        }
    }
}
