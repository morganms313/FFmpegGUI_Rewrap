import SwiftUI

struct JobDetailView: View {
    @Environment(AppState.self) private var appState
    let job: ProcessingJob

    @State private var selectedTab = DetailTab.settings

    enum DetailTab: String, CaseIterable {
        case settings  = "Settings"
        case inspector = "Inspector"
    }

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // Tab bar
            HStack {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(DetailTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)

                Spacer()

                // Process button
                processButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Main content
            switch selectedTab {
            case .settings:
                settingsContent
            case .inspector:
                InspectorView(mediaFile: job.mediaFile)
            }
        }
        .navigationTitle(job.mediaFile.filename)
        .navigationSubtitle(job.mediaFile.formatName)
    }

    // MARK: - Settings content

    private var settingsContent: some View {
        VSplitView {
            MetadataFormView(settings: bindableSettings, mediaFile: job.mediaFile)
                .frame(minHeight: 300)

            if appState.showCommandPreview {
                CommandPreviewView(job: job)
                    .padding(12)
                    .frame(minHeight: 100, maxHeight: 360)
            }
        }
    }

    private var bindableSettings: Binding<JobSettings> {
        Binding(
            get: { job.settings },
            set: { job.settings = $0 }
        )
    }

    // MARK: - Process button

    @ViewBuilder
    private var processButton: some View {
        switch job.status {
        case .running(let p):
            HStack(spacing: 8) {
                ProgressView(value: p)
                    .progressViewStyle(.linear)
                    .frame(width: 100)
                Text(String(format: "%.0f%%", p * 100))
                    .font(.caption)
                    .monospacedDigit()
            }
        case .done(let url):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.link)
            }
        case .failed(let err):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                Text("Failed").foregroundStyle(.red)
                Button("Retry") {
                    Task { await appState.processJob(job) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .help(err)
        default:
            Button {
                Task { await appState.processJob(job) }
            } label: {
                Label("Process", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(job.status == .probing || job.status == .idle)
        }
    }
}
