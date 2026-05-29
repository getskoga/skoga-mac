import SwiftUI

/// History view — the user's archive of completed / exited / killed /
/// PR-landed sessions. Reads `coordinator.history` (populated by
/// `loadHistory(reset:)`) and renders a search-and-filter toolbar above
/// a scrolling table of rows. Clicking a row opens the conversation
/// surface in read-only mode (gated inside ConversationView itself —
/// see Phase 4).
struct HistoryView: View {
    @Environment(\.palette) private var p
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(HistoryState.self) private var history

    var body: some View {
        VStack(spacing: 0) {
            HistoryToolbar()
            content
        }
        // One auto-load lifecycle: fires on first appearance and on every
        // date-range change (the chip mutates `history.dateRange`, the
        // view rebuilds, the id changes, the task re-fires). Keeps the
        // load gated to a single in-flight task and avoids the double-
        // fetch that an inner `.task` on `loadingState` would produce
        // after a chip click already kicked one off.
        .task(id: history.dateRange) {
            await coordinator.loadHistory(reset: true)
        }
    }

    @ViewBuilder private var content: some View {
        // Outer guard on emptiness so transient `.loading` / `.error`
        // states during pagination don't blow the user's already-loaded
        // rows off screen. Only a fully-empty list collapses to the
        // dedicated full-surface affordances below.
        if history.sessions.isEmpty {
            switch history.loadState {
            case .idle, .loading:    loadingState
            case .error(let msg):    errorState(message: msg)
            case .loaded:            list
            }
        } else {
            list
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text("Loading history…")
                .font(SkogaFont.small(11.5))
                .foregroundStyle(p.inkMute)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.paper)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(skoga: .alert).skogaIconSize(20)
                .foregroundStyle(p.ember)
            Text("Couldn't load history")
                .font(SkogaFont.bodyMedium(13))
                .foregroundStyle(p.ink)
            Text(message)
                .font(SkogaFont.small(11.5))
                .foregroundStyle(p.inkMute)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                Task { await coordinator.loadHistory(reset: true) }
            } label: {
                Text("Retry")
                    .font(SkogaFont.smallMedium(11.5))
                    .padding(.horizontal, 14).frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .fill(p.paper2)
                            .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                    )
                    .foregroundStyle(p.ink2)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.paper)
    }

    private var list: some View {
        let rows = history.filteredSessions
        return ScrollView {
            LazyVStack(spacing: 0) {
                HistoryHeaderRow()
                if rows.isEmpty {
                    emptyRow
                } else {
                    ForEach(rows) { agent in
                        HistoryRow(
                            agent: agent,
                            onOpen: { coordinator.openConversation(for: agent.id) },
                            onAttach: { Task { await coordinator.attach(agentId: agent.id) } }
                        )
                    }
                }
                footer
            }
            .padding(.horizontal, Tokens.Pad.viewX)
            .padding(.top, Tokens.Pad.viewY)
            .padding(.bottom, 28)
        }
        .background(p.paper)
    }

    private var emptyRow: some View {
        VStack(spacing: 6) {
            Text(history.query.isEmpty ? "No sessions in this range." : "No matches for \"\(history.query)\".")
                .font(SkogaFont.body(13))
                .foregroundStyle(p.ink2)
            Text(history.query.isEmpty
                 ? "Completed runs will show up here once they wind down."
                 : "Try a different search term or widen the date range.")
                .font(SkogaFont.small(11.5))
                .foregroundStyle(p.inkMute)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    @ViewBuilder private var footer: some View {
        if history.hasMore || history.totalEstimate != nil {
            HStack(spacing: 12) {
                if let total = history.totalEstimate {
                    Text("Showing \(history.sessions.count) of \(total)")
                        .font(SkogaFont.monoSmall(10.5))
                        .foregroundStyle(p.inkMute)
                }
                Spacer(minLength: 0)
                if history.hasMore {
                    LoadMoreButton(busy: history.loadState == .loading) {
                        Task { await coordinator.loadHistory(reset: false) }
                    }
                }
            }
            .padding(.top, 18)
        }
    }
}

private struct LoadMoreButton: View {
    @Environment(\.palette) private var p
    let busy: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .progressViewStyle(.circular)
                } else {
                    Image(skoga: .chevron).skogaIconSize(11)
                }
                Text(busy ? "Loading…" : "Load more")
                    .font(SkogaFont.smallMedium(11.5))
            }
            .foregroundStyle(hovering && !busy ? p.ink : p.ink2)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(hovering && !busy ? p.paper3 : p.paper2)
                    .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
            )
            .opacity(busy ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onHover { hovering = $0 }
    }
}
