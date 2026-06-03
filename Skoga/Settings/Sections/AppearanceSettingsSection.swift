import SwiftUI

/// Settings → Appearance. Three knobs that visibly change UI behavior:
/// chrome density (sidebar width), reduce motion (animated Kongle SVGs),
/// and a mascot/illustration toggle. Theme stays under General per the
/// roadmap layout — this panel links to it rather than duplicating.
///
/// Each control is backed by `@AppStorage` and consumed by exactly one
/// view: `Sidebar` reads density, `AnimatedSVG` reads reduce-motion,
/// `RosterView`'s empty state reads `showIllustrations`. Adding a knob
/// without a consumer would put us back where the placeholder was, so
/// every entry on this panel is wired to a visible effect.
struct AppearanceSettingsSection: View {
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            densityCard
            motionCard
            illustrationsCard
            themePointerCard
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(skoga: SettingsSectionID.appearance.icon).skogaIconSize(15)
                    .foregroundStyle(p.ink2)
                Text(SettingsSectionID.appearance.title)
                    .font(SkogaFont.serifTitle(24))
                    .foregroundStyle(p.ink)
            }
            Text("Tune the window chrome and motion. Theme (System · Light · Dark) lives under General — this panel covers the choices that don't fit there.")
                .font(SkogaFont.body(13))
                .foregroundStyle(p.inkMute)
                .lineSpacing(13 * 0.45)
                .frame(maxWidth: 540, alignment: .leading)
        }
    }

    // MARK: – Density

    private var densityCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel("CHROME DENSITY")
                    .padding(.bottom, 6)
                Text("Controls the width of the main window's sidebar and the Settings sidebar. Compact reclaims about 30pt for content; standard keeps full agent names visible without truncation.")
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
                DensitySegmentPicker()
            }
        }
    }

    // MARK: – Motion

    private var motionCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel("MOTION")
                    .padding(.bottom, 14)
                ReduceMotionRow()
            }
        }
    }

    // MARK: – Illustrations

    private var illustrationsCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel("ILLUSTRATIONS")
                    .padding(.bottom, 14)
                ShowIllustrationsRow()
            }
        }
    }

    // MARK: – Theme pointer

    /// Theme is a General-section concern (per issue #32) and lives in
    /// that panel. Without this card the user lands on Appearance hunting
    /// for "Dark mode" and either gets confused or assumes it doesn't
    /// exist. A one-line pointer is cheaper than re-rendering the same
    /// segmented control in two places.
    private var themePointerCard: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                    Image(skoga: SettingsSectionID.general.icon).skogaIconSize(13)
                        .foregroundStyle(p.ink2)
                }
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Theme lives under General")
                        .font(SkogaFont.bodyMedium(13))
                        .foregroundStyle(p.ink)
                    Text("System · Light · Dark is the same parchment palette in two color schemes. Open General to switch.")
                        .font(SkogaFont.body(12))
                        .foregroundStyle(p.inkMute)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: – Density picker

private struct DensitySegmentPicker: View {
    @Environment(\.palette) private var p
    @AppStorage(AppearancePrefs.density) private var raw: String = AppearancePrefs.Density.standard.rawValue

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppearancePrefs.Density.allCases) { choice in
                DensityChip(choice: choice, selected: raw == choice.rawValue) {
                    raw = choice.rawValue
                }
            }
            Spacer()
        }
    }
}

private struct DensityChip: View {
    @Environment(\.palette) private var p
    let choice: AppearancePrefs.Density
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

// MARK: – Reduce motion row

/// Toggle row that disables the SMIL animations on Kongle SVGs. Honors
/// macOS' Reduce Motion accessibility preference too — if the system
/// pref is on, the in-app pref is ignored and the row notes the override
/// so a user toggling here doesn't think Skoga is broken.
private struct ReduceMotionRow: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @AppStorage(AppearancePrefs.reduceMotion) private var on: Bool = AppearancePrefs.reduceMotionDefault

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                Image(skoga: .spark).skogaIconSize(13).foregroundStyle(p.ink2)
            }
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(p.rule, lineWidth: Tokens.Hairline.width)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Reduce motion")
                    .font(SkogaFont.bodyMedium(13))
                    .foregroundStyle(p.ink)
                Text(detailText)
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("Reduce motion", isOn: $on)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(p.forest)
                .controlSize(.small)
                .disabled(systemReduce)
        }
    }

    private var detailText: String {
        if systemReduce {
            return "On — System Settings → Accessibility has Reduce Motion enabled. Skoga follows the system pref; the in-app toggle is inactive until you turn the system one off."
        }
        return on
            ? "Animated mascot SVGs render as a single frame. Use this if SMIL playback feels jittery on your display."
            : "Mascot SVGs play their SMIL animations. The empty Roster's Kongle holds a coffee that drifts; the napping Kongle breathes."
    }
}

