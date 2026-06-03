import SwiftUI

/// The bubble that pops out of corner-Kongle. Structure-only for now —
/// the three options (bug / feature / help) are placeholders that will
/// hand off to `BugReportModal` and the daemon's help RPCs in a later
/// slice. Mirrors the layout in `kongle-helper-mockup.html` so the
/// concept can be validated end-to-end before any wiring lands.
struct KongleHelperModal: View {
    @Environment(\.palette) private var p
    @Environment(ModalState.self) private var modal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            menu
        }
        .frame(width: 322)
        .background(p.paper)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.modal)
                .stroke(p.ruleHard, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.modal))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 14)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hi, I'm Kongle.")
                    .font(SkogaFont.serifHeading(17))
                    .foregroundStyle(p.ink)
                Text("Spot a bug, want a feature, or stuck on something? Pass it my way.")
                    .font(SkogaFont.body(13))
                    .foregroundStyle(p.ink2)
                    .lineSpacing(13 * 0.4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                modal.kongleHelperOpen = false
            } label: {
                Image(skoga: .close).skogaIconSize(11)
                    .foregroundStyle(p.inkMute)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .fill(p.paper2)
                            .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
    }

    private var menu: some View {
        VStack(spacing: 8) {
            optionRow(icon: .bug,    title: "Report a bug",      subtitle: "Something's broken")
            optionRow(icon: .spark,  title: "Request a feature", subtitle: "Share an idea")
            optionRow(icon: .doc,    title: "Get help",          subtitle: "Ask me anything")
        }
        .padding(.horizontal, 16).padding(.bottom, 14)
    }

    private func optionRow(icon: SkogaIcon, title: String, subtitle: String) -> some View {
        // No action wired yet — placeholders for the eventual hand-off to
        // BugReportModal / FeatureRequest / Help flows.
        Button { } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(p.forestSoft)
                    Image(skoga: icon).skogaIconSize(15).foregroundStyle(p.forest)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(SkogaFont.bodyMedium(13))
                        .foregroundStyle(p.ink)
                    Text(subtitle)
                        .font(SkogaFont.small(11.5))
                        .foregroundStyle(p.inkMute)
                }

                Spacer(minLength: 0)

                Image(skoga: .chevron).skogaIconSize(10)
                    .foregroundStyle(p.inkFaint)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.card)
                    .fill(p.paper2)
                    .hairlineBorder(p.rule, radius: Tokens.Radius.card)
            )
        }
        .buttonStyle(.plain)
    }
}
