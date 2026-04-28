import SwiftUI

struct CommandPreviewView: View {
    let job: ProcessingJob
    @State private var isCopied = false

    private var commandText: String {
        guard let outputURL = job.resolvedOutputURL() else { return "—" }
        let builder = CommandBuilder()
        let result = builder.build(mediaFile: job.mediaFile, settings: job.settings, outputURL: outputURL)
        return result.displayCommand
    }

    private var buildResult: BuildResult? {
        guard let outputURL = job.resolvedOutputURL() else { return nil }
        let builder = CommandBuilder()
        return builder.build(mediaFile: job.mediaFile, settings: job.settings, outputURL: outputURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundStyle(.secondary)
                Text("FFmpeg Command")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                if let result = buildResult, result.requiresRender {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Render required")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption)
                    .help(result.renderReasons.joined(separator: "\n"))
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("ffmpeg " + (buildResult?.args.joined(separator: " ") ?? ""), forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isCopied = false }
                } label: {
                    Label(isCopied ? "Copied!" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isCopied ? .green : .accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary)

            Divider()

            // Command text
            ScrollView([.horizontal, .vertical]) {
                Text(commandText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 80, maxHeight: 180)
            .background(.background.opacity(0.5))

            // Log output (if running or finished)
            if !job.logOutput.isEmpty {
                Divider()
                HStack {
                    Text("Log")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { job.logOutput = "" }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(job.logOutput)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("logEnd")
                    }
                    .frame(minHeight: 60, maxHeight: 140)
                    .background(.background.opacity(0.5))
                    .onChange(of: job.logOutput) {
                        proxy.scrollTo("logEnd", anchor: .bottom)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}