// MARK: – Illustrations row

private struct ShowIllustrationsRow: View {
    @Environment(\.palette) private var p
    @AppStorage(AppearancePrefs.showIllustrations) private var on: Bool = AppearancePrefs.showIllustrationsDefault

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                Image(skoga: .roster).skogaIconSize(13).foregroundStyle(p.ink2)
            }
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(p.rule, lineWidth: Tokens.Hairline.width)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Show illustrations")
                    .font(SkogaFont.bodyMedium(13))
                    .foregroundStyle(p.ink)
                Text(on
                     ? "Kongle the mascot fills the Roster when it's empty. Today this is the only illustration in the app — flipping this off makes that surface text-only."
                     : "The empty Roster renders text-only. Other empty states aren't gated by this toggle today.")
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("Show illustrations", isOn: $on)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(p.forest)
                .controlSize(.small)
        }
    }
}

// MARK: – AppStorage keys + helpers

/// Single source of truth for the `skoga.appearance.*` keys. Read helpers
/// on the type so a non-View consumer (`AnimatedSVG`'s NSViewRepresentable
/// body, `Sidebar`'s width computation) can resolve the canonical default
/// without re-declaring it.
enum AppearancePrefs {
    static let density            = "skoga.appearance.density"
    static let reduceMotion       = "skoga.appearance.reduceMotion"
    static let showIllustrations  = "skoga.appearance.showIllustrations"

    /// Off by default — motion is part of the parchment palette's
    /// personality, and turning it off should be an explicit user choice.
    static let reduceMotionDefault: Bool = false
    /// On by default — mascots are a brand surface; the toggle is for
    /// users who'd rather not see them, not the default cohort.
    static let showIllustrationsDefault: Bool = true

    enum Density: String, CaseIterable, Identifiable, Hashable {
        case standard
        case compact

        var id: String { rawValue }
        var label: String {
            switch self {
            case .standard: "Standard"
            case .compact:  "Compact"
            }
        }

        /// Width applied to the main-window Sidebar and Settings sidebar.
        /// Standard matches the historical `Tokens.sidebarWidth` (224pt)
        /// so an upgrade from a previous build doesn't shift the layout
        /// for users who never opened Appearance.
        var sidebarWidth: CGFloat {
            switch self {
            case .standard: 224
            case .compact:  196
            }
        }

        /// Max width applied to the trailing role/branch label inside a
        /// Sidebar nav row. The label has fixed real estate on the right;
        /// when the whole sidebar shrinks by 28pt the trailing cap has to
        /// shrink in lockstep, otherwise the agent name gets pushed to a
        /// few characters before the truncation ellipsis. Picked so the
        /// fixed-claim total (16 + 14 + 10 + cap + 16) leaves the same
        /// proportional space for the name in both modes.
        var sidebarTrailingLabelMaxWidth: CGFloat {
            switch self {
            case .standard: 130
            case .compact:  100
            }
        }
    }

    static func readDensity() -> Density {
        let raw = UserDefaults.standard.string(forKey: density) ?? Density.standard.rawValue
        return Density(rawValue: raw) ?? .standard
    }

    static func readReduceMotion() -> Bool {
        if let v = UserDefaults.standard.object(forKey: reduceMotion) as? Bool { return v }
        return reduceMotionDefault
    }

    static func readShowIllustrations() -> Bool {
        if let v = UserDefaults.standard.object(forKey: showIllustrations) as? Bool { return v }
        return showIllustrationsDefault
    }
}
