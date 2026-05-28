import SwiftUI

/// Step 2 — Default model. Four radio cards (Opus 4.7 recommended,
/// Sonnet balanced, GPT-5 Codex fast, local offline) plus the
/// keys-come-later shield callout.
struct StepModel: View {
    @Environment(\.palette) private var p
    @Environment(OnboardingState.self) private var state
    let onNext: () -> Void
    let onBack: () -> Void

    /// Wizard-time copy. The actual *runtime* model list ships through
    /// the daemon — this is the four-option starter set the design
    /// specifies for the cockpit's default, deliberately kept short.
    private static let options: [ModelOption] = [
        .init(id: "claude-opus-4.7",  label: "Claude Opus 4.7",   provider: "Anthropic",            tag: .recommended,
              desc: "Highest reasoning lift. Best for refactors, perf, and tricky bugs. The cockpit default — swap on a per-run basis when you want to save money."),
        .init(id: "claude-sonnet-4.7", label: "Claude Sonnet 4.7", provider: "Anthropic",            tag: .balanced,
              desc: "Long context, steady multi-file edits, strong reasoning. Cheaper than Opus per token."),
        .init(id: "gpt-5-codex",      label: "GPT-5 Codex",       provider: "OpenAI",               tag: .fast,
              desc: "Cheap, fast iteration. Loves test harnesses and tight feedback loops."),
        .init(id: "local",            label: "Local model",       provider: "llama.cpp · LM Studio", tag: .offline,
              desc: "Run agents entirely on your machine. Slowest, but nothing leaves your laptop."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHead(
                eyebrow: "Step 2 · Default model",
                title: "Pick a default model.",
                body: AnyView(StepLede("This is what new agents will use unless you override on a per-run basis. We'll ask for API keys the first time an agent actually needs one — they go straight into your macOS keychain, never through Skoga."))
            )

            VStack(spacing: 8) {
                ForEach(Self.options) { option in
                    modelRow(option)
                }
            }

            OBCallout(
                icon: .shield,
                headline: "Keys come later, not now.",
                body: "When an agent first calls a model you haven't configured, Skoga prompts you for the key inline — once, stored in your keychain. You can swap models per-run anytime from Dispatch."
            )

            OnboardingActions(onBack: onBack) {
                OBPrimaryButton(label: "Continue", action: onNext)
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ option: ModelOption) -> some View {
        let selected = state.data.defaultModel == option.id

        Button(action: {
            state.update { $0.defaultModel = option.id }
        }) {
            HStack(alignment: .top, spacing: 14) {
                radio(selected: selected)
                    .frame(width: 18, height: 18)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(option.label)
                            .font(SkogaFont.serifName(17).weight(.medium))
                            .foregroundStyle(p.ink)
                        Text(option.provider)
                            .font(SkogaFont.monoSmall(10.5))
                            .foregroundStyle(p.inkMute)
                        ModelTag(tag: option.tag)
                    }
                    Text(option.desc)
                        .font(SkogaFont.body(12.5))
                        .foregroundStyle(p.inkMute)
                        .lineSpacing(12.5 * 0.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.card)
                    .fill(selected ? p.forestSoft.opacity(0.4) : p.paper2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.card)
                    .stroke(selected ? p.forest : p.rule, lineWidth: selected ? 1 : Tokens.Hairline.width)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func radio(selected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(selected ? p.forest : p.paper)
                .overlay(Circle().stroke(selected ? p.forest : p.ruleHard, lineWidth: 1))
            if selected {
                Circle()
                    .fill(Color.oklch(0.97, 0.02, 90))
                    .frame(width: 6, height: 6)
            }
        }
    }

    struct ModelOption: Identifiable {
        let id: String
        let label: String
        let provider: String
        let tag: Tag
        let desc: String

        enum Tag {
            case recommended, balanced, fast, offline
        }
    }
}

private struct ModelTag: View {
    @Environment(\.palette) private var p
    let tag: StepModel.ModelOption.Tag

    var body: some View {
        Text(text.uppercased())
            .font(SkogaFont.monoTiny(9.5).weight(weight))
            .tracking(0.76)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.tiny).fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                    .stroke(border, lineWidth: Tokens.Hairline.width)
            )
    }

    private var text: String {
        switch tag {
        case .recommended: "recommended"
        case .balanced:    "balanced"
        case .fast:        "fast"
        case .offline:     "offline"
        }
    }

    private var foreground: Color {
        switch tag {
        case .recommended, .balanced: p.forest
        case .fast:                   p.amber
        case .offline:                p.ink2
        }
    }

    private var background: Color {
        switch tag {
        case .recommended, .balanced: p.forestSoft
        case .fast:                   p.amberSoft
        case .offline:                p.paper
        }
    }

    private var border: Color {
        switch tag {
        case .recommended: .oklch(0.5, 0.08, 145, opacity: 0.55)
        case .balanced:    .oklch(0.6, 0.06, 145, opacity: 0.4)
        case .fast:        .oklch(0.7, 0.10, 75, opacity: 0.4)
        case .offline:     p.rule
        }
    }

    private var weight: Font.Weight {
        tag == .recommended ? .medium : .regular
    }
}
