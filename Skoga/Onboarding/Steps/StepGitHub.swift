import SwiftUI

/// Step 3 — GitHub. Three sub-states: idle (Connect CTA + perm chips),
/// connecting (spinner), connected (avatar + counts). Designed to be
/// skippable — the Skip-for-now path leaves PR-landing flows disabled
/// until the user reconnects from Settings.
struct StepGitHub: View {
    @Environment(\.palette) private var p
    @Environment(OnboardingState.self) private var state
    let onNext: () -> Void
    let onBack: () -> Void

    private enum LocalState { case idle, connecting, connected }

    @State private var localState: LocalState = .idle
    /// In-flight stub OAuth task. Captured so a `Skip for now` or step
    /// navigation during `.connecting` can cancel the pending state
    /// flip instead of racing the spinner into a fake "connected"
    /// account written into UserDefaults moments after the user left.
    @State private var connectTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHead(
                eyebrow: "Step 3 · GitHub",
                title: "Where the PRs land.",
                body: AnyView(StepLede("Agents push branches and open PRs through your GitHub. Skoga doesn't try to be a review tool — it routes you cleanly. Reviews loop back so the agent can respond."))
            )

            content
                .frame(maxWidth: .infinity, alignment: .leading)

            OnboardingActions(
                onBack: { skipPendingConnect(); onBack() },
                center: AnyView(OBTextButton(label: "Skip for now") { skipPendingConnect(); onNext() })
            ) {
                OBPrimaryButton(label: "Continue") { skipPendingConnect(); onNext() }
                    .opacity(localState == .connected ? 1 : 0.5)
                    .allowsHitTesting(localState == .connected)
            }
        }
        .onAppear {
            // Rehydrate from a prior wizard run so a re-launch with an
            // existing GitHub blob doesn't ask the user to reconnect.
            if state.data.github != nil {
                localState = .connected
            }
        }
        .onDisappear { connectTask?.cancel() }
    }

    /// Cancel any in-flight stub OAuth before navigating off the step.
    /// Without this, a user who hit Connect → Skip would still get a
    /// `mikael-w` GitHub blob written into UserDefaults 1.4s later,
    /// silently overriding their explicit skip.
    private func skipPendingConnect() {
        connectTask?.cancel()
        connectTask = nil
    }

    @ViewBuilder
    private var content: some View {
        HStack(alignment: .center, spacing: 22) {
            iconBlock
            infoBlock
            Spacer(minLength: 0)
            actionBlock
        }
        .padding(22)
        .frame(minHeight: 152)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.modal)
                .fill(p.paper2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.modal)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
    }

    @ViewBuilder
    private var iconBlock: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(localState == .connected ? p.forestSoft : p.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(localState == .connected ? Color.oklch(0.5, 0.06, 145, opacity: 0.4) : p.rule, lineWidth: Tokens.Hairline.width)
                )
                .frame(width: 56, height: 56)

            switch localState {
            case .idle:
                Image(skoga: .github).skogaIconSize(28)
                    .foregroundStyle(p.ink)
            case .connecting:
                ProgressView()
                    .controlSize(.regular)
                    .tint(p.forest)
            case .connected:
                ZStack {
                    Text(initial)
                        .font(SkogaFont.serifTitle(24).weight(.medium))
                        .foregroundStyle(p.ink)
                    Circle()
                        .fill(p.forest)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(p.paper, lineWidth: 1.5))
                        .overlay(Image(skoga: .check).skogaIconSize(10)
                            .foregroundStyle(Color.oklch(0.97, 0.02, 90)))
                        .offset(x: 22, y: 22)
                }
            }
        }
    }

    private var initial: String {
        let acct = state.data.github?.account ?? "M"
        return String(acct.prefix(1)).uppercased()
    }

    @ViewBuilder
    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch localState {
            case .idle:        idleInfo
            case .connecting:  connectingInfo
            case .connected:   connectedInfo
            }
        }
    }

    private var idleInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Connect a GitHub account")
                .font(SkogaFont.serifName(18).weight(.medium))
                .foregroundStyle(p.ink)
            Text("We'll open a browser tab. Approve in one click.")
                .font(SkogaFont.body(12.5))
                .foregroundStyle(p.inkMute)
            VStack(alignment: .leading, spacing: 4) {
                permRow("Read repos & orgs you select")
                permRow("Push branches & open PRs as you")
                permRow("Read PR review threads to loop back to agents")
            }
            .padding(.top, 6)
        }
    }

    private var connectingInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Waiting for GitHub…")
                .font(SkogaFont.serifName(18).weight(.medium))
                .foregroundStyle(p.ink)
            Text("Approve the request in your browser, then come back.")
                .font(SkogaFont.body(12.5))
                .foregroundStyle(p.inkMute)
        }
    }

    @ViewBuilder
    private var connectedInfo: some View {
        if let info = state.data.github {
            VStack(alignment: .leading, spacing: 4) {
                (Text("Connected as ").foregroundStyle(p.ink) +
                 Text("@\(info.account)").foregroundStyle(p.forest).fontWeight(.semibold))
                    .font(SkogaFont.serifName(18).weight(.medium))
                Text("\(info.orgs) organizations · \(info.repos) repositories accessible")
                    .font(SkogaFont.body(12.5))
                    .foregroundStyle(p.inkMute)
                HStack(spacing: 7) {
                    Image(skoga: .check).skogaIconSize(11).foregroundStyle(p.forest)
                    Text("Granted: read · push · review")
                        .font(SkogaFont.mono(11))
                        .foregroundStyle(p.ink2)
                }
                .padding(.top, 6)
            }
        }
    }

    private func permRow(_ text: String) -> some View {
        HStack(spacing: 7) {
            Image(skoga: .check).skogaIconSize(11)
                .foregroundStyle(p.inkFaint)
            Text(text)
                .font(SkogaFont.mono(11))
                .foregroundStyle(p.inkMute)
        }
    }

    @ViewBuilder
    private var actionBlock: some View {
        switch localState {
        case .idle:
            Button(action: connect) {
                HStack(spacing: 6) {
                    Image(skoga: .github).skogaIconSize(13)
                    Text("Connect GitHub").font(SkogaFont.bodyMedium(13))
                }
                .foregroundStyle(Color.oklch(0.97, 0.02, 90))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.forest))
            }
            .buttonStyle(.plain)
        case .connecting:
            EmptyView()
        case .connected:
            OBGhostButton(label: "Reconnect") {
                localState = .idle
            }
        }
    }

    private func connect() {
        localState = .connecting
        // Wizard-time stub: the OAuth round-trip happens in Settings ·
        // GitHub against the real `gh auth login --web` flow. Onboarding
        // just records the user's intent + a placeholder account so the
        // remaining steps can reference the connection — they pick the
        // real one up the first time Settings refreshes.
        connectTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            // Honour skip / back navigation that fired while the stub
            // was sleeping; without this, the user's explicit Skip would
            // be silently overridden by the delayed write below.
            guard !Task.isCancelled else { return }
            state.update {
                $0.github = OnboardingData.GitHubInfo(account: "mikael-w", orgs: 14, repos: 47)
            }
            localState = .connected
            connectTask = nil
        }
    }
}
