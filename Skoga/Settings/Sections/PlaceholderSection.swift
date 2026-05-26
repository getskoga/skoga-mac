import SwiftUI

/// Rendered for any `SettingsSectionID` whose dedicated panel hasn't
/// landed yet. The contract from issue #20 is "never a dead-end coming
/// soon", so the placeholder names the section, describes what'll
/// eventually live on it, *and* enumerates concrete bullets from the
/// section's `roadmap` so the user can see specifically what's
/// shipping next — not just a sticker with extra words.
struct PlaceholderSection: View {
    @Environment(\.palette) private var p
    let section: SettingsSectionID

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            roadmapCard
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(skoga: section.icon).skogaIconSize(15)
                    .foregroundStyle(p.ink2)
                Text(section.title)
                    .font(SkogaFont.serifTitle(24))
                    .foregroundStyle(p.ink)
            }
            Text(section.blurb)
                .font(SkogaFont.body(13))
                .foregroundStyle(p.inkMute)
                .lineSpacing(13 * 0.45)
                .frame(maxWidth: 540, alignment: .leading)
        }
    }

    private var roadmapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("SHIPPING NEXT")
                    .font(SkogaFont.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(p.inkFaint)
                Spacer()
                Text("v1 roadmap")
                    .font(SkogaFont.monoTiny(9.5))
                    .tracking(0.8)
                    .foregroundStyle(p.amber)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                            .stroke(p.amber.opacity(0.45), lineWidth: Tokens.Hairline.width)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(section.roadmap, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                            .fill(p.paper)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(item)
                            .font(SkogaFont.body(12.5))
                            .foregroundStyle(p.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(16)
        .background(p.paper2)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }
}
