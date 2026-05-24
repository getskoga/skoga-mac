import SwiftUI

/// Banner shown at the top of `MainWindow` whenever the app isn't talking to
/// a real skogad. Renders the user-facing recovery hint (install vs start).
struct DaemonStatusBanner: View {
    @Environment(\.palette) private var p
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
                headline: "Mock mode",
                detail: "Seed data only — SKOGA_USE_MOCK is set",
                hint: nil
            )
        }
    }
}
