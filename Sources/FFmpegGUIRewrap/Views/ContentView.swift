import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showFFmpegWarning = false

    private let supportedTypes: [UTType] = [
        .movie, .video,
        UTType(filenameExtension: "mxf")!,
        UTType(filenameExtension: "mov")!,
        UTType(filenameExtension: "mp4")!,
        UTType(filenameExtension: "mkv")!,
        UTType(filenameExtension: "ts")!,
    ]

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            QueueView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            if let job = appState.selectedJob {
                JobDetailView(job: job)
            } else {
                DropTargetView()
            }
        }
        .navigationTitle("Rewrap")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.triggerFileImport = true
                } label: {
                    Label("Add Files", systemImage: "plus")
                }

                Divider()

                Button {
                    Task { await appState.processAll() }
                } label: {
                    Label("Process All", systemImage: "play.fill")
                }
                .disabled(appState.jobs.isEmpty || appState.isProcessingAll)

                if appState.isProcessingAll {
                    ProgressView().controlSize(.small)
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                Toggle(isOn: $state.showCommandPreview) {
                    Label("Command Preview", systemImage: "terminal")
                }
                .toggleStyle(.button)
            }
        }
        .fileImporter(
            isPresented: $state.triggerFileImport,
            allowedContentTypes: supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let secured = urls.compactMap { url -> URL? in
                    guard url.startAccessingSecurityScopedResource() else { return nil }
                    return url
                }
                appState.addFiles(secured)
            case .failure:
                break
            }
        }
        .onAppear {
            let (ffOK, fpOK) = appState.validateFFmpegPaths()
            if !ffOK || !fpOK { showFFmpegWarning = true }
        }
        .alert("FFmpeg Not Found", isPresented: $showFFmpegWarning) {
            Button("Open Settings") { /* open settings */ }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text("ffmpeg and/or ffprobe were not found. Run 'make fetch-ffmpeg', install via Homebrew, or update the path in Settings.")
        }
    }
}

// MARK: - Drop target (empty state)

struct DropTargetView: View {
    @Environment(AppState.self) private var appState
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 56))
                .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .animation(.easeInOut(duration: 0.15), value: isTargeted)

            Text(isTargeted ? "Release to Add" : "Drop Files Here")
                .font(.title2)
                .foregroundStyle(isTargeted ? .primary : .secondary)
                .animation(.easeInOut(duration: 0.15), value: isTargeted)

            Text("or use the  +  button")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.accentColor.opacity(0.07) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                let urls = await resolveFileURLs(from: providers)
                if !urls.isEmpty {
                    appState.addFiles(urls)
                }
            }
            return true
        }
    }

    // NSItemProvider for file URLs gives back Data, not URL —
    // decode via URL(dataRepresentation:relativeTo:).
    private func resolveFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        await withTaskGroup(of: URL?.self) { group in
            for provider in providers {
                group.addTask {
                    await withCheckedContinuation { continuation in
                        provider.loadItem(
                            forTypeIdentifier: UTType.fileURL.identifier,
                            options: nil
                        ) { item, _ in
                            if let data = item as? Data,
                               let url = URL(dataRepresentation: data, relativeTo: nil)
                            {
                                continuation.resume(returning: url)
                            } else if let url = item as? URL {
                                // Fallback: some providers hand back a URL directly
                                continuation.resume(returning: url)
                            } else {
                                continuation.resume(returning: nil)
                            }
                        }
                    }
                }
            }
            var results: [URL] = []
            for await url in group {
                if let url { results.append(url) }
            }
            return results
        }
    }
}
