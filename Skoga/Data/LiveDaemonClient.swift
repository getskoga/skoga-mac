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

    func createSession(task: String, agent: String, base: String, repoRoot: URL, initialPrompt: String?) async throws -> Agent {
        // auto_launch tells skogad to spawn the detached `skoga
        // _dispatch_launch` subprocess that actually starts the agent in
        // tmux. The Mac dashboard has no other way to bring the agent up —
        // without this, session.create would persist a Running record that
        // gets reaped to AgentExited 30s later (REAP_GRACE_SECS).
        // initial_prompt is the brief from the Dispatch form; the daemon
        // forwards it to _dispatch_launch which passes it to the agent as
        // its first message. We normalize blank-only input to nil here so
        // the daemon doesn't launch claude with an empty positional arg.
        let trimmed = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let params = AnyEncodable(SessionCreateParams(
            task: task,
            agent: agent,
            base: base,
            repo_root: repoRoot.path,
            task_auto: false,
            auto_launch: true,
            initial_prompt: (trimmed?.isEmpty ?? true) ? nil : trimmed
        ))
        let resp: SessionCreateResponse = try await rpc.call("session.create", params: params)
        return Agent.from(rpc: resp.session)
    }

    func killSession(id: String) async throws {
        let params = AnyEncodable(SessionKillParams(id: id))
        let _: SessionKillResponse = try await rpc.call("session.kill", params: params)
    }

    /// Forwards every `events.event` notification to the caller. The consumer
    /// is expected to debounce + refetch — payloads are too heterogeneous to
    /// apply incrementally and a full `session.list` is cheap.
    nonisolated func events() -> AsyncStream<RPCEvent> {
        rpc.eventStream()
    }
}

// MARK: – RPCSession → Agent

extension Agent {
    /// Translate a daemon `Session` into a Mac `Agent`. Fields the daemon
    /// doesn't expose yet (tokens, cost, commits, files, progress) are zeroed;
    /// `name`/`role` are derived from the id and the configured agent adapter.
    static func from(rpc s: RPCSession) -> Agent {
        let status = AgentStatus(rpc: s.state, waiting: s.waiting_since, idle: s.idle_since)
        let waiting = s.waiting_since != nil
        let conflicted = s.state == .conflicted || s.state == .syncBroken
        let attn = waiting || conflicted

        let attnMessage: String? = {
            if waiting { return "Agent is blocked waiting on input" }
            if s.state == .conflicted { return "Rebase conflict — needs resolution" }
            if s.state == .syncBroken { return "Sync broken — run `skoga sync --debug`" }
            return nil
        }()

        return Agent(
            id: s.id,
            name: prettyName(from: s.id),
            role: s.agent,
            model: s.agent,
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
            prUrl: s.landed_pr_url
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
            self = .review
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
