import SwiftUI

@main
struct SkogaApp: App {
    @State private var coordinator: AppCoordinator = {
        let mock = ProcessInfo.processInfo.environment["SKOGA_USE_MOCK"] == "1"
        if mock {
            return AppCoordinator(client: MockDaemonClient(), isMock: true)
        }
        return AppCoordinator(client: LiveDaemonClient(), isMock: false)
    }()

    var body: some Scene {
        Window("Skoga", id: "main") {
            MainWindow()
                .environment(coordinator)
                .environment(coordinator.roster)
                .environment(coordinator.conversation)
                .environment(coordinator.modal)
                .environment(coordinator.daemon)
                .withPalette()
                .task { await coordinator.bootstrap() }
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Open Command Palette") { coordinator.modal.commandPaletteOpen = true }
                    .keyboardShortcut("k", modifiers: .command)
            }
        }

        // Dedicated Settings scene. `Settings { }` auto-wires the
        // "Settings…" app-menu item with the canonical ⌘, shortcut and
        // gives us a singleton window — reopening from the gear or the
        // command palette re-uses the existing one instead of spawning
        // duplicates. All slices are injected so sections can read
        // `daemon.githubStatus`, call `coordinator.setDefaultReviewer`,
        // and route toasts through `modal.showToast`.
        Settings {
            SettingsShell()
                .environment(coordinator)
                .environment(coordinator.roster)
                .environment(coordinator.conversation)
                .environment(coordinator.modal)
                .environment(coordinator.daemon)
                .withPalette()
        }
        .windowResizability(.contentMinSize)
    }
}
