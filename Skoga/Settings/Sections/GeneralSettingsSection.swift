import ServiceManagement
import SwiftUI

/// Settings → General. Three controls per the issue: theme, launch at
/// login, and "open at". Each is a single `@AppStorage` value; the heavy
/// lifting (registering the login item, applying the color scheme,
/// restoring the last view) lives where it's evaluated — `SkogaApp`
/// reads the theme + open-at keys via the same `AppPrefs` enum, and the
/// launch-at-login row talks straight to `SMAppService.mainApp` so the
/// Mac side doesn't have to round-trip through the daemon.
struct GeneralSettingsSection: View {
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            themeCard
            launchAtLoginCard
            openAtCard
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(skoga: SettingsSectionID.general.icon).skogaIconSize(15)
                    .foregroundStyle(p.ink2)
                Text(SettingsSectionID.general.title)
                    .font(SkogaFont.serifTitle(24))
                    .foregroundStyle(p.ink)
            }
            Text(SettingsSectionID.general.blurb)
                .font(SkogaFont.body(13))
                .foregroundStyle(p.inkMute)
                .lineSpacing(13 * 0.45)
                .frame(maxWidth: 540, alignment: .leading)
        }
    }

    // MARK: – Theme

    private var themeCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel("APPEARANCE")
                    .padding(.bottom, 6)
                Text("System follows the macOS appearance. The parchment palette ships in both modes; pick one explicitly if you prefer the look regardless of system setting.")
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)

                ThemeSegmentPicker()
            }
        }
    }

    // MARK: – Launch at login

    private var launchAtLoginCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel("LAUNCH AT LOGIN")
                    .padding(.bottom, 14)
                LaunchAtLoginRow()
            }
        }
    }

    // MARK: – Open at

    private var openAtCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel("OPEN AT")
                    .padding(.bottom, 6)
                Text("Where Skoga lands when you launch it. \"Last view\" remembers your top-level Cockpit tab — it won't reopen into a stale conversation.")
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
                OpenAtRow()
            }
        }
    }
}

// MARK: – Theme picker

/// Three-state segmented picker. Selected segment takes the forest fill
/// the rest of Settings uses for "this is the active choice"; the rest
/// stay in the paper/rule family so the row reads as one control. Same
/// chip shape as `AlertStepChip` in Budgets so the two segmented
/// selectors look like siblings.
private struct ThemeSegmentPicker: View {
    @Environment(\.palette) private var p

    @AppStorage(AppPrefs.theme) private var raw: String = AppPrefs.ThemeChoice.system.rawValue

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppPrefs.ThemeChoice.allCases) { choice in
                ThemeChip(
                    choice: choice,
                    selected: raw == choice.rawValue
                ) {
                    raw = choice.rawValue
                }
            }
            Spacer()
        }
    }
}

/// Text-only chip — `SkogaIcon` doesn't have moon/sun glyphs and the
/// repurposed icons (`.settings` for System, `.spark` for Light,
/// `.clock` for Dark) read as random rather than as an appearance
/// mode. Three short labels are perfectly skimmable without iconography.
private struct ThemeChip: View {
    @Environment(\.palette) private var p
    let choice: AppPrefs.ThemeChoice
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(choice.label)
                .font(SkogaFont.bodyMedium(12))
                .foregroundStyle(selected ? .white : p.ink2)
                .frame(minWidth: 88)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                        .fill(selected ? p.forest : (hovering ? p.paper3 : p.paper))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                        .stroke(selected ? .clear : p.rule, lineWidth: Tokens.Hairline.width)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: – Launch at login

/// Wraps `SMAppService.mainApp` — `register()` and `unregister()` are
/// the entire API surface. Status is re-read after every toggle since
/// `SMAppService.Status` doesn't publish changes the way `@Observable`
/// would, and a failed registration (System Settings denied it, signing
/// mismatch on a dev build) needs to flip the switch back so the UI
/// doesn't claim the login item is on when it isn't.
private struct LaunchAtLoginRow: View {
    @Environment(\.palette) private var p

    @State private var status: SMAppService.Status = SMAppService.mainApp.status
    @State private var errorText: String?

