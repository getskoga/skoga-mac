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

    /// First-run wizard state — pulled out of MainWindow because it gates
    /// the entire app surface. Persists across launches via UserDefaults
    /// inside `OnboardingState`; `MainWindow` mounts the overlay when
    /// `completed == false`.
    @State private var onboarding = OnboardingState()

    var body: some Scene {
        Window("Skoga", id: "main") {
            FirstRunGate()
                .environment(coordinator)
                .environment(coordinator.roster)
                .environment(coordinator.conversation)
                .environment(coordinator.modal)
                .environment(coordinator.daemon)
                .environment(coordinator.history)
                .environment(onboarding)
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
                .environment(coordinator.history)
                .environment(onboarding)
                .withPalette()
        }
        .windowResizability(.contentMinSize)
    }
}

/// Mounts the onboarding overlay on top of the cockpit until the user
/// finishes (or explicitly skips). Once `onboarding.completed` flips,
/// the overlay drops and re-launches go straight to MainWindow.
private struct FirstRunGate: View {
    @Environment(OnboardingState.self) private var onboarding

    var body: some View {
        ZStack {
            MainWindow()
            if !onboarding.completed {
                OnboardingShell()
                    .transition(.opacity)
                    .zIndex(1000)
            }
        }
        .animation(.easeOut(duration: 0.28), value: onboarding.completed)
    }
}
