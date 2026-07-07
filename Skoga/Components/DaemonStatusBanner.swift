import SwiftUI

/// Banner shown at the top of `MainWindow` whenever the app isn't talking to
/// a real skogad. Renders the user-facing recovery hint (install vs start)
/// plus the demo-mode toggle: "Try the demo" swaps in the seeded mock client
/// when skogad isn't reachable — the only way a fresh install (or an App
/// Review tester, who can't set `SKOGA_USE_MOCK`) can see the product
/// without the daemon — and "Exit demo" swaps back to the live client.
struct DaemonStatusBanner: View {
    @Environment(\.palette) private var p
    @Environment(AppCoordinator.self) private var coordinator
    let status: DaemonStatus

    var body: some View {
        if let copy = copy {
            HStack(spacing: 10) {
                Circle()
                    .fill(p.ember)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(p.ember.opacity(0.18), lineWidth: 3))
                Text(copy.headline)
                    .font(SkogaFont.bodyMedium(12))
                    .foregroundStyle(p.ink)
                Text(copy.detail)
                    .font(SkogaFont.mono(11))
                    .foregroundStyle(p.inkMute)
                Spacer(minLength: 0)
                if let hint = copy.hint {
                    Text(hint)
                        .font(SkogaFont.mono(11))
                        .foregroundStyle(p.inkFaint)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4).fill(p.paper2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                        )
                }
                if let action = action {
                    Button(action: action.perform) {
                        Text(action.label)
                            .font(SkogaFont.smallMedium(11))
                            .foregroundStyle(p.ink)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4).fill(p.paper)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(p.ruleHard, lineWidth: Tokens.Hairline.width)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.emberSoft.opacity(0.4))
            .overlay(alignment: .bottom) { Hairline() }
        }
    }

    private struct Copy {
        let headline: String
        let detail: String
        let hint: String?
    }

    private struct BannerAction {
        let label: String
        let perform: () -> Void
    }

    private var copy: Copy? {
        switch status {
        case .connected:
            return nil
        case .connecting:
            return Copy(headline: "Connecting…", detail: "Reaching skogad on ~/.skoga/sock", hint: nil)
        case .notRunning(let detail):
            return Copy(
                headline: "skogad not reachable",
                detail: detail,
                hint: "brew install getskoga/tap/skoga · skoga daemon start"
            )
        case .mock:
            return Copy(
                headline: "Demo mode",
                detail: "Sample agents only — not connected to a real daemon",
                hint: nil
            )
        }
    }

    private var action: BannerAction? {
        switch status {
        case .notRunning:
            return BannerAction(label: "Try the demo") {
                Task { await coordinator.enterDemoMode() }
            }
        case .mock:
            return BannerAction(label: "Exit demo") {
                Task { await coordinator.exitDemoMode() }
            }
        case .connected, .connecting:
            return nil
        }
    }
}
