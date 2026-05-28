import SwiftUI

/// Root view for the first-run wizard. Renders the deep-forest backdrop
/// (with concentric topographic rings), the rounded paper window, the
/// six-pip progress bar, and dispatches to the current step view. Owns
/// no state of its own — the `OnboardingState` it reads from is
/// supplied by the parent and persists across re-runs via UserDefaults.
struct OnboardingShell: View {
    @Environment(\.palette) private var p
    @Environment(OnboardingState.self) private var state
    @Environment(AppCoordinator.self) private var coordinator

    private struct TopoRing: Identifiable {
        let id: Int
        let rx: Double
        let ry: Double
    }

    private static let topoRings: [TopoRing] = [
        .init(id: 0, rx: 360, ry: 200),
        .init(id: 1, rx: 280, ry: 155),
        .init(id: 2, rx: 200, ry: 110),
        .init(id: 3, rx: 120, ry: 66),
        .init(id: 4, rx: 48,  ry: 26),
    ]

    var body: some View {
        ZStack {
            backdrop
            window
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    // MARK: – Backdrop

    /// Deep forest gradient with five concentric topographic rings,
    /// mirroring the radial-gradient + ellipses in `onboarding.css`.
    /// Rings are centered on the window's midpoint so the layout stays
    /// stable across resize / window-resize animations.
    private var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: [.oklch(0.30, 0.05, 145), .oklch(0.18, 0.02, 130)],
                startPoint: .top,
                endPoint: .bottom
            )
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                let cx = w * 0.5
                let cy = h * 0.5
                ZStack {
                    ForEach(Self.topoRings, id: \.id) { ring in
                        Ellipse()
                            .stroke(Color.oklch(0.42, 0.085, 145, opacity: 0.10), lineWidth: 1)
                            .frame(width: ring.rx * 2, height: ring.ry * 2)
                            .position(x: cx, y: cy)
                    }
                }
            }
            .opacity(0.94)
        }
        .ignoresSafeArea()
    }

    // MARK: – Window

    private var window: some View {
        VStack(spacing: 0) {
            topBar
            Hairline()
            ScrollView {
                stepBody
                    .padding(.horizontal, 72)
                    .padding(.top, 38)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(p.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(p.rule.opacity(0.6), lineWidth: Tokens.Hairline.width)
        )
        .shadow(color: .oklch(0.10, 0.01, 60, opacity: 0.30), radius: 35, x: 0, y: 24)
        .frame(maxWidth: 1180, maxHeight: 820)
        .padding(24)
    }

    // MARK: – Top bar (wordmark · progress · close)

    private var topBar: some View {
        HStack(alignment: .center, spacing: 0) {
            wordmark
                .frame(width: 160, alignment: .leading)
            progress
                .frame(maxWidth: .infinity, alignment: .center)
            closeButton
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(p.paper2)
    }

    private var wordmark: some View {
        HStack(spacing: 8) {
            SkogaGlyph(size: 16, color: p.forest)
            Text("Skoga")
                .font(SkogaFont.serifName(16).weight(.medium))
                .foregroundStyle(p.ink)
            Text("FIRST RUN")
                .font(SkogaFont.monoTiny(9))
                .tracking(0.72)
                .foregroundStyle(p.inkMute)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                        .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                )
        }
    }

    private var progress: some View {
        HStack(spacing: 0) {
            ForEach(Array(OnboardingStep.allCases.enumerated()), id: \.offset) { pair in
                if pair.offset > 0 {
                    Rectangle()
                        .fill(p.ruleHard)
                        .frame(width: 16, height: 0.5)
                }
                progressPip(index: pair.offset, step: pair.element)
                    .padding(.horizontal, 11)
            }
        }
    }

    @ViewBuilder
    private func progressPip(index: Int, step: OnboardingStep) -> some View {
        let isCurrent = index == state.step
        let isDone = index < state.step

        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(isDone ? p.forest : (isCurrent ? p.ink : p.paper))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle().stroke(
                            isDone ? p.forest : (isCurrent ? p.ink : p.ruleHard),
                            lineWidth: Tokens.Hairline.width
                        )
                    )
                if isDone {
                    Image(skoga: .check).skogaIconSize(9)
                        .foregroundStyle(Color.oklch(0.97, 0.02, 90))
                } else {
                    Text("\(index + 1)")
                        .font(SkogaFont.mono(9.5).weight(.medium))
                        .foregroundStyle(isCurrent ? p.paper : p.inkMute)
                }
            }
            Text(step.label.uppercased())
                .font(SkogaFont.mono(10))
                .tracking(0.8)
                .foregroundStyle(isCurrent ? p.ink : (isDone ? p.ink2 : p.inkMute))
        }
    }

    private var closeButton: some View {
        Button(action: skip) {
            Image(skoga: .close).skogaIconSize(12)
                .foregroundStyle(p.inkMute)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(p.paper)
                        .hairlineBorder(p.rule, radius: 5)
                )
        }
        .buttonStyle(.plain)
        .help("Skip onboarding")
        // Escape mirrors the close affordance — without it the wizard
        // has no keyboard escape hatch, which violates the issue's
        // "never a dead-end" rule for users who navigate by keyboard.
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Skip onboarding")
    }

    // MARK: – Step body

    @ViewBuilder
    private var stepBody: some View {
        let current = OnboardingStep.allCases[state.step]
        let next: () -> Void = { state.next() }
        let back: () -> Void = { state.back() }
        Group {
            switch current {
            case .welcome:  StepWelcome(onNext: next)
            case .model:    StepModel(onNext: next, onBack: back)
            case .github:   StepGitHub(onNext: next, onBack: back)
            case .sandbox:  StepSandbox(onNext: next, onBack: back)
            case .forest:   StepWorkspace(onNext: next, onBack: back)
            case .ready:    StepReady(onFinish: finish, onDispatchFirst: dispatchFirst)
            }
        }
        .frame(maxWidth: 880)
        .frame(maxWidth: .infinity)
    }

    // MARK: – Finish paths

    private func skip() {
        state.finish()
    }

    private func finish() {
        state.finish()
    }

    private func dispatchFirst() {
        state.finish()
        coordinator.navigate(to: .dispatch)
    }
}
