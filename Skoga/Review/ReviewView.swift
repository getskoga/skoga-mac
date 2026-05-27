import SwiftUI

struct ReviewView: View {
    @Environment(\.palette) private var p
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(RosterState.self) private var roster

    /// Review surface = agents with a PR open on GitHub. We *intentionally*
    /// don't list agents that the manager hasn't landed yet — there's no
    /// reliable "agent thinks it's done" signal, and surfacing every idle
    /// run here would bury the things that actually need a reviewer's eye.
    /// Manager-driven: the moment `skoga land` succeeds and `prUrl` lands
    /// on the session, the card shows up here.
    ///
    /// `prUrl` alone isn't enough: it stays set through `.prMerged` /
    /// `.prClosed` / `.shipping` / `.done` (the daemon keeps the landed
    /// URL on the session for the audit log). Status-gate to `.prOpen`
    /// so a session in its brief auto-ship window doesn't linger here
    /// — by then the PR is no longer up for review.
    private var inReview: [Agent] {
        roster.agents.filter { $0.prUrl != nil && $0.status == .prOpen }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Up for review")
                    .font(SkogaFont.serifTitle(26))
                    .foregroundStyle(p.ink)
                Text("Agents with an open pull request. Review feedback loops back to the agent automatically.")
                    .font(SkogaFont.body(13))
                    .foregroundStyle(p.inkMute)
                    .lineSpacing(13 * 0.5)
                    .frame(maxWidth: 540, alignment: .leading)
                    .padding(.top, 6).padding(.bottom, 22)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 320), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(inReview) { a in
                        AgentCard(agent: a) {
                            coordinator.openConversation(for: a.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 28)
        }
        .background(p.paper)
    }
}
