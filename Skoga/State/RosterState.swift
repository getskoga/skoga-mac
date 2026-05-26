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
    }

    func apply(activity next: [Double]) {
        if activity != next { activity = next }
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
    }

    struct Spend { let today: Double; let budget: Double }

    var counts: Counts {
        Counts(
            total:    agents.count,
            running:  agents.filter { $0.status == .running  }.count,
            blocked:  agents.filter { $0.status == .blocked  }.count,
            prOpen:   agents.filter { $0.status == .prOpen   }.count,
            done:     agents.filter { $0.status == .done     }.count,
            idle:     agents.filter { $0.status == .idle     }.count,
            stopping: agents.filter { $0.status == .stopping }.count,
            exited:   agents.filter { $0.status == .exited   }.count,
            tokens:   agents.reduce(0) { $0 + $1.tokens }
        )
    }

    var spend: Spend { Spend(today: agents.reduce(0) { $0 + $1.cost }, budget: 40) }

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
