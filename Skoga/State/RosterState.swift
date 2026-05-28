import Foundation

/// Roster slice — the agent roll-call plus everything you'd reasonably
/// derive from it (counts, spend, filtered list). Owned by
/// `AppCoordinator`; views read this in isolation so a roster filter
/// change can't invalidate the conversation feed or any modal.
@MainActor
@Observable
final class RosterState {

    enum Filter: String, CaseIterable, Hashable {
        case all, running, blocked, prOpen, done, idle, stopping, exited
    }

    /// Daemon-driven. The coordinator's `refresh()` calls `apply(agents:)` /
    /// `apply(activity:)` from the JSON-RPC loop; views read but don't write
    /// — the old `AppState.agents` was `private(set)` for the same reason
    /// (a stray view-side write would diverge from the daemon's truth).
    private(set) var agents: [Agent] = []
    private(set) var activity: [Double] = []

    /// Daemon-aggregated total spend (USD) across every session started
    /// today, terminal sessions included. Populated by the coordinator
    /// from `spend.today`; `nil` against older daemons that don't speak
    /// the RPC, in which case `spend.today` (below) falls back to
    /// summing the live `agents` array. Kept separate from `agents` so
    /// terminal sessions contribute to the cap readout without polluting
    /// the open-roster surfaces.
    private(set) var todaySpend: Double?

    /// First-observed timestamp for each session currently in `.prOpen`.
    /// Populated and pruned by `apply(agents:)` so an entry exists iff
    /// that session id is still up-for-review on the latest poll. The
    /// Cockpit's "avg age" subline averages `now - timestamp` across
    /// these, which means sessions that were already `.prOpen` when the
    /// app launched start at 0m and grow from there — accurate historical
    /// ages would need a `pr_opened_at` field on the daemon's Session
    /// record; the client-observed first-sighting is a deliberate
    /// degradation to keep this Mac-only.
    ///
    /// `@ObservationIgnored` because every state change that would shift
    /// the map (a new PR opening, an existing one merging) also reassigns
    /// `agents` on the same `apply(agents:)` call. The `agents` write
    /// already invalidates `counts` readers; tracking this field too
    /// would just fire a second redundant invalidation on the same tick.
    @ObservationIgnored private(set) var prOpenedAt: [String: Date] = [:]

    /// UI-driven; mutated directly from `FilterRail` and any future filter
    /// surface (command palette, etc.) without going through the coordinator.
    var filter: Filter = .all
    var query: String = ""

    /// Diff-guard at the slice boundary so the `@Observable` write only
    /// fires when the agent list actually changed. Without this the 5s
    /// polling loop would re-publish identical arrays and force every
    /// view that reads `agents` to recompute.
    func apply(agents next: [Agent]) {
        if agents != next { agents = next }
        syncPrOpenedAt(against: next)
    }

    /// Stamp newly-`.prOpen` session ids with `now()` and drop entries
    /// for sessions that have left the state. Runs after every poll —
    /// gated on actual map changes so a tick that doesn't add or remove
    /// a `.prOpen` session doesn't invalidate `@Observable` readers.
    private func syncPrOpenedAt(against next: [Agent]) {
        let currentlyPrOpen = Set(next.lazy.filter { $0.status == .prOpen }.map(\.id))
        let now = Date()
        var updated = prOpenedAt
        var changed = false
        for id in currentlyPrOpen where updated[id] == nil {
            updated[id] = now
            changed = true
        }
        for id in Array(updated.keys) where !currentlyPrOpen.contains(id) {
            updated.removeValue(forKey: id)
            changed = true
        }
        if changed { prOpenedAt = updated }
    }

    func apply(activity next: [Double]) {
        if activity != next { activity = next }
    }

    func apply(todaySpend next: Double?) {
        if todaySpend != next { todaySpend = next }
    }

    struct Counts {
        let total: Int
        let running: Int
        let blocked: Int
        let prOpen: Int
        let done: Int
        let idle: Int
        let stopping: Int
        let exited: Int
        let tokens: Int
        /// Average age of currently-`.prOpen` sessions, in seconds, since
        /// the Mac first observed each one in that state. `nil` when no
        /// PRs are up for review — the Cockpit renders that as "—".
        let reviewAvgAge: TimeInterval?
    }

    /// Today's spend across the live roster. The daily *cap* (the
    /// denominator the Cockpit / Telemetry / Budgets surfaces compare
    /// against) is read directly from `@AppStorage(BudgetPrefs.Cap.daily)`
    /// in each consuming View so SwiftUI invalidates on a slider drag;
    /// piping it through this slice would lock the Cockpit strip to
    /// the next 5s poll for slider edits.
    struct Spend { let today: Double }

    /// `reviewAvgAge` is computed from `Date()` at evaluation time, but
    /// SwiftUI only re-renders the Cockpit when `agents` changes — so the
    /// rendered minute number ticks once per 5s poll, not on a wall clock.
    /// Matches the `runtime` label's behavior on the Agent card; a
    /// `TimelineView` wrapper to tick continuously would force the whole
    /// cell to re-render every second for one minor cosmetic gain.
    var counts: Counts {
        let now = Date()
        let ages = agents.lazy
            .filter { $0.status == .prOpen }
            .compactMap { self.prOpenedAt[$0.id] }
            .map { now.timeIntervalSince($0) }
        let avg: TimeInterval? = {
            var total: TimeInterval = 0
            var n = 0
            for age in ages { total += age; n += 1 }
            return n == 0 ? nil : total / Double(n)
        }()
        return Counts(
            total:    agents.count,
            running:  agents.filter { $0.status == .running  }.count,
            blocked:  agents.filter { $0.status == .blocked  }.count,
            prOpen:   agents.filter { $0.status == .prOpen   }.count,
            done:     agents.filter { $0.status == .done     }.count,
            idle:     agents.filter { $0.status == .idle     }.count,
            stopping: agents.filter { $0.status == .stopping }.count,
            exited:   agents.filter { $0.status == .exited   }.count,
            tokens:   agents.reduce(0) { $0 + $1.tokens },
            reviewAvgAge: avg
        )
    }

    /// `today` prefers the daemon's `spend.today` rollup (terminal
    /// sessions included) and only falls back to summing the live
    /// `agents` array when the daemon hasn't supplied a number yet
    /// (cold start, older daemon without the RPC). The roster is the
    /// canonical client-side cost source — anything in the chrome that
    /// wants "today's spend" reads through this slice. The matching daily
    /// cap is read by each View via `@AppStorage(BudgetPrefs.Cap.daily)`.
    var spend: Spend {
        Spend(today: todaySpend ?? agents.reduce(0) { $0 + $1.cost })
    }

    var filteredSortedAgents: [Agent] {
        var xs = agents
        if filter != .all, let status = AgentStatus(rawValue: filter.rawValue) {
            xs = xs.filter { $0.status == status }
        }
        if !query.isEmpty {
            let q = query.lowercased()
            xs = xs.filter {
                $0.name.lowercased().contains(q) ||
                $0.task.lowercased().contains(q) ||
                $0.repo.lowercased().contains(q) ||
                $0.role.lowercased().contains(q)
            }
        }
        return xs.sorted { $0.status.sortRank < $1.status.sortRank }
    }
}
