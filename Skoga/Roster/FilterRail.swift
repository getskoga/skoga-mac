import SwiftUI

struct FilterRail: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            chipGroup
            Spacer(minLength: 0)
            searchField
            dispatchButton
        }
        .padding(.horizontal, Tokens.Pad.viewX)
        .padding(.vertical, 12)
        .background(p.paper)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var chipGroup: some View {
        HStack(spacing: 0) {
            chip(.all,     label: "All")
            divider
            chip(.running, label: "Running", dot: .running)
            divider
            chip(.blocked, label: "Blocked", dot: .blocked)
            divider
            chip(.review,  label: "Review",  dot: .review)
            divider
            chip(.done,    label: "Done",    dot: .done)
            divider
            chip(.idle,    label: "Idle",    dot: .idle)
        }
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                .fill(p.paper2)
                .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.chip))
    }

    private var divider: some View {
        Hairline(axis: .vertical)
    }

    @ViewBuilder
    private func chip(_ value: AppState.Filter, label: String, dot: AgentStatus? = nil) -> some View {
        let on = state.filter == value
        let count: Int = {
            switch value {
            case .all: state.counts.total
            case .running: state.counts.running
            case .blocked: state.counts.blocked
            case .review: state.counts.review
            case .done: state.counts.done
            case .idle: state.counts.idle
            }
        }()

        Button {
            state.filter = value
        } label: {
            HStack(spacing: 6) {
                if let dot { PulseDot(status: dot) }
                Text(label)
                    .font(SkogaFont.smallMedium(11.5))
                Text("\(count)")
                    .font(SkogaFont.monoSmall(10.5))
                    .foregroundStyle(on ? p.ink2 : p.inkFaint)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(on ? p.ink : p.inkMute)
            .background(on ? p.paper4 : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(skoga: .search).skogaIconSize(12).foregroundStyle(p.inkMute)
            TextField("Filter agents, tasks, repos…", text: $state.query)
                .textFieldStyle(.plain)
                .font(SkogaFont.small(11.5))
                .foregroundStyle(p.ink)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .frame(minWidth: 200)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                .fill(p.paper2)
                .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
        )
    }

    private var dispatchButton: some View {
        Button {
            state.view = .dispatch
            state.openAgentId = nil
        } label: {
            HStack(spacing: 6) {
                Image(skoga: .plus).skogaIconSize(13)
                Text("Dispatch")
                    .font(SkogaFont.bodyMedium(12))
            }
            .padding(.horizontal, 14)
            .frame(height: 28)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.forest)
            )
        }
        .buttonStyle(.plain)
    }
}
