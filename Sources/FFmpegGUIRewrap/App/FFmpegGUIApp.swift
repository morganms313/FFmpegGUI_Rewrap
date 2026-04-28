import SwiftUI

@main
struct FFmpegGUIApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Files…") {
                    appState.triggerFileImport = true
                }
                .keyboardShortcut("o")
            }
            CommandMenu("Queue") {
                Button("Process All") {
                    Task { await appState.processAll() }
                }
                .keyboardShortcut("r")
                .disabled(appState.jobs.isEmpty)

                Divider()

                Button("Remove Selected") {
                    appState.removeSelected()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(appState.selectedJobID == nil)

                Button("Clear Queue") {
                    appState.clearQueue()
                }
                .disabled(appState.jobs.isEmpty)
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
