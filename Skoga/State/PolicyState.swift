import Foundation

/// Policy slice — the containment denial log plus the in-flight promote
/// state. Distinct from `RosterState` so the panel's promote/refresh
/// churn doesn't invalidate the roster, and so a denial poll on the 5s
/// tick doesn't force the conversation feed to recompute.
///
/// Daemon-driven: the coordinator's `refresh()` rides `policy.denials`
/// along on every poll (so the sidebar badge stays live), and the
/// panel's `.task` calls `loadDenials()` once on open for its
/// loading/error affordances. Views read but don't write the `denials`
/// list — same `private(set)` discipline as `RosterState.agents`.
@MainActor
@Observable
final class PolicyState {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    private(set) var denials: [RPCDenial] = []
    private(set) var loadState: LoadState = .idle

    /// Denial ids with a `policy.promote` call in flight. Used to disable
    /// the row's scope picker + show a spinner so a double-click can't
    /// fire two promotions for the same denial. `@ObservationIgnored`
    /// off — the row reads it to switch its trailing control.
    private(set) var promoting: Set<String> = []

    /// Apply a freshly-fetched denial list. Diff-guarded so an identical
    /// poll result (the common case once the guild settles) doesn't
    /// re-publish the array and force every row to recompute. `loadState`
    /// only advances to `.loaded` when it isn't already there, so a
    /// steady 5s poll doesn't fire a redundant `@Observable` invalidation
    /// on the panel chrome.
    func apply(denials next: [RPCDenial]) {
        if denials != next { denials = next }
        if loadState != .loaded { loadState = .loaded }
    }

    func setLoading() {
        if loadState != .loading { loadState = .loading }
    }

    func setError(_ message: String) {
        loadState = .error(message)
    }

    /// Drop a single row by id — used by the coordinator's promote action
    /// so a just-allowed denial disappears the moment its RPC returns,
    /// rather than lingering until the next ride-along poll. The poll
    /// won't re-add it (the daemon dropped it from the log on promote),
    /// so this is a clean optimistic removal.
    func remove(id: String) {
        denials.removeAll { $0.id == id }
    }

    func setPromoting(_ inFlight: Bool, id: String) {
        if inFlight { promoting.insert(id) } else { promoting.remove(id) }
    }

    func isPromoting(_ id: String) -> Bool { promoting.contains(id) }

    /// Promotable (non-floor) denial count — drives the sidebar badge and
    /// the context label. Deny-floor entries are excluded because they're
    /// not actionable: surfacing them in the badge would nag the user
    /// about rules they can never clear.
    var pendingCount: Int {
        denials.lazy.filter { !$0.floor }.count
    }
}
