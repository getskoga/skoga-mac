import Foundation

/// Talks to a real `skogad` over `~/.skoga/sock`. Maps the daemon's `Session`
/// records onto the Mac `Agent` model — many UI fields (tokens, cost, commits,
/// progress) aren't exposed by the daemon yet and are synthesized; see
/// [`Agent.from(rpc:)`] for the mapping policy.
@MainActor
final class LiveDaemonClient: DaemonClient {

    private let rpc = JSONRPCClient(socketPath: URL.skogaSocket)

    func listAgents() async throws -> [Agent] {
        let params = AnyEncodable(SessionListParams(include_terminal: false))
        let sessions: [RPCSession] = try await rpc.call("session.list", params: params)
        return sessions.map(Agent.from(rpc:))
    }

    func conversation(for agentId: String) async throws -> [ConversationMessage] {
        // skogad reconstructs the conversation by parsing Claude Code's own
        // transcript jsonl for the session. If the session has no recorded
        // agent_session_id yet (very fresh) or the daemon is older than this
        // RPC, the call returns empty / method-not-found — both fall back to
        // the UI's empty state rather than surfacing as a hard error.
        let params = AnyEncodable(SessionConversationParams(id: agentId))
        do {
            let resp: SessionConversationResponse = try await rpc.call("session.conversation", params: params)
            return resp.messages.compactMap { $0.toDomain() }
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            // Older daemon doesn't know session.conversation yet — show empty.
            return []
        }
    }

    func activitySeries() async throws -> [Double] { [] }

    func timeline(for agentId: String) async throws -> [TimelineEntry] { [] }

    // MARK: – Mutations

    func daemonVersion() async throws -> String {
        let resp: VersionResponse = try await rpc.call("daemon.version")
        return resp.version
    }

    func createSession(task: String, agent: String, model: String?, base: String, repoRoot: URL, initialPrompt: String?) async throws -> Agent {
        // auto_launch tells skogad to spawn the detached `skoga
        // _dispatch_launch` subprocess that actually starts the agent in
        // tmux. The Mac dashboard has no other way to bring the agent up —
        // without this, session.create would persist a Running record that
        // gets reaped to AgentExited 30s later (REAP_GRACE_SECS).
        // initial_prompt is the brief from the Dispatch form; the daemon
        // forwards it to _dispatch_launch which passes it to the agent as
        // its first message. We normalize blank-only input to nil here so
        // the daemon doesn't launch claude with an empty positional arg.
        // agent_model pins the adapter's CLI model flag (e.g. `claude
        // --model claude-opus-4.7`) and is persisted on the session
        // record; legacy callers / older Mac builds omit it and the
        // daemon falls back to the adapter's CLI default.
        let trimmed = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let params = AnyEncodable(SessionCreateParams(
            task: task,
            agent: agent,
            base: base,
            repo_root: repoRoot.path,
            task_auto: false,
            auto_launch: true,
            initial_prompt: (trimmed?.isEmpty ?? true) ? nil : trimmed,
            agent_model: model
        ))
        let resp: SessionCreateResponse = try await rpc.call("session.create", params: params)
        return Agent.from(rpc: resp.session)
    }

    func killSession(id: String) async throws {
        let params = AnyEncodable(SessionKillParams(id: id))
        let _: SessionKillResponse = try await rpc.call("session.kill", params: params)
    }

    func sendInput(sessionId: String, text: String) async throws {
        // Older daemons (pre-`session.send_input`) return METHOD_NOT_FOUND.
        // We let that propagate as a JSONRPCError so the AppState shows the
        // user a real toast rather than the silent stub the composer used
        // to be. The Mac app's distribution will require a matching daemon
        // version anyway — gating this on an Optional dance would mask the
        // version mismatch instead of surfacing it.
        let params = AnyEncodable(SessionSendInputParams(id: sessionId, text: text))
        let _: SessionSendInputResponse = try await rpc.call("session.send_input", params: params)
    }

