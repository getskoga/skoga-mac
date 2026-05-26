import SwiftUI

/// Destructive-confirm modal for the Stop button in `ConvHeader`. Kill
/// tears the agent down — tmux pane gone, worktree slated for cleanup,
/// conversation frozen. There's no undo, so we gate it behind a warning
/// instead of wiring the button straight to `state.kill`.
struct StopConfirmModal: View {
    @Environment(\.palette) private var p
    @Environment(AppState.self) private var state
    let agent: Agent

    @State private var submitting = false

    var body: some View {
        ZStack {
            p.modalScrim
                .ignoresSafeArea()
                .onTapGesture {
                    if !submitting { state.stopAgentId = nil }
                }

            VStack(spacing: 0) {
                head
                bodyText
                foot
            }
            .frame(width: 440)
            .background(p.paper)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.modal)
                    .stroke(p.ruleHard, lineWidth: Tokens.Hairline.width)
            )
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.modal))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 20)
        }
    }

    private var head: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(p.emberSoft)
                Image(skoga: .alert).skogaIconSize(18).foregroundStyle(p.ember)
            }
            .frame(width: 36, height: 36)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.ember.opacity(0.4), lineWidth: Tokens.Hairline.width))

            VStack(alignment: .leading, spacing: 2) {
                Text("Stop \(agent.name)?")
                    .font(SkogaFont.serifHeading(21))
                    .foregroundStyle(p.ink)
                Text("\(agent.repo) · \(agent.branch)")
                    .font(SkogaFont.mono(11))
                    .foregroundStyle(p.inkMute)
            }
            Spacer(minLength: 0)
            Button { if !submitting { state.stopAgentId = nil } } label: {
                Image(skoga: .close).skogaIconSize(12)
                    .foregroundStyle(p.inkMute)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .fill(p.paper2)
                            .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                    )
            }
            .buttonStyle(.plain)
            .disabled(submitting)
        }
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 14)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var bodyText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This will kill the entire session.")
                .font(SkogaFont.bodyMedium(13.5))
                .foregroundStyle(p.ink)
            Text("The tmux pane will be torn down and the worktree cleaned up. The conversation is preserved, but the agent can't resume — you'd need to dispatch a new run. To stop just the current turn without ending the session, use Pause instead.")
                .font(SkogaFont.body(13))
                .foregroundStyle(p.ink2)
                .lineSpacing(13 * 0.45)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22).padding(.vertical, 18)
    }

    private var foot: some View {
        HStack(spacing: 8) {
            Spacer()
            Button {
                if !submitting { state.stopAgentId = nil }
            } label: {
                Text("Cancel")
                    .font(SkogaFont.smallMedium(11.5))
                    .foregroundStyle(p.ink2)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .fill(p.paper)
                            .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                    )
            }
            .buttonStyle(.plain)
            .disabled(submitting)

            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 6) {
                    if submitting {
                        ProgressView()
                            .controlSize(.small)
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(skoga: .stop).skogaIconSize(12)
                    }
                    Text(submitting ? "Stopping…" : "Stop session")
                        .font(SkogaFont.bodyMedium(12))
                }
                .padding(.horizontal, 14)
                .frame(height: 28)
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.ember))
                .opacity(submitting ? 0.7 : 1)
            }
            .buttonStyle(.plain)
            .disabled(submitting)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(p.paper2)
        .overlay(alignment: .top) { Hairline() }
    }

    private func submit() async {
        submitting = true
        let id = agent.id
        await state.kill(agentId: id)
        state.stopAgentId = nil
    }
}
