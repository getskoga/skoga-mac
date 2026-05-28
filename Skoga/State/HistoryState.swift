import Foundation

/// History slice — paginated terminal-session list plus the local
/// filter state (free-text search + date range). Distinct from
/// `RosterState` so the 5s roster poll doesn't invalidate the History
/// view, and so the History view's search/filter writes don't fire
/// `@Observable` invalidations on the roster.
///
/// Server-side `since`/`until` come from the selected `DateRange` — we
/// push date filtering through the RPC so pagination doesn't fall over
/// when the user filters down to a narrow window. Free-text search
/// stays client-side over whatever pages have been loaded so far,
/// matching how `RosterState.filteredSortedAgents` filters.
@MainActor
@Observable
final class HistoryState {

    /// Discrete date windows offered as chips in the History toolbar.
    /// Mapped to a server-side `since` at fetch time; `until` is left
    /// open (the daemon's terminal-state list is already capped at
    /// retention_days).
    enum DateRange: String, CaseIterable, Hashable {
        case all, today, last7d, last30d

        var label: String {
            switch self {
            case .all:     "All time"
            case .today:   "Today"
            case .last7d:  "Last 7 days"
            case .last30d: "Last 30 days"
            }
        }

        /// `since` to send to `session.list_terminal`. `nil` for
        /// `.all` — the daemon's retention policy is the only floor.
        func since(now: Date) -> Date? {
            switch self {
            case .all:     nil
            case .today:   Calendar.current.startOfDay(for: now)
            case .last7d:  now.addingTimeInterval(-86400 * 7)
            case .last30d: now.addingTimeInterval(-86400 * 30)
            }
        }
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    /// Daemon-driven. Populated by the coordinator's `loadHistory(reset:)`
    /// which calls `apply(page:replacing:)` once per RPC round-trip.
    /// Views read but don't write — same `private(set)` discipline as
    /// `RosterState.agents`.
    private(set) var sessions: [Agent] = []
    private(set) var nextCursor: String? = nil
    private(set) var totalEstimate: Int? = nil
    private(set) var loadState: LoadState = .idle

    /// Which `DateRange` the currently-loaded `sessions` are scoped to.
    /// Tracked so the coordinator can distinguish "user re-entered the
    /// History view with no change" (skip the refetch — preserve scroll
    /// position and load-more cursor) from "user changed the date chip"
    /// (must refetch — old data doesn't match new filter). `nil` before
    /// the first successful load and after `reset()`.
    private(set) var loadedFor: DateRange? = nil

    /// UI-driven; mutated directly from the History toolbar. The
    /// coordinator observes `dateRange` and resets+refetches when it
    /// changes (date filtering is server-side). `query` stays
    /// client-side because re-fetching on every keystroke would burn
    /// the daemon for no real benefit on already-loaded pages.
    var query: String = ""
    var dateRange: DateRange = .all

    /// Apply a freshly-fetched page. `replacing == true` means this is
    /// a fresh load (initial open, date-range change, manual refresh);
    /// `false` means a "Load more" append. Both paths update the
    /// cursor + total estimate so the view's "Showing N of ~M" reads
    /// correctly between fetches.
    func apply(page: TerminalSessionPage, replacing: Bool) {
        if replacing {
            sessions = page.sessions
        } else {
            sessions.append(contentsOf: page.sessions)
        }
        nextCursor = page.nextCursor
        totalEstimate = page.totalEstimate
        loadState = .loaded
        loadedFor = dateRange
    }

    func setLoading() {
        if loadState != .loading { loadState = .loading }
    }

    func setError(_ message: String) {
        loadState = .error(message)
    }

    /// Drop everything — used when the user navigates away and we
    /// want a fresh load next time. Leaves `query`/`dateRange` in
    /// place so a user who returns sees their last filter selection.
    func reset() {
        sessions = []
        nextCursor = nil
        totalEstimate = nil
        loadState = .idle
        loadedFor = nil
    }

    var hasMore: Bool { nextCursor != nil }

    /// Client-side free-text filter over the currently-loaded pages.
    /// Mirrors `RosterState.filteredSortedAgents` — same fields, same
    /// case-insensitive substring match. Order is preserved from the
    /// daemon (newest-first by terminal-transition time).
    var filteredSessions: [Agent] {
        guard !query.isEmpty else { return sessions }
        let q = query.lowercased()
        return sessions.filter {
            $0.name.lowercased().contains(q) ||
            $0.task.lowercased().contains(q) ||
            $0.repo.lowercased().contains(q) ||
            $0.branch.lowercased().contains(q) ||
            $0.role.lowercased().contains(q)
        }
    }
}