    func pendingQuestion(for agentId: String) async throws -> RPCPendingQuestion? {
        // Older daemons (pre-#100) don't expose this method; swallow
        // METHOD_NOT_FOUND so the conversation view still renders.
        let params = AnyEncodable(SessionPendingQuestionParams(id: agentId))
        do {
            let resp: SessionPendingQuestionResponse = try await rpc.call(
                "session.pending_question", params: params
            )
            return resp.question
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            return nil
        }
    }

    func answerQuestion(sessionId: String, selectedIndices: [Int]) async throws {
        let params = AnyEncodable(SessionAnswerQuestionParams(
            id: sessionId,
            selected_indices: selectedIndices
        ))
        let _: SessionAnswerQuestionResponse = try await rpc.call(
            "session.answer_question", params: params
        )
    }

    func openPTYStream(sessionId: String, cols: UInt16?, rows: UInt16?) async throws -> AttachedPTYStream {
        try await rpc.openPTYStream(sessionId: sessionId, cols: cols, rows: rows)
    }

    func ptyWrite(sessionId: String, bytes: Data) async throws {
        let params = AnyEncodable(SessionPtyWriteParams(
            id: sessionId,
            bytes_b64: bytes.base64EncodedString()
        ))
        let _: SessionPtyWriteResponse = try await rpc.call("session.pty_write", params: params)
    }

    func ptyResize(sessionId: String, cols: UInt16, rows: UInt16) async throws {
        let params = AnyEncodable(SessionPtyResizeParams(id: sessionId, cols: cols, rows: rows))
        let _: SessionPtyResizeResponse = try await rpc.call("session.pty_resize", params: params)
    }

    /// Forwards every `events.event` notification to the caller. The consumer
    /// is expected to debounce + refetch — payloads are too heterogeneous to
    /// apply incrementally and a full `session.list` is cheap.
    nonisolated func events() -> AsyncStream<RPCEvent> {
        rpc.eventStream()
    }

