import SwiftUI

struct RosterView: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            FilterRail()
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 320), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(state.filteredSortedAgents) { agent in
                        AgentCard(agent: agent) {
                            state.openConversation(for: agent.id)
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
