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
        let out = try await runSkoga(args: ["land", sessionId, "--preview"])
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw SkogaCLIError.unexpectedOutput("preview returned non-utf8 output")
        }
        let payload = try JSONDecoder().decode(SkogaLandPreviewPayload.self, from: data)
        return PRPreview(title: payload.title, body: payload.body)
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
        let process = Process()
        process.executableURL = bin
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            process.terminationHandler = { p in
                let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? nil ?? Data()
                let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? nil ?? Data()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
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
        let candidates = [
            "\(NSHomeDirectory())/.cargo/bin/skoga",
            "/opt/homebrew/bin/skoga",
            "/usr/local/bin/skoga",
            "/usr/bin/skoga",
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
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
