import SwiftUI

@main
struct SkogaApp: App {
    @StateObject private var state: AppState = {
        let mock = ProcessInfo.processInfo.environment["SKOGA_USE_MOCK"] == "1"
        if mock {
            return AppState(client: MockDaemonClient(), isMock: true)
        }
        return AppState(client: LiveDaemonClient(), isMock: false)
    }()

    var body: some Scene {
        Window("Skoga", id: "main") {
            MainWindow()
                .environmentObject(state)
                .withPalette()
                .task { await state.bootstrap() }
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Open Command Palette") { state.commandPaletteOpen = true }
                    .keyboardShortcut("k", modifiers: .command)
            }
        }
    }
}
