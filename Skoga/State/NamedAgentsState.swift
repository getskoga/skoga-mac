import Foundation

/// Permanent-agents slice — registry + the per-Norse-name counter that
/// gates the "Save as permanent agent?" footer prompt. Owned by
/// `AppCoordinator`; views read this in isolation so a registry refresh
/// from the daemon's `agents.list` poll can't invalidate the roster or
/// the conversation feed.
@MainActor
@Observable
final class NamedAgentsState {

    /// Daemon-driven from `agents.list`. The coordinator's polling
    /// loop calls `apply(agents:)`; views read but don't write —
    /// matching the `RosterState.agents` discipline so a stray view
    /// write can't diverge from the daemon's truth.
    private(set) var agents: [NamedAgent] = []

    /// Successful-runs-per-Norse-name counter that gates the
    /// "Save as permanent agent?" footer prompt. Recomputed on every
    /// roster apply by walking sessions that reached `.prMerged` /
    /// `.done` and grouping by display name. Distinct from a
    /// NamedAgent's `totalRuns` because the counter is also computed
    /// for ephemeral identities that *haven't* been saved yet — that
    /// is in fact the whole point of it.
    ///
    /// Observation-tracked so the banner re-renders the moment the
    /// counter crosses the threshold (rather than waiting for the
    /// next `agents`-driven invalidation).
    private(set) var successfulRunsByName: [String: Int] = [:]

    /// Per-session-id "save prompt dismissed" memory. The conversation
    /// footer prompt is non-blocking and can be dismissed; once
    /// dismissed for a given session id, we don't re-show it for that
    /// session even if the user navigates away and back. The slice
    /// rather than the view owns this because `ConversationView` is
    /// torn down + recreated on `agent.id` changes (id-bound
    /// rebuilds), and the dismissal needs to outlive that.
    ///
    /// Observation-tracked so the dismiss button collapses the banner
    /// immediately on click.
    private(set) var dismissedPromptSessionIds: Set<String> = []

    /// Threshold at which the "Save as permanent agent?" prompt fires.
    /// Pulled out as a static so designers can flip it during a demo
    /// (3 is a meaningful "tried it a few times" number; lower would
    /// nag, higher would never trigger in normal use).
    static let saveAsPermanentThreshold: Int = 3

    /// Diff-guard at the slice boundary: only republish `agents` when
    /// the list (id, name, role, defaults, totalRuns, lastUsed) actually
    /// changed. Without this the polling loop would force every reader
    /// of the dispatch grid + sidebar to recompute on each tick.
    func apply(agents next: [NamedAgent]) {
        if agents != next { agents = next }
    }

    /// Walk one or more agent slices and recompute the successful-runs
    /// counter from scratch. Called by `AppCoordinator` after each
    /// roster apply (live roster) and after history loads (terminal
    /// history). Variadic so a single call site can fold both sources
    /// without an intermediate concatenation.
    ///
    /// Per-call recomputation (rather than the previous incremental
    /// "insert if not already counted" approach) is the only correct
    /// shape here: history slices grow and shrink with the user's
    /// date-range chip (`.today` ↔ `.all`), so a session id that
    /// pruned out on one tick could come back on the next, and an
    /// id-dedup set would double-count it. The session id itself is
    /// inherently unique inside each slice — Set on the way in gives
    /// us natural roster+history overlap dedup. Cheap: a few hundred
    /// terminal sessions, mostly ints + small strings, runs in
    /// microseconds per refresh.
    func recountSuccessfulRuns(from slices: [Agent]...) {
        var seenIds = Set<String>()
        var counter: [String: Int] = [:]
        for slice in slices {
            for agent in slice where Self.isSuccessfulTerminal(agent.status) {
                if seenIds.insert(agent.id).inserted {
                    counter[agent.name, default: 0] += 1
                }
            }
        }
        if counter != successfulRunsByName { successfulRunsByName = counter }
    }

    /// `.prMerged` is the strongest signal (PR actually landed);
    /// `.done` covers `skoga ship`-driven teardown that didn't go
    /// through a PR (older sessions, or work that landed via a
    /// different path). `.exited` and `.prClosed` deliberately don't
    /// count — they're terminal but not successful, and counting
    /// them would surface the "save as permanent" prompt off the
    /// back of work that didn't actually ship.
    private static func isSuccessfulTerminal(_ status: AgentStatus) -> Bool {
        switch status {
        case .prMerged, .done: true
        default: false
        }
    }

    /// True when the open session's deterministic name has hit the
    /// threshold AND isn't already pinned as a permanent agent AND
    /// the prompt hasn't been dismissed for this session. The footer
    /// row reads this; the coordinator dispatches `createNamedAgent`
    /// when the user accepts.
    func shouldPromptSaveAsPermanent(for agent: Agent) -> Bool {
        guard !dismissedPromptSessionIds.contains(agent.id) else { return false }
        guard !agents.contains(where: { $0.name.caseInsensitiveCompare(agent.name) == .orderedSame }) else { return false }
        let count = successfulRunsByName[agent.name, default: 0]
        return count >= Self.saveAsPermanentThreshold
    }

    /// User clicked Dismiss on the footer prompt for this session.
    /// We keep the dismissal in memory for the app's lifetime — durable
    /// "don't ask again" is a stronger commitment than this prompt's
    /// scope warrants, and most users will either save or shrug it off.
    func dismissPrompt(for sessionId: String) {
        dismissedPromptSessionIds.insert(sessionId)
    }

    /// Drop the dismissal memory for sessions that have left both the
    /// live roster and the visible history slice. Keeps the set from
    /// growing unbounded over a long-lived app session. The counter
    /// itself is recomputed from scratch each tick (see
    /// `recountSuccessfulRuns`) so it has no per-id state to prune.
    func prune(keepingSessionIds liveIds: Set<String>) {
        dismissedPromptSessionIds = dismissedPromptSessionIds.intersection(liveIds)
    }

    /// Permanent agent matching `name` (case-insensitive), if any.
    /// Used by the conversation footer prompt to decide whether to
    /// suppress (already saved) and by the dispatch grid to mark a
    /// session row as "this is your permanent Astrid talking".
    func permanentAgent(named name: String) -> NamedAgent? {
        agents.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
