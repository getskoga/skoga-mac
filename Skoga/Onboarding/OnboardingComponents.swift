import SwiftUI

// MARK: – Step head (eyebrow + title + lede)

/// Shared head block used by steps 2–5. Step 1's hero diverges enough
/// (centered, no eyebrow) that it builds its own header inline.
struct StepHead: View {
    @Environment(\.palette) private var p
    let eyebrow: String
    let title: String
    /// Optional lede paragraph rendered under the title. Named `lede`
    /// rather than `body` so it doesn't collide with the View protocol's
    /// required `var body`.
    let lede: AnyView?

    init(eyebrow: String, title: String, body: AnyView? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.lede = body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(SkogaFont.monoLabel(10))
                .tracking(1.0)
                .foregroundStyle(p.forest)
            Text(title)
                .font(SkogaFont.serifTitle(30))
                .foregroundStyle(p.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let lede {
                lede
                    .frame(maxWidth: 580, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Helper for the lede paragraph under a step title — `body:` can carry
/// inline `Text` segments, so callers wrap in `AnyView(Text(…))`.
struct StepLede: View {
    @Environment(\.palette) private var p
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(SkogaFont.body(14))
            .foregroundStyle(p.inkMute)
            .lineSpacing(14 * 0.55)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: – Action bar

/// Bottom row pattern: Back at left, optional secondary in the middle,
/// primary Continue (or override) at right.
struct OnboardingActions<Trailing: View>: View {
    let onBack: (() -> Void)?
    let center: AnyView?
    @ViewBuilder var trailing: () -> Trailing

    init(
        onBack: (() -> Void)? = nil,
        center: AnyView? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.onBack = onBack
        self.center = center
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            if let onBack {
                OBTextButton(label: "Back", action: onBack)
            }
            Spacer()
            if let center { center }
            trailing()
        }
        .padding(.top, 6)
    }
}

// MARK: – Buttons (forest primary / text / ghost)

struct OBPrimaryButton: View {
    @Environment(\.palette) private var p
    let label: String
    var icon: SkogaIcon? = .chevron
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label).font(SkogaFont.bodyMedium(13))
                if let icon {
                    Image(skoga: icon).skogaIconSize(13)
                }
            }
            .foregroundStyle(Color.oklch(0.97, 0.02, 90))
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(disabled ? p.forest.opacity(0.55) : p.forest)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct OBTextButton: View {
    @Environment(\.palette) private var p
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(SkogaFont.bodyMedium(12.5))
                .foregroundStyle(p.inkMute)
                .padding(.horizontal, 10)
                .frame(height: 32)
        }
        .buttonStyle(.plain)
    }
}

struct OBGhostButton: View {
    @Environment(\.palette) private var p
    let label: String
    var icon: SkogaIcon? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(skoga: icon).skogaIconSize(12)
                }
                Text(label).font(SkogaFont.bodyMedium(12.5))
            }
            .foregroundStyle(p.ink2)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(p.paper)
                    .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Switch (matches `.s-switch` in onboarding.css)

struct OBSwitch: View {
    @Environment(\.palette) private var p
    let isOn: Bool
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? p.forest : p.paper3)
                    .overlay(
                        Capsule()
                            .stroke(isOn ? p.forest : p.rule, lineWidth: Tokens.Hairline.width)
                    )
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .padding(3)
                    .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 0.5)
            }
            .frame(width: 36, height: 20)
            .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .animation(.easeOut(duration: 0.12), value: isOn)
        // VoiceOver: announce as a stateful toggle, not just "Button".
        // Without this, every carveout / master toggle reads as a
        // nameless button with no on/off cue.
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: – Callout (dashed, leading shield icon)

struct OBCallout: View {
    @Environment(\.palette) private var p
    let icon: SkogaIcon
    let headline: String
    /// Paragraph text under `headline`. Named `detail` rather than
    /// `body` because View's protocol already claims that identifier.
    let detail: String

    init(icon: SkogaIcon, headline: String, body: String) {
        self.icon = icon
        self.headline = headline
        self.detail = body
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(skoga: icon).skogaIconSize(14)
                .foregroundStyle(p.forest)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(SkogaFont.bodyMedium(12.5))
                    .foregroundStyle(p.ink)
                Text(detail)
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .lineSpacing(12 * 0.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.input)
                .fill(p.paper2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.input)
                .strokeBorder(p.rule, style: StrokeStyle(lineWidth: Tokens.Hairline.width, dash: [3, 3]))
        )
    }
}
