import SwiftUI

struct FilterRail: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var state: AppState

    @State private var queryDraft: String = ""
    @State private var debounceArmed: Bool = false

    var body: some View {
        let counts = state.counts
        HStack(spacing: 6) {
            chipGroup(counts: counts)
            Spacer(minLength: 0)
            searchField
            dispatchButton
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Tokens.Pad.viewX)
        .padding(.vertical, 12)
        .background(p.paper)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func chipGroup(counts: AppState.Counts) -> some View {
        HStack(spacing: 0) {
            chip(.all,     label: "All",     count: counts.total)
            divider
            chip(.running, label: "Running", count: counts.running, dot: .running)
            divider
            chip(.blocked, label: "Blocked", count: counts.blocked, dot: .blocked)
            divider
            chip(.prOpen,  label: "PR open", count: counts.prOpen,  dot: .prOpen)
            divider
            chip(.done,    label: "Done",    count: counts.done,    dot: .done)
            divider
            chip(.idle,    label: "Idle",    count: counts.idle,    dot: .idle)
            divider
            chip(.exited,  label: "Exited",  count: counts.exited,  dot: .exited)
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
    private func chip(_ value: AppState.Filter, label: String, count: Int, dot: AgentStatus? = nil) -> some View {
        let on = state.filter == value

        Button {
            state.filter = value
        } label: {
            HStack(spacing: 6) {
                if let dot { PulseDot(status: dot) }
                Text(label)
                    .font(SkogaFont.smallMedium(11.5))
                    .lineLimit(1)
                Text("\(count)")
                    .font(SkogaFont.monoSmall(10.5))
                    .foregroundStyle(on ? p.ink2 : p.inkFaint)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
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
            TextField("Filter agents, tasks, repos…", text: $queryDraft)
                .textFieldStyle(.plain)
                .font(SkogaFont.small(11.5))
                .foregroundStyle(p.ink)
                // Seed the local draft from state.query so a search
                // persisted via env var or external mutation survives a
                // view-tree teardown. `debounceArmed` flips true only
                // after the seed, so the first .task tick can't race
                // the seed and clobber state.query back to "".
                .onAppear {
                    if queryDraft != state.query { queryDraft = state.query }
                    debounceArmed = true
                }
                // Keep the draft in sync with external writes to
                // state.query (e.g., a future "clear filter" command).
                .onChange(of: state.query) { _, new in
                    if queryDraft != new { queryDraft = new }
                }
                .task(id: queryDraft) {
                    guard debounceArmed else { return }
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled, state.query != queryDraft else { return }
                    state.query = queryDraft
                }
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
