import SwiftUI

struct ReviewView: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var state: AppState

    private var inReview: [Agent] {
        state.agents.filter { $0.status == .review }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Up for review")
                    .font(SkogaFont.serifTitle(26))
                    .foregroundStyle(p.ink)
                Text("These agents finished their runs. Open as PRs on GitHub — review feedback loops back to the agent.")
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
                            state.openConversation(for: a.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 28)
        }
        .background(p.paper)
    }
}
