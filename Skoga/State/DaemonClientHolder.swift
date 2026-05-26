import Foundation

/// Daemon slice — the JSON-RPC client, its connection health, and the
/// gh-status cache that Settings → GitHub and the PR modal both read.
/// Polling/event loops that touch *other* slices live on
/// `AppCoordinator`; this slice only owns the daemon-derived facts.
@MainActor
@Observable
final class DaemonClientHolder {
    let client: DaemonClient
    let isMock: Bool

    /// All daemon-derived facts below — set internally by
    /// `refreshGitHubStatus()` or from the coordinator's refresh path
    /// via the `apply*` / `set*` helpers. Views read but don't write.
    private(set) var daemonStatus: DaemonStatus

    /// Last fetched `gh` CLI status from the daemon. `nil` before the
    /// first fetch completes — Settings → GitHub renders a loading row
    /// in that window, and the PR modal's reviewer field falls back to
    /// the "+ add" placeholder.
    private(set) var githubStatus: RPCGitHubStatus?
    /// True when the daemon doesn't speak `github.status` (METHOD_NOT_FOUND).
    /// Surfaced as a distinct Settings row so the user sees "Upgrade the
    /// daemon" instead of a misleading "Install gh CLI" CTA when in fact
    /// `gh` may already be on disk and authenticated.
    private(set) var githubDaemonUnsupported: Bool = false
    /// Localized error from the most recent github.status fetch, kept
    /// only when we have no cached status to fall back on. Background
    /// poll failures while a status is already in hand stay silent —
    /// the existing UI doesn't need to flicker on every transient drop.
    private(set) var githubStatusError: String?

    init(client: DaemonClient, isMock: Bool) {
        self.client = client
        self.isMock = isMock
        self.daemonStatus = isMock ? .mock : .connecting
    }

    /// Diff-guarded transition for the connection banner. Called from
    /// the coordinator's `refresh()` on each `session.list` round-trip.
    func setDaemonStatus(_ status: DaemonStatus) {
        if daemonStatus != status { daemonStatus = status }
    }

    /// Adopt a `gh` status update from a successful response — clears
    /// the daemon-unsupported / fetch-error fallbacks since we now
    /// have a definitive answer.
    func applyGithubStatus(_ status: RPCGitHubStatus) {
        githubStatus = status
        githubDaemonUnsupported = false
        githubStatusError = nil
    }

    /// Re-fetch `gh` CLI status from the daemon. Called at bootstrap, when
    /// the Settings page opens, and on demand while the sign-in sheet is
    /// polling (every 2s) until `authenticated` flips true.
    ///
    /// Three failure modes, three different UI affordances:
    /// - METHOD_NOT_FOUND → outdated daemon; surface a daemon-upgrade row.
    /// - any other failure with no cached status → surface the error so
    ///   the user isn't staring at `Checking gh status…` forever.
    /// - any other failure with a cached status → swallow silently so the
    ///   sheet's 2s poll doesn't flicker the page on a transient drop.
    func refreshGitHubStatus() async {
        do {
            let updated = try await client.githubStatus()
            applyGithubStatus(updated)
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            githubDaemonUnsupported = true
            githubStatusError = nil
        } catch {
            githubDaemonUnsupported = false
            if githubStatus == nil {
                githubStatusError = error.toastMessage
            }
        }
    }
}

/// Toast-friendly description for an arbitrary thrown error. JSON-RPC
/// errors carry their own `errorDescription`; everything else falls
/// back to `localizedDescription`. Used by the state layer when
/// surfacing failures via `ModalState.showToast`.
extension Error {
    var toastMessage: String {
        if let rpc = self as? JSONRPCError {
            return rpc.errorDescription ?? "\(rpc)"
        }
        return localizedDescription
    }
}