    func previewPR(for sessionId: String) async throws -> PRPreview {
        // Mirror the CLI's `commit_message: Claude` mode: ask Claude to draft
        // a commit message from the session's diff and use it as the PR's
        // title (first line) + body (rest). Without this the modal pre-fills
        // with the bare session task — produces noticeably worse PRs than
        // `skoga land` from a terminal, which is the gap this method closes.
        //
        // Two failure paths fall back to the CLI's default-message preview
        // rather than surfacing as a modal error: (1) we couldn't locate the
        // session via session.list (older daemon, race against teardown);
        // (2) we found it but `claude` isn't installed / produced nothing
        // useful. The user can still edit the field — getting a worse
        // default is better than a hard-failed modal.
        if let drafted = try? await claudeDraftedPreview(for: sessionId) {
            return drafted
        }
        let out = try await runSkoga(args: ["land", sessionId, "--preview"])
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw SkogaCLIError.unexpectedOutput("preview returned non-utf8 output")
        }
        let payload = try JSONDecoder().decode(SkogaLandPreviewPayload.self, from: data)
        return PRPreview(title: payload.title, body: payload.body)
    }

    /// Re-implements `skoga land`'s `draft_message_via_claude` in Swift so
    /// the Mac app's PR modal pre-fills with the same Claude-drafted text a
    /// terminal `skoga land` would produce. Throws (and lets `previewPR`
    /// fall back) when any precondition fails — claude not installed, empty
    /// diff, non-zero exit — rather than papering over with junk output.
    private func claudeDraftedPreview(for sessionId: String) async throws -> PRPreview {
        guard let session = try await fetchSession(id: sessionId) else {
            throw SkogaCLIError.unexpectedOutput("session \(sessionId) not in session.list")
        }
        guard let worktree = session.worktree, !worktree.isEmpty else {
            throw SkogaCLIError.unexpectedOutput("session \(sessionId) has no worktree path")
        }
        // `origin/<base>...HEAD` is the read-only equivalent of what the
        // CLI feeds Claude. The CLI rebases onto target + `reset --soft
        // merge_base` + `diff --cached`; we can't mutate the worktree for
        // a preview, so we use three-dot diff (which is `merge-base(...)
        // → HEAD`) directly. If `origin/<base>` has moved since the
        // session last rebased, the actual landed diff will include
        // upstream churn this preview doesn't — acceptable for the modal
        // pre-fill since the user reviews the message before landing.
        let diff = try await runGit(
            args: ["diff", "origin/\(session.base)...HEAD"],
            cwd: worktree
        )
        if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SkogaCLIError.unexpectedOutput("no diff vs origin/\(session.base)")
        }
        let drafted = try await draftCommitMessageViaClaude(task: session.task, diff: diff)
        return splitCommitMessage(drafted)
    }

    private func fetchSession(id: String) async throws -> RPCSession? {
        let params = AnyEncodable(SessionListParams(include_terminal: true))
        let sessions: [RPCSession] = try await rpc.call("session.list", params: params)
        return sessions.first(where: { $0.id == id })
    }

    func landPR(for sessionId: String, title: String, body: String) async throws {
        // `--yes` skips the confirm prompt. Title/body win over the CLI's
        // default-message derivation, so the modal's edits make it all the
        // way through the squash + push + gh-pr-create pipeline.
        _ = try await runSkoga(args: [
            "land", sessionId,
            "--title", title,
            "--body", body,
            "--yes",
        ])
    }

    /// Spawn `skoga <args>`, await termination, capture stdout. Stderr is
    /// folded into the error message on failure so the user sees the same
    /// preflight-failure / conflict text the terminal would surface.
    private nonisolated func runSkoga(args: [String]) async throws -> String {
        guard let bin = LiveDaemonClient.resolveSkogaBinary() else {
            throw SkogaCLIError.binaryNotFound
        }
        return try await runProcess(executable: bin, args: args, stdin: nil, cwd: nil)
    }

    /// Run `git <args>` in `cwd`. Trimmed stdout on success; stderr folded
    /// into `SkogaCLIError.commandFailed` on non-zero. `git` is resolved
    /// via the system PATH — every macOS dev install has it (Xcode CLT or
    /// Homebrew), so there's no equivalent of `resolveSkogaBinary` here.
    private nonisolated func runGit(args: [String], cwd: String) async throws -> String {
        try await runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            args: ["git"] + args,
            stdin: nil,
            cwd: cwd
        )
    }

    /// Ask `claude` to draft a commit message from the staged diff. The
    /// prompt mirrors `draft_message_via_claude` in skoga-cli's land.rs
    /// verbatim — keeping the wording aligned means PRs opened from the
    /// Mac app read the same as PRs opened from a terminal `skoga land`.
    private nonisolated func draftCommitMessageViaClaude(task: String, diff: String) async throws -> String {
        guard let bin = LiveDaemonClient.resolveClaudeBinary() else {
            throw SkogaCLIError.binaryNotFound
        }
        // Embed the diff in the prompt arg (not stdin) to match the CLI's
        // `draft_message_via_claude` byte-for-byte. ARG_MAX on macOS is 1MB
        // — large for diffs but the CLI uses this shape successfully today,
        // so we keep the two flows on the same prompt for parity. If we
        // later hit E2BIG on a real PR, switch both implementations to
        // stdin together so the wording stays aligned.
        let prompt = """
        Write a concise git commit message for the staged changes below. \
        The user's original task was: "\(task)". \
        Output ONLY the commit message — no preamble, no code fences. \
        First line: imperative subject, 50 chars or less. \
        Then a blank line. \
        Then a short body wrapped at 72 chars explaining the why.

        --- diff ---
        \(diff)
        """
        let stdout = try await runProcess(
            executable: bin,
            args: ["-p", prompt],
            stdin: nil,
            cwd: nil
        )
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw SkogaCLIError.unexpectedOutput("claude produced an empty message")
        }
        return trimmed
    }

    /// Split a Claude-drafted commit message into PR title (first line) and
    /// PR body (everything after the blank line). Matches the CLI's
    /// `first_line` / `message_body` pair — same splitting rule, so the
    /// modal pre-fill renders the same shape the terminal flow would.
    private nonisolated func splitCommitMessage(_ message: String) -> PRPreview {
        // Strip leading blank lines before picking the title. Claude has
        // been observed to prefix the message with an empty line; without
        // this guard the title field would render blank even though the
        // body contains a perfectly good subject.
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false)
        let firstNonEmpty = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? lines.startIndex
        let titleSlice = lines[firstNonEmpty]
        let title = String(titleSlice).trimmingCharacters(in: .whitespaces)
        let bodyLines = lines[lines.index(after: firstNonEmpty)...]
        let body = bodyLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return PRPreview(title: title, body: body)
    }

    /// Common subprocess runner shared by `runSkoga`, `runGit`, and the
    /// claude shell-out. Captures stdout, folds stderr into the error
    /// message, and (when `stdin` is non-nil) writes the payload onto the
    /// child's stdin before closing.
    ///
    /// Drains stdout/stderr asynchronously via `readabilityHandler` rather
    /// than calling `readToEnd()` in `terminationHandler`. The pipe buffer
    /// is ~64 KB; `git diff origin/<base>...HEAD` on any substantive
    /// session blows past that and the child would block on `write()`,
    /// never exit, and the modal would hang forever waiting on
    /// `terminationHandler` to fire. Draining as data arrives keeps the
    /// pipe from filling. A locked accumulator is needed because
    /// `readabilityHandler` and `terminationHandler` fire on different
    /// background queues.
    private nonisolated func runProcess(
        executable: URL,
        args: [String],
        stdin: String?,
        cwd: String?
    ) async throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        // A macOS app launched from Finder/Dock inherits a minimal PATH
        // (/usr/bin:/bin:/usr/sbin:/sbin). `git` lives in /usr/bin so
        // `skoga land`'s push step works, but `gh` lives in homebrew —
        // without augmenting PATH the subsequent `gh pr create` step
        // silently fails and the user sees a pushed branch with no PR.
        // Applied to every subprocess (skoga / git / claude) so each one
        // gets the same dev-shell-like view of the toolchain.
        process.environment = LiveDaemonClient.subprocessEnvironment()
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe: Pipe? = (stdin != nil) ? Pipe() : nil
        process.standardOutput = outPipe
        process.standardError = errPipe
        if let inPipe {
            process.standardInput = inPipe
        } else {
            // Close stdin explicitly. Claude (and a few other CLIs) will
            // otherwise hang reading from an inherited stdin in `-p` mode —
            // the GUI app has no TTY, so what we'd inherit is undefined.
            process.standardInput = FileHandle.nullDevice
        }

        let stdoutBuffer = LockedData()
        let stderrBuffer = LockedData()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                // EOF on the pipe — child closed its write end. Detach so
                // we don't busy-loop on a closed handle.
                handle.readabilityHandler = nil
            } else {
                stdoutBuffer.append(chunk)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stderrBuffer.append(chunk)
            }
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            process.terminationHandler = { p in
                // Detach handlers; the child is gone and any further
                // availableData will be empty anyway. Drain whatever the
                // kernel still has buffered with one final read so we
                // don't lose a trailing chunk.
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if let tail = try? outPipe.fileHandleForReading.readToEnd() {
                    stdoutBuffer.append(tail)
                }
                if let tail = try? errPipe.fileHandleForReading.readToEnd() {
                    stderrBuffer.append(tail)
                }
                let stdout = String(data: stdoutBuffer.snapshot(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrBuffer.snapshot(), encoding: .utf8) ?? ""
                if p.terminationStatus == 0 {
                    cont.resume(returning: stdout)
                } else {
                    let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(throwing: SkogaCLIError.commandFailed(
                        status: p.terminationStatus,
                        stderr: detail.isEmpty ? stdout : detail
                    ))
                }
            }
            do {
                try process.run()
                if let inPipe, let stdin {
                    let handle = inPipe.fileHandleForWriting
                    if let data = stdin.data(using: .utf8) {
                        try? handle.write(contentsOf: data)
                    }
                    try? handle.close()
                }
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    /// Find an installed `skoga` binary. Checked at call-time rather than
    /// cached at boot because the user may install the CLI while the app
    /// is already running. The order matches the priority `which skoga`
    /// would return for a default zsh PATH on macOS dev machines.
    private nonisolated static func resolveSkogaBinary() -> URL? {
        resolveBinary(name: "skoga", extraDirs: ["\(NSHomeDirectory())/.cargo/bin"])
    }

    /// Find an installed `claude` binary. Same search order as `skoga` plus
    /// the npm global prefix where the official CLI typically lands. Claude
    /// is optional — if it's missing, `previewPR` falls back to the CLI's
    /// default-message preview rather than surfacing a hard failure, so the
    /// modal still opens for users who haven't set up the agent CLI.
    private nonisolated static func resolveClaudeBinary() -> URL? {
        resolveBinary(name: "claude", extraDirs: [
            "\(NSHomeDirectory())/.claude/local",
            "\(NSHomeDirectory())/.npm-global/bin",
            "\(NSHomeDirectory())/.volta/bin",
        ])
    }

    private nonisolated static func resolveBinary(name: String, extraDirs: [String]) -> URL? {
        let fm = FileManager.default
        for dir in extraDirs + standardSearchDirs {
            let path = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Dirs checked for tool binaries and prepended to the spawn PATH so
    /// `skoga land`'s shell-outs (`gh`, etc.) resolve under a Finder-
    /// launched app. Single source of truth — the binary lookup and the
    /// env augmentation must stay in sync or one of them will silently
    /// regress. `/usr/bin` is included for the binary lookup but doesn't
    /// need re-prepending to PATH (it's on the default already).
    private nonisolated static let standardSearchDirs: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
    ]

    /// Build the env for `skoga` / `git` / `claude` subprocesses: inherit
    /// the app's env, then prepend `standardSearchDirs` plus the cargo
    /// install location so `gh` (and anything else the CLI shells out to)
    /// is reachable on the Finder-launched app's stripped-down PATH.
    private nonisolated static func subprocessEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let prepend = ["\(NSHomeDirectory())/.cargo/bin"] + standardSearchDirs
        let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (prepend + [existing]).joined(separator: ":")
        return env
    }
}

/// Tiny lock-guarded `Data` accumulator. `runProcess` drains stdout/stderr
/// from background `readabilityHandler` queues while another background
/// queue fires `terminationHandler` — they touch the same buffer, so a
/// plain `Data` would race. `NSLock` is enough; the contention window is
/// a `Data.append` per pipe chunk.
private final class LockedData: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    func snapshot() -> Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}