    private var enabled: Bool { status == .enabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                    Image(skoga: .bolt).skogaIconSize(13).foregroundStyle(p.ink2)
                }
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Skoga at login")
                        .font(SkogaFont.bodyMedium(13))
                        .foregroundStyle(p.ink)
                    Text(detailText)
                        .font(SkogaFont.body(12))
                        .foregroundStyle(p.inkMute)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("Launch at login",
                       isOn: Binding(get: { enabled }, set: { toggle(to: $0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(p.forest)
                    .controlSize(.small)
                    // System Settings denial leaves the service in
                    // `.requiresApproval` — disable the switch so a
                    // user clicking it doesn't get a second silent
                    // failure; the inline error below points them at
                    // the right place.
                    .disabled(status == .requiresApproval)
            }
            if let errorText {
                Text(errorText)
                    .font(SkogaFont.body(11.5))
                    .foregroundStyle(p.ember)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { refreshStatus() }
    }

    /// Two-state copy so the row reads correctly in both positions and
    /// the `.requiresApproval` case is its own message — System
    /// Settings denial isn't a Skoga failure but the user still needs
    /// to know they have to flip a switch elsewhere.
    private var detailText: String {
        switch status {
        case .enabled:
            "Skoga launches as part of your login items. Toggle off to remove."
        case .requiresApproval:
            "macOS blocked the login item. Approve Skoga under System Settings → General → Login Items."
        case .notRegistered, .notFound:
            "Adds Skoga to your login items via the system service — no AppleScript or hidden agent."
        @unknown default:
            "Status unavailable. Toggle to retry."
        }
    }

    private func toggle(to on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on {
                try service.register()
            } else {
                try service.unregister()
            }
            errorText = nil
        } catch {
            errorText = "Couldn't \(on ? "register" : "unregister") login item: \(error.localizedDescription)"
        }
        refreshStatus()
    }

    private func refreshStatus() {
        status = SMAppService.mainApp.status
    }
}

// MARK: – Open at

private struct OpenAtRow: View {
    @Environment(\.palette) private var p

    @AppStorage(AppPrefs.openAt) private var raw: String = AppPrefs.OpenAtChoice.roster.rawValue

    var body: some View {
        VStack(spacing: 6) {
            ForEach(AppPrefs.OpenAtChoice.allCases) { choice in
                OpenAtChoiceRow(choice: choice, selected: raw == choice.rawValue) {
                    raw = choice.rawValue
                }
            }
        }
    }
}

private struct OpenAtChoiceRow: View {
    @Environment(\.palette) private var p
    let choice: AppPrefs.OpenAtChoice
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                    Image(skoga: choice.icon).skogaIconSize(13).foregroundStyle(p.ink2)
                }
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.label)
                        .font(SkogaFont.bodyMedium(13))
                        .foregroundStyle(p.ink)
                    Text(choice.blurb)
                        .font(SkogaFont.body(12))
                        .foregroundStyle(p.inkMute)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    Circle()
                        .stroke(selected ? p.forest : p.rule, lineWidth: Tokens.Hairline.width)
                        .frame(width: 16, height: 16)
                    if selected {
                        Circle().fill(p.forest).frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 6)
            }
            .padding(10)
            // Selected lands on paper4 so it's visibly heavier than the
            // hover state's paper3 — without that step, a user hovering
            // over an unselected row sees the same fill as the
            // currently-selected one and has to rely on the thin
            // border to tell which is which.
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(selected ? p.paper4 : (hovering ? p.paper3 : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .stroke(selected ? p.forest.opacity(0.5) : .clear, lineWidth: Tokens.Hairline.width)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: – AppStorage keys + helpers

/// Single source of truth for `skoga.app.*` keys. `SkogaApp` reads
/// `theme` to drive `.preferredColorScheme` on both Scenes, and reads
/// `openAt` + `lastView` to decide which view to land on after
/// bootstrap. Other Settings panels namespace their keys separately —
/// `BudgetPrefs`, `NotificationPrefs`, `EditorPrefs`, etc.
enum AppPrefs {
    static let theme    = "skoga.app.theme"
    static let openAt   = "skoga.app.openAt"
    /// Bumped by `AppCoordinator.navigate(to:)` whenever the user lands
    /// on a top-level Cockpit tab (Roster / Dispatch / Review /
    /// Telemetry / History). Conversation is excluded — restoring to a
    /// now-deleted session id would land on the placeholder view; the
    /// roster is a safer fallback for that case.
    static let lastView = "skoga.app.lastView"

    enum ThemeChoice: String, CaseIterable, Identifiable, Hashable {
        case system
        case light
        case dark

        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: "System"
            case .light:  "Light"
            case .dark:   "Dark"
            }
        }
        /// `nil` lets the system appearance drive the color scheme.
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light:  .light
            case .dark:   .dark
            }
        }
    }

    enum OpenAtChoice: String, CaseIterable, Identifiable, Hashable {
        case roster
        case lastView

        var id: String { rawValue }
        var label: String {
            switch self {
            case .roster:   "Roster"
            case .lastView: "Last view"
            }
        }
        var blurb: String {
            switch self {
            case .roster:   "Always start on the Roster — the default."
            case .lastView: "Reopen on whichever top-level tab you left off on."
            }
        }
        var icon: SkogaIcon {
            switch self {
            case .roster:   .roster
            case .lastView: .loop
            }
        }
    }

    /// Theme resolver used by `SkogaApp` to drive `.preferredColorScheme`.
    /// Falls back to system when the persisted value is missing or
    /// unknown — no reason to hard-fail the whole app on a stray key.
    static func readTheme() -> ThemeChoice {
        let raw = UserDefaults.standard.string(forKey: theme) ?? ThemeChoice.system.rawValue
        return ThemeChoice(rawValue: raw) ?? .system
    }

    static func readOpenAt() -> OpenAtChoice {
        let raw = UserDefaults.standard.string(forKey: openAt) ?? OpenAtChoice.roster.rawValue
        return OpenAtChoice(rawValue: raw) ?? .roster
    }

    /// Persisted last-view rawValue. Caller maps to `AppView` itself —
    /// returning a String keeps this helper independent of `AppView`'s
    /// import surface (and means a new AppView case can be added
    /// without breaking the resolver if the persisted value disappears).
    static func readLastView() -> String? {
        UserDefaults.standard.string(forKey: lastView)
    }
}
