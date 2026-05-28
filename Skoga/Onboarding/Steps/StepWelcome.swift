import SwiftUI

/// Step 1 — Welcome. Hero glyph + wordmark, italic tagline, the
/// three-surface diagram (Skoga → GitHub → Editor), the thesis line, and
/// a single forest-green CTA. The only step without a Back button.
struct StepWelcome: View {
    @Environment(\.palette) private var p
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 22) {
            hero
            diagram
            thesis
            HStack {
                Spacer()
                OBPrimaryButton(label: "Set up the cockpit", action: onNext)
                    .frame(height: 36)
                Spacer()
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(p.paper2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                    )
                    .frame(width: 92, height: 92)
                    .shadow(color: .oklch(0.18, 0.012, 60, opacity: 0.08), radius: 11, x: 0, y: 8)
                SkogaGlyph(size: 72, color: p.forest)
            }
            Text("Skoga")
                .font(SkogaFont.serifTitle(44).weight(.medium))
                .foregroundStyle(p.ink)
            Text("The manager's cockpit for AI coding agents.")
                .font(SkogaFont.font(.serif, size: 17, weight: .regular).italic())
                .foregroundStyle(p.inkMute)
                .frame(maxWidth: 560)
        }
        .padding(.top, 16)
    }

    private var diagram: some View {
        HStack(alignment: .center, spacing: 4) {
            surface(name: "Skoga", role: "dispatch · supervise", isPrimary: true, glyph: { SkogaGlyph(size: 22, color: p.forest) })
            link(arrow: "→", label: "PR")
            surface(name: "GitHub", role: "review · merge", isPrimary: false, glyph: { Image(skoga: .github).skogaIconSize(22) })
            link(arrow: "→", label: "when stuck")
            surface(name: "Editor", role: "microscope", isPrimary: false, glyph: { Image(skoga: .doc).skogaIconSize(22) })
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.modal)
                .fill(p.paper2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.modal)
                .strokeBorder(p.rule, style: StrokeStyle(lineWidth: Tokens.Hairline.width, dash: [3, 3]))
        )
    }

    @ViewBuilder
    private func surface<G: View>(name: String, role: String, isPrimary: Bool, @ViewBuilder glyph: () -> G) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(isPrimary ? p.forestSoft : p.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(isPrimary ? Color.oklch(0.6, 0.06, 145, opacity: 0.4) : p.rule, lineWidth: Tokens.Hairline.width)
                    )
                    .frame(width: 36, height: 36)
                glyph()
                    .foregroundStyle(isPrimary ? p.forest : p.inkMute)
            }
            .padding(.bottom, 2)
            Text(name)
                .font(SkogaFont.serifName(15).weight(.medium))
                .foregroundStyle(p.ink)
            Text(role.uppercased())
                .font(SkogaFont.monoTiny(10))
                .tracking(0.6)
                .foregroundStyle(p.inkFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minWidth: 120)
    }

    private func link(arrow: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(arrow)
                .font(SkogaFont.mono(18))
                .foregroundStyle(p.inkFaint)
            Text(label.uppercased())
                .font(SkogaFont.monoTiny(9.5))
                .tracking(0.76)
                .foregroundStyle(p.inkMute)
        }
    }

    private var thesis: some View {
        // The design renders this paragraph with `<b>Skoga is where you
        // run your guild from.</b>` mid-sentence. SwiftUI's `Text(_:)`
        // markdown initialiser ships with this app's deployment target,
        // so we render the bold span inline rather than hand-splicing
        // three separate Text views.
        Text(LocalizedStringKey("You're not an individual contributor anymore. You delegate, you check in, you unblock, you review. **Skoga is where you run your guild from.** Five quick steps to set up your forest."))
            .font(SkogaFont.body(13.5))
            .foregroundStyle(p.ink2)
            .lineSpacing(13.5 * 0.6)
            .frame(maxWidth: 580)
            .multilineTextAlignment(.center)
    }
}
