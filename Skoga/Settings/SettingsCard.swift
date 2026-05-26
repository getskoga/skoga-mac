import SwiftUI

/// Shared chrome for a single panel in `SettingsShell`'s detail column.
/// Originally lived as private `sectionCard` helpers inside the GitHub
/// and Models panels; promoting it here keeps the three (now four)
/// panels visually identical without each one inventing its own radius,
/// padding, and border treatment.
///
/// Padding mirrors the original 18pt used by the live cards. The
/// background uses `paper2` so a card sits one tier above the detail
/// column's `paper` — same contrast step as a Roster card on the
/// MainWindow background.
struct SettingsCard<Content: View>: View {
    @Environment(\.palette) private var p
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(18)
        .background(p.paper2)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }
}

/// Small uppercase-mono section label used inside settings cards
/// ("SCOPES", "DEFAULT REVIEWER", "API KEY", "WHAT WAKES YOU", etc.).
/// One source of truth so a future tracking / weight / color tweak
/// doesn't have to land in five files.
struct SettingsCardLabel: View {
    @Environment(\.palette) private var p
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(SkogaFont.mono(10))
            .tracking(1.0)
            .foregroundStyle(p.inkFaint)
    }
}
