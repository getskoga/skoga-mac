import Foundation

/// Builds the `github.com/<owner>/<repo>/compare/<base>...<branch>` URL
/// for the agent's session, used by the conversation side panel's
/// "View commits on GitHub" quick action. Owner/repo come from
/// `git config --get remote.origin.url` against the agent's worktree —
/// the worktree shares its `.git` with the parent checkout, so the
/// remote resolves identically. Only `github.com` is recognized; other
/// hosts (GHE, GitLab, Bitbucket) fall through as `.notGitHub`.
enum GitHubCompareLauncher {
    enum Outcome {
        case resolved(URL)
        case notGitHub
        case failed(String)
    }

    static func resolve(worktree: String, base: String, branch: String) async -> Outcome {
        await Task.detached(priority: .userInitiated) {
            let remote: String
            switch readOriginURL(worktree: worktree) {
            case .ok(let value):
                remote = value
            case .notConfigured:
                return .notGitHub
            case .error(let message):
                return .failed(message)
            }
            guard let parsed = parseGitHubRemote(remote) else {
                return .notGitHub
            }
            // Branch names can contain `/` (e.g. `skoga/foo`) and GitHub
            // uses those literally in compare URLs — `.urlPathAllowed`
            // preserves `/` while escaping anything genuinely unsafe.
            let baseEscaped = base.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? base
            let branchEscaped = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
            let urlString = "https://github.com/\(parsed.owner)/\(parsed.repo)/compare/\(baseEscaped)...\(branchEscaped)"
            guard let url = URL(string: urlString) else {
                return .failed("Couldn't build a valid GitHub compare URL.")
            }
            return .resolved(url)
        }.value
    }

    // MARK: – git invocation

    private enum OriginReadResult {
        case ok(String)
        case notConfigured
        case error(String)
    }

    private static func readOriginURL(worktree: String) -> OriginReadResult {
        guard let git = resolveGit() else {
            return .error("Couldn't find `git` on this machine.")
        }
        let process = Process()
        process.executableURL = git
        process.arguments = ["-C", worktree, "config", "--get", "remote.origin.url"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        // Drain stderr to /dev/null rather than a Pipe — we never read it
        // and a full Pipe buffer would deadlock `waitUntilExit`.
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .error("Couldn't run git: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        // `git config --get` exits 1 when the key is missing — that's a
        // "no origin configured" signal, not a hard error.
        if process.terminationStatus == 1 {
            return .notConfigured
        }
        if process.terminationStatus != 0 {
            return .error("git exited \(process.terminationStatus) while reading the remote.")
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let raw = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return .notConfigured }
        return .ok(raw)
    }

    /// Finder-launched apps inherit a stripped PATH (no Homebrew), so
    /// look at known install locations directly. `/usr/bin/git` is
    /// present on every supported macOS, but the homebrew candidates
    /// come first so a user with a newer toolchain installed there
    /// gets that version. Same search list as `BugReportModal.resolveGh`.
    private static func resolveGit() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
            "/usr/bin/git",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
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
