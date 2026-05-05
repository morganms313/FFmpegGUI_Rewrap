import SwiftUI

// MARK: - CurrentValueBadge

/// Small secondary badge showing the source file's current value for a field.
private struct CurrentValueBadge: View {
    let value: String
    var body: some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - OptionalPicker
/// A Picker that includes a "Preserve" (nil) option alongside the enum cases.
/// Pass `current` to show the source file's existing value as a badge.
struct OptionalPicker<T: CaseIterable & Hashable & Identifiable>: View {
    let label: String
    @Binding var selection: T?
    let options: [T]
    let displayName: (T) -> String
    var current: String? = nil

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                if let c = current {
                    CurrentValueBadge(value: c)
                }
                Picker("", selection: $selection) {
                    Text("Preserve").tag(Optional<T>.none)
                    ForEach(options) { option in
                        Text(displayName(option)).tag(Optional(option))
                    }
                }
                .labelsHidden()
            }
        }
    }
}

// MARK: - OptionalTextField
/// A TextField that binds to an optional String (empty = nil).
/// Pass `current` to show the source file's existing value as a badge.
struct OptionalTextField: View {
    let placeholder: String
    @Binding var value: String?
    let label: String
    var current: String? = nil

    init(_ placeholder: String, value: Binding<String?>, label: String, current: String? = nil) {
        self.placeholder = placeholder
        self._value = value
        self.label = label
        self.current = current
    }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField(placeholder, text: Binding(
                    get: { value ?? "" },
                    set: { value = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                if let c = current {
                    CurrentValueBadge(value: c)
                }
            }
        }
    }
}

// MARK: - IntegerField
struct IntegerField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    @State private var text: String = ""

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
            .onAppear { text = "\(value)" }
            .onChange(of: text) {
                if let v = Int(text), range.contains(v) { value = v }
            }
            .onChange(of: value) { text = "\(value)" }
    }
}

// MARK: - DecimalField
struct DecimalField: View {
    @Binding var value: Double
    let format: String
    @State private var text: String = ""

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 90)
            .onAppear { text = String(format: format, value) }
            .onChange(of: text) {
                if let v = Double(text) { value = v }
            }
            .onChange(of: value) { text = String(format: format, value) }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @StateObject private var updater = FFmpegUpdater()

    var body: some View {
        @Bindable var state = appState

        Form {
            ffmpegSection
            outputSection
            aboutSection
            Section("UI") {
                Toggle("Show Command Preview by Default", isOn: $state.showCommandPreview)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
    }

    // MARK: FFmpeg section

    private var ffmpegSection: some View {
        Section {
            // Active binary locations (read-only, resolved by FFmpegLocator)
            binaryRow(label: "ffmpeg",  url: appState.ffmpegURL,  version: FFmpegLocator.version(of: "ffmpeg"))
            binaryRow(label: "ffprobe", url: appState.ffprobeURL, version: FFmpegLocator.version(of: "ffprobe"))

            Divider()

            // Update controls
            updateControls

        } header: {
            Text("FFmpeg")
        } footer: {
            Text("Bundled binaries ship inside the app. Updates are stored in ~/Library/Application Support/FFmpegGUI-Rewrap/bin/ and take priority automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func binaryRow(label: String, url: URL?, version: String?) -> some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                if let url {
                    Text(url.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    if let version {
                        Text("v\(version)")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                } else {
                    Label("Not found", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
        }
    }

    @ViewBuilder
    private var updateControls: some View {
        switch updater.state {
        case .idle:
            Button("Check for FFmpeg Updates") {
                Task { await updater.checkForUpdates() }
            }

        case .checking:
            HStack { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }

        case .upToDate(let version):
            Label("FFmpeg \(version) is up to date", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case .available(let ffv, _):
            HStack {
                Label("FFmpeg \(ffv) available", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Spacer()
                Button("Update Now") {
                    Task { await updater.installUpdate() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

        case .downloading(let tool, let progress):
            VStack(alignment: .leading, spacing: 4) {
                Text("Downloading \(tool)…").foregroundStyle(.secondary).font(.callout)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text(String(format: "%.0f%%", progress * 100))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

        case .installing:
            HStack { ProgressView().controlSize(.small); Text("Installing…").foregroundStyle(.secondary) }

        case .complete(let version):
            Label("Updated to FFmpeg \(version) — restart the app to use it", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)

        case .error(let msg):
            VStack(alignment: .leading, spacing: 6) {
                Label(msg, systemImage: "xmark.circle.fill").foregroundStyle(.red)
                Button("Try Again") {
                    Task { await updater.checkForUpdates() }
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: About section

    private var aboutSection: some View {
        let appVersion  = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        let ffmpegVer   = FFmpegLocator.version(of: "ffmpeg")
        let ffprobeVer  = FFmpegLocator.version(of: "ffprobe")
        // Wrap in a Group so the compiler resolves Section as the List/Form variant,
        // not the Table-row variant (triggered by LabeledContent's dual conformance).
        return Group {
            Section {
                LabeledContent("App Version",
                               value: "v\(appVersion) (build \(buildNumber))")
                LabeledContent("FFmpeg",
                               value: ffmpegVer.map { "v\($0)" } ?? "Not found")
                LabeledContent("FFprobe",
                               value: ffprobeVer.map { "v\($0)" } ?? "Not found")
            } header: {
                Text("About")
            }
        }
    }

    // MARK: Output section

    private var outputSection: some View {
        Section("Output") {
            LabeledContent("Default Output Directory") {
                @Bindable var state = appState
                HStack {
                    if state.defaultOutputDirectory.isEmpty {
                        Text("Same as source").foregroundStyle(.secondary)
                    } else {
                        Text(state.defaultOutputDirectory)
                            .lineLimit(1).truncationMode(.head)
                    }
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        if panel.runModal() == .OK {
                            state.defaultOutputDirectory = panel.url?.path ?? ""
                        }
                    }
                    if !state.defaultOutputDirectory.isEmpty {
                        Button("Clear") { state.defaultOutputDirectory = "" }
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}