/// Failure modes for `skoga <verb>` shell-outs from the Mac app. Surfaced
/// to the user via toasts / modal error states — they're the only useful
/// signal when the CLI fails inside a non-interactive run.
enum SkogaCLIError: LocalizedError {
    case binaryNotFound
    case commandFailed(status: Int32, stderr: String)
    case unexpectedOutput(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Couldn't find the `skoga` CLI on disk. Install it (e.g. `cargo install --path crates/skoga-cli`) and try again."
        case .commandFailed(let status, let stderr):
            let detail = stderr.isEmpty ? "no stderr output" : stderr
            return "skoga exited \(status): \(detail)"
        case .unexpectedOutput(let msg):
            return msg
        }
    }
}

/// Decodes the JSON payload `skoga land --preview` writes to stdout. The
/// CLI emits a single line with `session_id`, `title`, and `body`; we
/// ignore `session_id` (the caller already knows which session it asked
/// about) but decode it for forward compatibility.
private struct SkogaLandPreviewPayload: Decodable {
    let session_id: String
    let title: String
    let body: String
}

// MARK: – RPCSession → Agent

extension Agent {
    /// Translate a daemon `Session` into a Mac `Agent`. Fields the daemon
    /// doesn't expose yet (tokens, cost, commits, files, progress) are zeroed;
    /// `name`/`role` are derived from the id and the configured agent adapter.
    static func from(rpc s: RPCSession) -> Agent {
        let pendingQuestion = s.pending_question?.toConversationMessage()
        let pendingQuestionPayload: ConversationMessage.QuestionPayload? = {
            guard case .question(let q) = pendingQuestion else { return nil }
            return q
        }()
        let status = AgentStatus(rpc: s.state, waiting: s.waiting_since, idle: s.idle_since)
        let waiting = s.waiting_since != nil
        let conflicted = s.state == .conflicted || s.state == .syncBroken
        let attn = waiting || conflicted

        let attnMessage: String? = {
            if pendingQuestionPayload != nil { return "Agent is asking a question" }
            if waiting { return "Agent is blocked waiting on input" }
            if s.state == .conflicted { return "Rebase conflict — needs resolution" }
            if s.state == .syncBroken { return "Sync broken — run `skoga sync --debug`" }
            return nil
        }()

        return Agent(
            id: s.id,
            name: prettyName(from: s.id),
            role: s.agent,
            // Legacy sessions (pre-#92) didn't persist a model, so fall
            // back to the adapter name to keep the Roster's model line
            // populated — same string the old code used to show.
            model: s.agent_model ?? s.agent,
            status: status,
            task: s.task,
            repo: prettyRepo(from: s.repo_root),
            branch: s.branch,
            progress: progressFor(state: s.state),
            runtime: runtimeLabel(since: s.created_at),
            tokens: 0,
            cost: 0,
            commits: 0,
            files: 0,
            attn: attn,
            attnMessage: attnMessage,
            prUrl: s.landed_pr_url,
            pendingQuestion: pendingQuestionPayload
        )
    }
}

