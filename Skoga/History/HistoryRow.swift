import SwiftUI

/// One terminal-session row in the History table. Mirrors the
/// `(name, task, repo, status, when, runtime, spend)` shape spelled
/// out in skoga-mac issue #34. Click invokes the row's `onOpen`
/// callback, which the parent uses to navigate into the read-only
/// conversation surface. The hover-revealed "Attach" pill and the
/// right-click "Attach to session" item both call `onAttach` to
/// revive the session in place — same id, fresh worktree, agent
/// relaunched against the same transcript.
struct HistoryRow: View {
    @Environment(\.palette) private var p
    let agent: Agent
    let onOpen: () -> Void
    let onAttach: () -> Void

    @State private var hovering = false

    var body: some View {
        // ZStack so the hover-only Attach pill captures its own clicks
        // without bubbling through the row-open Button. Nesting it
        // inside the outer Button (the obvious approach) makes the
        // pill's tap fire `onOpen` instead of `onAttach` on macOS,
        // because SwiftUI's Button container swallows interior touch
        // events regardless of `.buttonStyle(.plain)`.
        ZStack(alignment: .trailing) {
            Button(action: onOpen) {
                HStack(spacing: HistoryRowLayout.colSpacing) {
                    avatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.name)
                            .font(SkogaFont.bodyMedium(12.5))
                            .foregroundStyle(p.ink)
                            .lineLimit(1)
                        Text(agent.role)
                            .font(SkogaFont.monoTiny(9.5))
                            .tracking(0.4)
                            .foregroundStyle(p.inkFaint)
                    }
                    .frame(width: HistoryRowLayout.nameCol, alignment: .leading)

                    Text(agent.task)
                        .font(SkogaFont.body(12.5))
                        .foregroundStyle(p.ink2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.repo)
                            .font(SkogaFont.monoSmall(10.5))
                            .foregroundStyle(p.ink2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(agent.branchSlug)
                            .font(SkogaFont.monoTiny(9.5))
                            .foregroundStyle(p.inkFaint)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(width: HistoryRowLayout.repoCol, alignment: .leading)

                    StatusPill(status: agent.status)
                        .frame(width: HistoryRowLayout.statusCol, alignment: .leading)

                    Text(WhenFormatter.relative(from: agent.createdAt))
                        .font(SkogaFont.monoSmall(10.5))
                        .foregroundStyle(p.inkMute)
                        .frame(width: HistoryRowLayout.whenCol, alignment: .leading)

                    Text(agent.runtime)
                        .font(SkogaFont.monoSmall(10.5))
                        .foregroundStyle(p.inkMute)
                        .frame(width: HistoryRowLayout.runtimeCol, alignment: .leading)

                    Text(String(format: "$%.2f", agent.cost))
                        .font(SkogaFont.monoSmall(10.5))
                        .foregroundStyle(p.ink2)
                        .frame(width: HistoryRowLayout.spendCol, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .background(hovering ? p.paper2 : .clear)
                .overlay(alignment: .bottom) { Hairline() }
            }
            .buttonStyle(.plain)

            if hovering && agent.status.canAttach {
                // Hover-only quick action — revealed at the right edge of
                // the row so the user can revive without first opening the
                // read-only conversation. Offset inside the row's padding
                // so it floats over the spend column without permanently
                // crowding it; the row is wide enough that occluding the
                // last cell on hover is preferable to reserving a column.
                // Gated on `canAttach` so Done/Killed rows (worktrees
                // gone, daemon would reject) don't surface a button we
                // know would fail.
                AttachQuickAction(onAttach: onAttach)
                    .padding(.trailing, 16)
                    .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            if agent.status.canAttach {
                Button {
                    onAttach()
                } label: {
                    Label("Attach to session", systemImage: SkogaIcon.attach.symbol)
                }
            }
        }
    }

    private var avatar: some View {
        Text(agent.initials)
            .font(SkogaFont.serifName(13))
            .foregroundStyle(p.ink2)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7).fill(p.paper3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7).stroke(p.rule, lineWidth: Tokens.Hairline.width)
            )
    }
}

/// Hover-revealed "Attach" pill at the right edge of a History row.
/// Pulled out into its own view so the row's `onAttach` callback can
/// stop the parent button's tap before the row-open action fires —
/// without a nested Button + `buttonStyle(.plain)`, the click would
/// bubble up to the row's onOpen and dump the user into the
/// read-only conversation instead of starting the revive.
private struct AttachQuickAction: View {
    @Environment(\.palette) private var p
    let onAttach: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onAttach) {
            HStack(spacing: 4) {
                Image(skoga: .attach).skogaIconSize(11)
                Text("Attach")
                    .font(SkogaFont.smallMedium(11))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(hovering ? p.forest.opacity(0.9) : p.forest)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Re-arm this session and resume working with its agent.")
    }
}

/// Header row above the History table — same column geometry as
/// `HistoryRow` so labels line up over their columns.
struct HistoryHeaderRow: View {
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: HistoryRowLayout.colSpacing) {
            Color.clear.frame(width: 28, height: 14)
            label("Agent").frame(width: HistoryRowLayout.nameCol, alignment: .leading)
            label("Task").frame(maxWidth: .infinity, alignment: .leading)
            label("Repo · branch").frame(width: HistoryRowLayout.repoCol, alignment: .leading)
            label("Status").frame(width: HistoryRowLayout.statusCol, alignment: .leading)
            label("When").frame(width: HistoryRowLayout.whenCol, alignment: .leading)
            label("Runtime").frame(width: HistoryRowLayout.runtimeCol, alignment: .leading)
            label("Spend").frame(width: HistoryRowLayout.spendCol, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(SkogaFont.monoTiny(9.5))
            .tracking(0.95)
            .foregroundStyle(p.inkFaint)
    }
}

/// Shared column widths so header + row stay aligned without each
/// having to reach into the other for measurement.
enum HistoryRowLayout {
    static let colSpacing: CGFloat = 12
    static let nameCol: CGFloat = 130
    static let repoCol: CGFloat = 180
    static let statusCol: CGFloat = 110
    static let whenCol: CGFloat = 110
    static let runtimeCol: CGFloat = 70
    static let spendCol: CGFloat = 70
}

/// Relative-date formatter used by the History row. Mirrors the
/// terse shape the side-panel timeline uses ("12m", "2h", "3d") and
/// falls through to a calendar date for anything older than a week
/// so the user gets an absolute landmark for distant sessions.
enum WhenFormatter {
    static func relative(from date: Date, now: Date = Date()) -> String {
        let delta = now.timeIntervalSince(date)
        if delta < 60 { return "just now" }
        if delta < 3600 {
            let m = Int(delta / 60)
            return "\(m)m ago"
        }
        if delta < 86400 {
            let h = Int(delta / 3600)
            return "\(h)h ago"
        }
        if delta < 86400 * 7 {
            let d = Int(delta / 86400)
            return "\(d)d ago"
        }
        return absoluteFormatter.string(from: date)
    }

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}
