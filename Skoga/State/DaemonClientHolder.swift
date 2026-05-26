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

    /// Last fetched per-provider credential presence/last-used metadata
    /// (`credentials.list`). Empty before the first fetch; Settings →
    /// Models & keys renders a loading row in that window. Mutated
    /// optimistically by set/delete flows so the row chip flips
    /// immediately instead of waiting for the next refresh.
    private(set) var credentialEntries: [RPCCredentialEntry] = []
    /// True when the daemon doesn't speak `credentials.*` (skogad <
    /// getskoga/skoga#103). Surfaced as a distinct "Upgrade the daemon"
    /// row in Settings → Models & keys so the user doesn't waste time
    /// pasting keys into a UI the daemon can't persist.
    private(set) var credentialsDaemonUnsupported: Bool = false
    /// Localized error from the most recent credentials.list fetch,
    /// kept only when we have no cached entries to fall back on. Same
    /// reasoning as `githubStatusError` — don't flicker on transient
    /// failures while we already have something to render.
    private(set) var credentialsError: String?
    /// Most recent `credentials.test` outcome per provider. Surfaced
    /// inline next to the Test button; `nil` means "no probe run since
    /// last app launch". Trimmed when the user mutates the key (set /
    /// delete) so a stale "ok" doesn't sit next to a freshly-changed
    /// row.
    private(set) var credentialTestResults: [RPCCredentialProvider: RPCCredentialsTestResult] = [:]

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

    /// Re-fetch per-provider credential presence + last-used metadata
    /// (`credentials.list`). Called when Settings → Models & keys opens
    /// and after any set/delete to keep the row chips honest.
    ///
    /// Same three-failure-mode shape as `refreshGitHubStatus`:
    /// - METHOD_NOT_FOUND → outdated daemon; surface the upgrade row.
    /// - other failure with no cached entries → show the error.
    /// - other failure with cached entries → swallow silently.
    func refreshCredentials() async {
        do {
            let entries = try await client.credentialsList()
            credentialEntries = entries
            credentialsDaemonUnsupported = false
            credentialsError = nil
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            credentialsDaemonUnsupported = true
            credentialsError = nil
        } catch {
            credentialsDaemonUnsupported = false
            if credentialEntries.isEmpty {
                credentialsError = error.toastMessage
            }
        }
    }

    /// Update the cached entry for `entry.provider` in-place (or append
    /// when the slice has never seen it). Used by the coordinator after
    /// set/delete/test so the row chip flips without waiting for a full
    /// `refreshCredentials` round-trip.
    func applyCredentialEntry(_ entry: RPCCredentialEntry) {
        if let idx = credentialEntries.firstIndex(where: { $0.provider == entry.provider }) {
            credentialEntries[idx] = entry
        } else {
            credentialEntries.append(entry)
        }
    }

    /// Record (or clear) the inline `credentials.test` result for one
    /// provider. Passed `nil` to drop the cached result — typically
    /// after a set/delete so an old "✓ Probe succeeded" doesn't sit
    /// next to a freshly-rotated key.
    func setCredentialTestResult(_ result: RPCCredentialsTestResult?, for provider: RPCCredentialProvider) {
        credentialTestResults[provider] = result
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
