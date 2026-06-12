import SwiftUI
import AppKit
import UserNotifications

@main
struct SkogaApp: App {
    /// SwiftUI's adaptor for an `NSApplicationDelegate`. The delegate's
    /// `applicationWillFinishLaunching` is the earliest reliable hook
    /// for registering the `UNUserNotificationCenter` delegate — it
    /// runs before any `Scene` materializes and before any `.task`
    /// modifier fires, so a launch-via-notification click delivered by
    /// macOS reaches our delegate instead of being dropped.
    @NSApplicationDelegateAdaptor(SkogaAppDelegate.self) private var appDelegate

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

    /// Theme preference set in Settings → General. `nil` = follow the
    /// system appearance. Bound to `@AppStorage` so flipping the
    /// segmented picker recolors both Scenes on the next render
    /// without a relaunch.
    @AppStorage(AppPrefs.theme) private var themeRaw: String = AppPrefs.ThemeChoice.system.rawValue

    private var preferredColorScheme: ColorScheme? {
        AppPrefs.ThemeChoice(rawValue: themeRaw)?.colorScheme
    }

    var body: some Scene {
        Window("Skoga", id: "main") {
            FirstRunGate()
                .environment(coordinator)
                .environment(coordinator.roster)
                .environment(coordinator.conversation)
                .environment(coordinator.modal)
                .environment(coordinator.daemon)
                .environment(coordinator.history)
                .environment(coordinator.namedAgents)
                .environment(coordinator.policy)
                .environment(onboarding)
                .withPalette()
                .preferredColorScheme(preferredColorScheme)
                .task {
                    await coordinator.bootstrap()
                    // Apply the user's "Open at" preference after
                    // bootstrap. The SKOGA_VIEW env override is honored
                    // by bootstrap; skip the lastView restore when it's
                    // set so design previews land where the env says
                    // (rather than getting overwritten by the persisted
                    // last view here). `lastView` ignores the
                    // conversation surface on write, so a restored
                    // value lands on a real top-level tab.
                    if ProcessInfo.processInfo.environment["SKOGA_VIEW"] == nil,
                       AppPrefs.readOpenAt() == .lastView,
                       let raw = AppPrefs.readLastView(),
                       let view = AppView(rawValue: raw) {
                        coordinator.navigate(to: view)
                    }
                }
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
                .environment(coordinator.namedAgents)
                .environment(coordinator.policy)
                .environment(onboarding)
                .withPalette()
                .preferredColorScheme(preferredColorScheme)
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
        // Trigger the one-time notification authorization request only
        // after the onboarding overlay drops. Otherwise the explainer
        // toast (which `start()` posts ~1.5s before the system prompt)
        // would render UNDER the zIndex-1000 overlay and be invisible,
        // and the permission alert would race the wizard. `task(id:)`
        // re-fires when `completed` flips, and runs immediately for
        // returning users (where it's already true on first appear).
        .task(id: onboarding.completed) {
            if onboarding.completed {
                NotificationsService.shared.start()
            }
        }
    }
}

/// `NSApplicationDelegate` adaptor used solely to register the
/// `UNUserNotificationCenter` delegate at the earliest possible point
/// in launch — before any SwiftUI scene exists. macOS dispatches a
/// launch-via-notification response right after the delegate is set,
/// but if we waited for a `.task` modifier to wire it the click could
/// be delivered to a nil delegate and silently dropped.
///
/// `@MainActor` because AppKit invokes the delegate on the main thread
/// and the `NotificationsService.shared` we hand off is MainActor-isolated.
@MainActor
final class SkogaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = NotificationsService.shared
    }
}
