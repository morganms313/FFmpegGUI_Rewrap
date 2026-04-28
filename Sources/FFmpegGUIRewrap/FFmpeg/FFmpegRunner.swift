import Foundation

enum FFmpegEvent {
    case output(String)
    case progress(Double)      // current time in seconds
    case finished(Int32)       // exit code
    case error(String)
}

class FFmpegRunner {
    let ffmpegPath: String

    init(ffmpegPath: String = "/usr/local/bin/ffmpeg") {
        self.ffmpegPath = ffmpegPath
    }

    /// Returns an AsyncStream of FFmpegEvents.  The stream ends after .finished or .error.
    func run(args: [String]) -> AsyncStream<FFmpegEvent> {
        AsyncStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            // -y: overwrite output  -progress pipe:1: machine-readable progress to stdout
            process.arguments = ["-y", "-progress", "pipe:1"] + args

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError  = stderrPipe

            // Stop the process if the stream is cancelled
            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }

            // Stream stderr (log lines) and stdout (progress key=value)
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                for line in text.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("out_time_ms=") {
                        let valStr = String(trimmed.dropFirst("out_time_ms=".count))
                        if let us = Double(valStr), us > 0 {
                            continuation.yield(.progress(us / 1_000_000))
                        }
                    }
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                continuation.yield(.output(text))
            }

            do {
                try process.run()
            } catch {
                continuation.yield(.error(error.localizedDescription))
                continuation.finish()
                return
            }

            process.terminationHandler = { p in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.yield(.finished(p.terminationStatus))
                continuation.finish()
            }
        }
    }
}
