import SwiftUI

struct RosterView: View {
    @Environment(\.palette) private var p
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(RosterState.self) private var roster

    var body: some View {
        VStack(spacing: 0) {
            FilterRail()
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 320), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(roster.filteredSortedAgents) { agent in
                        AgentCard(agent: agent) {
                            coordinator.openConversation(for: agent.id)
                        }
                    }
                }
                .padding(.horizontal, Tokens.Pad.viewX)
                .padding(.top, Tokens.Pad.viewY)
                .padding(.bottom, 28)
            }
            .background(p.paper)
        }
    }
}
