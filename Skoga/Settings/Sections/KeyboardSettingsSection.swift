import SwiftUI

/// Settings → Keyboard. Read-only catalog of the shortcuts the app
/// actually responds to today. Source-of-truth lives in
/// `KeyboardShortcut.catalog` so a future rebinding UI can hang off the
/// same array without re-deriving the human-readable mapping from
/// scattered `.keyboardShortcut(...)` modifiers.
///
/// Why read-only: the issue calls out rebinding as a v2 item. Doing it
/// honestly requires a key-capture field, conflict detection, and a
/// place to persist user overrides — none of which exist today. Showing
/// a list of real shortcuts the user can actually press is more useful
/// than a half-built editor.
struct KeyboardSettingsSection: View {
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            ForEach(KeyboardShortcut.catalog) { group in
                shortcutCard(group)
            }
            futureCard
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(skoga: SettingsSectionID.keyboard.icon).skogaIconSize(15)
                    .foregroundStyle(p.ink2)
                Text(SettingsSectionID.keyboard.title)
                    .font(SkogaFont.serifTitle(24))
                    .foregroundStyle(p.ink)
            }
            Text("Shortcuts that work today. Each row shows what the chord does and where in the app it's active. Rebinding is on the roadmap; for v1 these are fixed.")
                .font(SkogaFont.body(13))
                .foregroundStyle(p.inkMute)
                .lineSpacing(13 * 0.45)
                .frame(maxWidth: 540, alignment: .leading)
        }
    }

    private func shortcutCard(_ group: KeyboardShortcut.Group) -> some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel(group.label.uppercased())
                    .padding(.bottom, 14)

                VStack(spacing: 0) {
                    ForEach(group.shortcuts.indices, id: \.self) { idx in
                        ShortcutRow(shortcut: group.shortcuts[idx])
                        if idx != group.shortcuts.count - 1 {
                            Hairline().padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    /// Same amber-pill "v1 roadmap" treatment used by the placeholder
    /// sections — the rebinding affordance is the panel's only piece of
    /// not-yet-shipped UI, so flagging it explicitly keeps the rest of
    /// the panel honest about what does work today.
    private var futureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SettingsCardLabel("ROADMAP")
                Spacer()
                Text("rebinding")
                    .font(SkogaFont.monoTiny(9.5))
                    .tracking(0.8)
                    .foregroundStyle(p.amber)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    // Matches the amber pill treatment used in
                    // NotificationsSettingsSection / PlaceholderSection
                    // / PrivacySettingsSection. Fill + stroke (rather
                    // than stroke-only) keeps the pill above WCAG AA
                    // in dark mode — same reasoning as the
                    // "COMING IN SOLO" pill comment.
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                            .fill(p.amberSoft.opacity(0.45))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                            .stroke(p.amber.opacity(0.45), lineWidth: Tokens.Hairline.width)
                    )
            }

            Text("A future build will let you rebind any of the chords above, with conflict detection against macOS and the embedded terminal. Bindings will persist per-machine under `skoga.keyboard.*` — same `@AppStorage` pattern Notifications and Budgets use.")
                .font(SkogaFont.body(12))
                .foregroundStyle(p.inkMute)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(p.paper)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }
}

// MARK: – Shortcut row

private struct ShortcutRow: View {
    @Environment(\.palette) private var p
    let shortcut: KeyboardShortcut

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.action)
                    .font(SkogaFont.bodyMedium(13))
                    .foregroundStyle(p.ink)
                Text(shortcut.context)
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ChordView(keys: shortcut.keys)
        }
    }
}

/// One key cap per glyph, joined with a thin separator. SwiftUI's
/// `KeyboardShortcut` -> string formatter doesn't render the apple-style
/// caps we want next to a parchment row, so we draw them ourselves with
/// the same `paper3` + rule treatment used by Budgets' alert chips.
private struct ChordView: View {
    @Environment(\.palette) private var p
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys.indices, id: \.self) { idx in
                Text(keys[idx])
                    .font(SkogaFont.mono(11.5))
                    .foregroundStyle(p.ink)
                    .frame(minWidth: 20, minHeight: 20)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(p.paper3)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                    )
            }
        }
    }
}

// MARK: – Shortcut catalog

/// One shortcut the app actually responds to. Lives outside the view so
/// the future rebinding UI can iterate the same list. Each entry maps
/// 1:1 to a `.keyboardShortcut(...)` modifier in the codebase or to a
/// built-in macOS chord (e.g. ⌘, for Settings, which `Settings { }`
/// wires automatically).
struct KeyboardShortcut: Identifiable, Hashable {
    let id: String
    /// What the chord does, in user-facing language ("Open Command
    /// Palette", not "set commandPaletteOpen = true").
    let action: String
    /// Where the chord is active — "Anywhere", "Modal", a specific view.
    let context: String
    /// Display glyphs for each key in the chord, in press order.
    let keys: [String]

    struct Group: Identifiable {
        let id: String
        let label: String
        let shortcuts: [KeyboardShortcut]
    }

    /// Ordered groups rendered top-to-bottom in the panel. Keep groups
    /// small (3-5 entries each) — a long single list is harder to skim
    /// than three short cards.
    static let catalog: [Group] = [
        Group(
            id: "global",
            label: "Global",
            shortcuts: [
                .init(
                    id: "command-palette",
                    action: "Open Command Palette",
                    context: "Anywhere in the app",
                    keys: ["⌘", "K"]
                ),
                .init(
                    id: "settings",
                    action: "Open Settings",
                    context: "Anywhere — macOS default",
                    keys: ["⌘", ","]
                ),
                .init(
                    id: "hide",
                    action: "Hide Skoga",
                    context: "Anywhere — macOS default",
                    keys: ["⌘", "H"]
                ),
                .init(
                    id: "quit",
                    action: "Quit Skoga",
                    context: "Anywhere — macOS default",
                    keys: ["⌘", "Q"]
                ),
            ]
        ),
        Group(
            id: "modal",
            label: "Modals and overlays",
            shortcuts: [
                .init(
                    id: "esc-palette",
                    action: "Dismiss Command Palette",
                    context: "When the palette is open",
                    keys: ["esc"]
                ),
                .init(
                    id: "esc-onboarding",
                    action: "Skip first-run for now",
                    context: "While the first-run wizard is up",
                    keys: ["esc"]
                ),
                .init(
                    id: "submit-palette",
                    action: "Run first match",
                    context: "When the palette is open",
                    keys: ["⏎"]
                ),
            ]
        ),
    ]
}
