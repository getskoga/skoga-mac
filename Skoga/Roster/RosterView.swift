import SwiftUI

struct RosterView: View {
    @Environment(\.palette) private var p
    @Environment(\.colorScheme) private var scheme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(RosterState.self) private var roster
    @AppStorage(AppearancePrefs.showIllustrations) private var showIllustrations: Bool = AppearancePrefs.showIllustrationsDefault

    var body: some View {
        VStack(spacing: 0) {
            FilterRail()
            if roster.agents.isEmpty {
                emptyState
            } else {
                grid
            }
        }
    }

    private var grid: some View {
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

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            if showIllustrations {
                AnimatedSVG(assetName: scheme == .dark ? "KongleSleeping" : "KongleCoffee")
                    .frame(width: 220, height: 220)
            }
            VStack(spacing: 4) {
                Text("No agents in your roster.")
                    .font(SkogaFont.bodyMedium(13))
                    .foregroundStyle(p.ink2)
                Text("Dispatch your first agent to get started.")
                    .font(SkogaFont.small(11.5))
                    .foregroundStyle(p.inkMute)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.paper)
    }
}
