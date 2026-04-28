import SwiftUI

struct QueueView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        List(appState.jobs, selection: $state.selectedJobID) { job in
            QueueRowView(job: job)
                .tag(job.id)
        }
        .listStyle(.sidebar)
        .navigationTitle("Queue")
        .overlay {
            if appState.jobs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No files")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if !ids.isEmpty {
                Button("Process Selected") {
                    Task {
                        for id in ids {
                            if let job = appState.jobs.first(where: { $0.id == id }) {
                                if let url = job.resolvedOutputURL() {
                                    let builder = CommandBuilder()
                                    let result = builder.build(mediaFile: job.mediaFile, settings: job.settings, outputURL: url)
                                    job.ffmpegCommand = result.args
                                    await appState.processJob(job)
                                }
                            }
                        }
                    }
                }
                Divider()
                Button("Remove", role: .destructive) {
                    appState.jobs.removeAll { ids.contains($0.id) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(appState.jobs.count) file\(appState.jobs.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    appState.clearQueue()
                } label: {
                    Text("Clear")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .disabled(appState.jobs.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }
}

// MARK: - Row

struct QueueRowView: View {
    let job: ProcessingJob

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.mediaFile.filename)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(job.status.displayLabel)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            if case .running(let p) = job.status {
                ProgressView(value: p)
                    .progressViewStyle(.linear)
                    .frame(width: 50)
                    .tint(.accentColor)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .idle:
            Image(systemName: "circle").foregroundStyle(.tertiary)
        case .probing:
            ProgressView().controlSize(.mini)
        case .ready:
            Image(systemName: "circle.fill").foregroundStyle(.blue)
        case .running:
            Image(systemName: "arrow.trianglehead.2.clockwise").foregroundStyle(.orange)
                .rotationEffect(.degrees(0))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: true)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .idle, .probing:  return .secondary
        case .ready:           return .blue
        case .running:         return .orange
        case .done:            return .green
        case .failed:          return .red
        }
    }
}
