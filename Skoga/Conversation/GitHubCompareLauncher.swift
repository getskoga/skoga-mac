import Foundation

/// Builds the `github.com/<owner>/<repo>/compare/<base>...<branch>` URL
/// for the agent's session, used by the conversation side panel's
/// "View commits on GitHub" quick action. The origin URL is resolved by
/// the daemon (`session.remote_url`) rather than read from local git
/// config in a subprocess, so a sandboxed build stays a pure daemon
/// client. Only `github.com` is recognized; other hosts (GHE, GitLab,
/// Bitbucket) fall through as `.notGitHub`.
enum GitHubCompareLauncher {
    enum Outcome {
        case resolved(URL)
        case notGitHub
        case failed(String)
    }

    /// Turn a daemon-resolved `origin` URL into a GitHub compare URL. Pure
    /// and synchronous — the caller fetches `remoteURL` over RPC and hands
    /// the result in. `nil` (no `origin` configured) or a non-github.com
    /// host resolves to `.notGitHub`.
    static func resolve(remoteURL: String?, base: String, branch: String) -> Outcome {
        guard let remoteURL, !remoteURL.isEmpty else { return .notGitHub }
        guard let parsed = parseGitHubRemote(remoteURL) else {
            return .notGitHub
        }
        // Branch names can contain `/` (e.g. `skoga/foo`) and GitHub uses
        // those literally in compare URLs — `.urlPathAllowed` preserves `/`
        // while escaping anything genuinely unsafe.
        let baseEscaped = base.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? base
        let branchEscaped = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
        let urlString = "https://github.com/\(parsed.owner)/\(parsed.repo)/compare/\(baseEscaped)...\(branchEscaped)"
        guard let url = URL(string: urlString) else {
            return .failed("Couldn't build a valid GitHub compare URL.")
        }
        return .resolved(url)
    }

    // MARK: – URL parsing

    /// Pull `(owner, repo)` from a github.com remote URL. Handles every
    /// form `git remote` will emit:
    /// * `https://github.com/owner/repo[.git]`
    /// * `https://<token>@github.com/owner/repo[.git]`
    /// * `git@github.com:owner/repo[.git]`
    /// * `ssh://git@github.com/owner/repo[.git]`
    ///
    /// Returns nil for non-github.com hosts (GHE, GitLab, …) so the
    /// caller can flip to a "not a GitHub repo" toast.
    static func parseGitHubRemote(_ rawURL: String) -> (owner: String, repo: String)? {
        var s = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip trailing `/` first so an input like `.../repo.git/`
        // collapses to `.../repo.git` before the `.git` strip; otherwise
        // the suffix check misses and `repo` ends up as `repo.git`.
        while s.hasSuffix("/") { s = String(s.dropLast()) }
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        while s.hasSuffix("/") { s = String(s.dropLast()) }
        guard let hostRange = s.range(of: "github.com") else { return nil }
        let afterHost = s[hostRange.upperBound...]
        // The character immediately following the host is `:` for the SCP
        // form (`git@github.com:owner/repo`) or `/` for every URL form.
        // Anything else means the string mentions github.com somewhere
        // other than the host slot (e.g. a path containing it) and we
        // shouldn't try to parse it.
        guard let separator = afterHost.first, separator == "/" || separator == ":" else { return nil }
        let path = afterHost.dropFirst()
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let owner = String(parts[0])
        let repo = String(parts[1])
        guard !owner.isEmpty, !repo.isEmpty else { return nil }
        return (owner, repo)
    }
}