private extension AgentStatus {
    init(rpc state: RPCSessionState, waiting: Date?, idle: Date?) {
        // Waiting-on-input trumps everything else because the manager needs
        // to act. Idle-at-prompt is just a hint the agent isn't doing work,
        // so it maps to .idle only when the underlying state is still Running.
        if waiting != nil {
            self = .blocked
            return
        }
        switch state {
        case .running:
            // .idle here means "Claude finished a turn, awaiting next prompt"
            // — the process is alive, just dormant. Distinct from .exited.
            self = (idle != nil) ? .idle : .running
        case .conflicted, .syncBroken:
            self = .blocked
        case .killing:
            // .stopping is the transitional teardown state: process is being
            // wound down but cleanup hasn't completed. Kept distinct from
            // .exited so a card stuck mid-teardown (cleanup hung) is visibly
            // different from a cleanly-exited agent.
            self = .stopping
        case .agentExited, .killed:
            // .exited means the Claude process is gone (Ctrl-C, crash, or
            // post-teardown). The session/worktree may still be around, so
            // it's not the same as terminal .done. Renders distinct from .idle
            // because the user can't just "send another message" to wake it.
            self = .exited
        case .prOpen, .prMerged, .shipping:
            self = .prOpen
        case .done:
            self = .done
        }
    }
}

private func progressFor(state: RPCSessionState) -> Double {
    switch state {
    case .running, .conflicted, .agentExited, .syncBroken:  0.0
    case .prOpen, .prMerged, .shipping, .killing:           0.95
    case .done, .killed:                                    1.0
    }
}

private func prettyName(from id: String) -> String {
    // Session ids are 8-char hex. Default behavior maps the id to a Norse
    // alias from `NordicNames` so the Roster reads as "Odin" / "Thor"
    // instead of "24b171". The user can opt back into hex via
    // `skoga.useNordicNames` in defaults — see `NordicNames`.
    NordicNames.displayName(forSessionId: id)
}

private func prettyRepo(from path: String) -> String {
    URL(fileURLWithPath: path).lastPathComponent
}

private func runtimeLabel(since: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(since))
    if seconds < 60 { return "\(seconds)s" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    let remMin = minutes % 60
    return "\(hours)h \(remMin)m"
}
