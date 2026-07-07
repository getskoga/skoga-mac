import Foundation
import CryptoKit

/// Talks to a real `skogad` over `~/.skoga/sock`. Maps the daemon's `Session`
/// records onto the Mac `Agent` model — many UI fields (tokens, cost, commits)
/// aren't exposed by the daemon yet and are synthesized; see
/// [`Agent.from(rpc:)`] for the mapping policy.
@MainActor
final class LiveDaemonClient: DaemonClient {

    private let rpc = JSONRPCClient(socketPath: URL.skogaSocket)

    nonisolated func listAgents() async throws -> [Agent] {
        let params = AnyEncodable(SessionListParams(include_terminal: false))
        let sessions: [RPCSession] = try await rpc.call("session.list", params: params)
        return sessions.map(Agent.from(rpc:))
    }

    nonisolated func listTerminalSessions(
        limit: Int?,
        cursor: String?,
        since: Date?,
        until: Date?
    ) async throws -> TerminalSessionPage {
        let params = AnyEncodable(SessionListTerminalParams(
            limit: limit,
            cursor: cursor,
            since: since.map(Self.isoString(_:)),
            until: until.map(Self.isoString(_:))
        ))
        do {
            let resp: SessionListTerminalResponse = try await rpc.call(
                "session.list_terminal", params: params
            )
            return TerminalSessionPage(
                sessions: resp.sessions.map(Agent.from(rpc:)),
                nextCursor: resp.next_cursor,
                totalEstimate: resp.total_estimate
            )
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            // Older daemon without session.list_terminal — surface as an
            // empty page so the History view renders its "no history"
            // state rather than a transport error. The user will see the
            // same outcome they would with no terminal sessions yet.
            return TerminalSessionPage(sessions: [], nextCursor: nil, totalEstimate: nil)
        }
    }

    /// RFC3339 with fractional seconds, matching the format chrono
    /// emits on the daemon side. Used for `session.list_terminal`'s
    /// `since`/`until` since the project's `JSONEncoder` has no global
    /// date strategy — the boundary converts to a string here so the
    /// wire shape stays explicit and the param struct stays a plain
    /// `Encodable` instead of growing a custom `encode(to:)`.
    private nonisolated static func isoString(_ date: Date) -> String {
        Self.isoFormatter.string(from: date)
    }

    private nonisolated static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated func conversation(for agentId: String) async throws -> [ConversationMessage] {
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

    nonisolated func activitySeries() async throws -> [Double] {
        // Daemon emits raw tokens/min per minute bucket; ActivityBars
        // normalizes against the max-of-series so the bar scale stays
        // sensible whether the guild is emitting 3k or 3M tok/min.
        // Older daemons (pre-getskoga/skoga#89) don't expose this RPC —
        // swallow METHOD_NOT_FOUND so the cockpit shows a flat baseline
        // rather than the connection banner flipping to .notRunning.
        do {
            let resp: CockpitActivityResponse = try await rpc.call("cockpit.activity")
            return resp.buckets.map(\.tokens_per_min)
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            return []
        }
    }

    nonisolated func timeline(for agentId: String) async throws -> [TimelineEntry] {
        // Mirrors `conversation(for:)` — older daemons (pre-getskoga/skoga#115)
        // don't know `session.timeline` yet, so swallow METHOD_NOT_FOUND and
        // fall back to the empty feed rather than toasting on every poll
        // against a real-but-outdated skogad. `limit: nil` lets the daemon
        // apply its default cap (30).
        let params = AnyEncodable(SessionTimelineParams(id: agentId, limit: nil))
        do {
            let resp: SessionTimelineResponse = try await rpc.call("session.timeline", params: params)
            return resp.entries.toDomain()
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            return []
        }
    }

    // MARK: – Mutations

    func daemonVersion() async throws -> String {
        let resp: VersionResponse = try await rpc.call("daemon.version")
        return resp.version
    }

    nonisolated func spendToday() async throws -> Double? {
        // Older daemons don't expose this method yet — swallow
        // METHOD_NOT_FOUND so the roster falls back to summing the live
        // (open-only) agent costs. Any other RPC error propagates so the
        // coordinator can keep the prior value rather than letting a flaky
        // tick clobber the cap readout.
        do {
            let resp: SpendTodayResponse = try await rpc.call("spend.today")
            return resp.total_usd
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            return nil
        }
    }

    func createSession(task: String, agent: String, model: String?, base: String, repoRoot: URL, initialPrompt: String?, namedAgentId: String?, attachments: [URL]) async throws -> Agent {
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
        // --model claude-opus-4-7`) and is persisted on the session
        // record; legacy callers / older Mac builds omit it and the
        // daemon falls back to the adapter's CLI default.
        // named_agent_id stamps the session against a permanent agent
        // from `agents.list`; the daemon bumps the agent's `last_used`
        // on accept and increments `total_runs` on terminal success.
        // Older daemons drop the field silently (`#[serde(default)]`),
        // so the dispatch still goes through against an ephemeral
        // identity.
        // attachments get read + base64-encoded off-MainActor so a
        // multi-MB binary doesn't freeze the UI thread during the
        // request build. The daemon writes them to disk before forking
        // `_dispatch_launch` and appends a path-list to initial_prompt,
        // so we don't reference attachment paths in the prompt here.
        let trimmed = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloads = try await Self.loadAttachmentPayloads(attachments)
        let params = AnyEncodable(SessionCreateParams(
            task: task,
            agent: agent,
            base: base,
            repo_root: repoRoot.path,
            task_auto: false,
            auto_launch: true,
            initial_prompt: (trimmed?.isEmpty ?? true) ? nil : trimmed,
            agent_model: model,
            named_agent_id: namedAgentId,
            attachments: payloads
        ))
        let resp: SessionCreateResponse = try await rpc.call("session.create", params: params)
        return Agent.from(rpc: resp.session)
    }

    /// Read every attachment URL into memory, base64-encode the bytes, and
    /// hash with SHA-256 for the daemon's integrity check. Runs on a
    /// detached task so a multi-MB PDF doesn't block MainActor in
    /// `createSession`. Throws on the first read failure (NSFileReadError)
    /// — that bubbles up as a dispatch toast instead of silently dropping
    /// the file. Returns `[]` when `urls` is empty so the wire payload is
    /// trivially small for the common no-attachment dispatch.
    nonisolated private static func loadAttachmentPayloads(_ urls: [URL]) async throws -> [RPCAttachment] {
        guard !urls.isEmpty else { return [] }
        return try await Task.detached(priority: .userInitiated) {
            try urls.map { url in
                let data = try Data(contentsOf: url)
                let digest = SHA256.hash(data: data)
                let hex = digest.map { String(format: "%02x", $0) }.joined()
                return RPCAttachment(
                    name: url.lastPathComponent,
                    bytes_b64: data.base64EncodedString(),
                    sha256: hex
                )
            }
        }.value
    }

    func killSession(id: String) async throws {
        let params = AnyEncodable(SessionKillParams(id: id))
        let _: SessionKillResponse = try await rpc.call("session.kill", params: params)
    }

    func shipSession(id: String) async throws {
        let params = AnyEncodable(SessionShipParams(id: id))
        let _: SessionShipResponse = try await rpc.call("session.ship", params: params)
    }

    func sendInput(sessionId: String, text: String) async throws {
        // Older daemons (pre-`session.send_input`) return METHOD_NOT_FOUND.
        // We let that propagate as a JSONRPCError so the coordinator shows the
        // user a real toast rather than the silent stub the composer used
        // to be. The Mac app's distribution will require a matching daemon
        // version anyway — gating this on an Optional dance would mask the
        // version mismatch instead of surfacing it.
        let params = AnyEncodable(SessionSendInputParams(id: sessionId, text: text))
        let _: SessionSendInputResponse = try await rpc.call("session.send_input", params: params)
    }

    func resolveRebaseConflict(sessionId: String) async throws {
        let params = AnyEncodable(SessionResolveRebaseConflictParams(id: sessionId))
        let _: SessionResolveRebaseConflictResponse = try await rpc.call(
            "session.resolve_rebase_conflict", params: params
        )
    }

    func injectFeedback(sessionId: String) async throws {
        let params = AnyEncodable(SessionInjectFeedbackParams(id: sessionId))
        let _: SessionInjectFeedbackResponse = try await rpc.call(
            "session.inject_feedback", params: params
        )
    }

    func attachSession(id: String) async throws -> Agent {
        // RESTORE (Direct build): reattaching a terminal (Done/Killed/
        // Exited) session relaunches the agent — tmux pane spawn, sandbox
        // wrap, credential env, adapter exec — which lives entirely in the
        // `skoga attach <id>` CLI command. The `session.attach` RPC only
        // reprovisions the worktree + flips state to Running; it does NOT
        // start an agent process. A sandboxed Mac App Store build can't
        // spawn that subprocess, so reattach is unavailable here and the
        // History/Conversation "Attach" affordances are hidden behind
        // `SkogaBuild.isDirectBuild`. To bring reattach back in the Direct
        // build, restore the `skoga attach` shell-out here (see git
        // history for the prior implementation) — or add a daemon RPC that
        // performs the relaunch server-side, which would let both builds
        // share this path.
        throw DaemonActionError.attachUnavailable
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
        // Prefer the daemon's Claude-drafted message (`session.draft_message`
        // runs `claude -p` server-side with the byte-for-byte prompt
        // `skoga land` uses), so the modal pre-fills with the same text a
        // terminal land would produce. On any failure — claude missing
        // daemon-side, empty diff, the 120s timeout — fall back to the
        // structured `session.land_preview` (task-derived default) rather
        // than surfacing a modal error; the user can still edit the field,
        // and a worse default beats a hard-failed modal. If BOTH fail the
        // land_preview error propagates so the modal shows something real.
        if let drafted = try? await draftedPreview(for: sessionId) {
            return drafted
        }
        let params = AnyEncodable(SessionLandPreviewParams(id: sessionId))
        let resp: SessionLandPreviewResponse = try await rpc.call(
            "session.land_preview", params: params
        )
        return PRPreview(title: resp.title, body: resp.body)
    }

    /// Fetch the daemon-drafted commit / PR message (`session.draft_message`)
    /// and map it onto the modal's title/body. The daemon already splits the
    /// message, but a leading blank line in the model output can leave
    /// `title` empty — re-split via `splitCommitMessage` in that case (the
    /// same rule the CLI uses) so the title field never renders blank.
    /// Throws (letting `previewPR` fall back) on any RPC failure.
    private func draftedPreview(for sessionId: String) async throws -> PRPreview {
        let params = AnyEncodable(SessionDraftMessageParams(id: sessionId))
        let resp: SessionDraftMessageResponse = try await rpc.call(
            "session.draft_message", params: params
        )
        if resp.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return splitCommitMessage(resp.message)
        }
        return PRPreview(title: resp.title, body: resp.body)
    }

    func diffStat(for sessionId: String) async throws -> RPCDiffStat? {
        // Pre-#110 daemons don't expose this method; swallow
        // METHOD_NOT_FOUND so the PR modal degrades to "no diff numbers"
        // rather than failing open. Any other RPC error (transport,
        // session-not-found, decode) still propagates.
        let params = AnyEncodable(SessionDiffStatParams(id: sessionId))
        do {
            let resp: SessionDiffStatResponse = try await rpc.call(
                "session.diff_stat", params: params
            )
            return resp.diff_stat
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            return nil
        }
    }

    func changedFiles(for sessionId: String) async throws -> [String]? {
        // Pre-#changed_files daemons return METHOD_NOT_FOUND; swallow it
        // so the editor action gracefully falls back to "open the
        // worktree folder, no tabs" instead of throwing. Other RPC
        // errors (transport, session-not-found) propagate so the UI
        // can surface them.
        let params = AnyEncodable(SessionChangedFilesParams(id: sessionId))
        do {
            let resp: SessionChangedFilesResponse = try await rpc.call(
                "session.changed_files", params: params
            )
            return resp.files
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            return nil
        }
    }

    func landPR(for sessionId: String, title: String, body: String) async throws {
        // `session.land` drives the full squash + rebase + push + `gh pr
        // create` pipeline daemon-side. title/body are an all-or-nothing
        // pair on the wire — a partial pair returns INVALID_PARAMS — and
        // the PR modal always hands us both, so we send both and they win
        // over the daemon's default-message derivation. merge=false keeps
        // the PR-opening path (vs `skoga land --merge`).
        let params = AnyEncodable(SessionLandParams(
            id: sessionId, title: title, body: body, merge: false
        ))
        let _: SessionLandResponse = try await rpc.call("session.land", params: params)
    }

    func pushBranch(for sessionId: String) async throws {
        // `session.push` is the thin per-revision push (no squash, no PR) —
        // the daemon-side equivalent of `git push -u`. force=false; the
        // Mac's "View commits on GitHub" flow never force-pushes.
        let params = AnyEncodable(SessionPushParams(id: sessionId, force: false))
        let _: SessionPushResponse = try await rpc.call("session.push", params: params)
    }

    func remoteURL(for sessionId: String) async throws -> String? {
        // `session.remote_url` returns the session repo's `origin` URL (or
        // `nil` when no origin is configured), for building GitHub compare
        // links without reading git config in a subprocess.
        let params = AnyEncodable(SessionRemoteUrlParams(id: sessionId))
        let resp: SessionRemoteUrlResponse = try await rpc.call(
            "session.remote_url", params: params
        )
        return resp.url
    }

    func githubStatus() async throws -> RPCGitHubStatus {
        // METHOD_NOT_FOUND propagates as-is — the Settings view distinguishes
        // an outdated daemon (skogad < getskoga/skoga#97) from "gh is genuinely
        // missing" so the install CTA never lies about which side needs fixing.
        try await rpc.call("github.status")
    }

    @discardableResult
    func githubSetDefaultReviewer(_ reviewer: String) async throws -> RPCGitHubStatus {
        let params = AnyEncodable(GitHubSetDefaultReviewerParams(reviewer: reviewer))
        let resp: GitHubSetDefaultReviewerResponse = try await rpc.call(
            "github.set_default_reviewer", params: params
        )
        return resp.status
    }

    func credentialsList() async throws -> [RPCCredentialEntry] {
        // METHOD_NOT_FOUND propagates as-is so AppState can light up the
        // "daemon too old" row (skogad < getskoga/skoga#103). Anything
        // else — transport, decode — also propagates; the Settings view
        // surfaces it as an error row with a Retry button.
        let resp: CredentialsListResponse = try await rpc.call("credentials.list")
        return resp.entries
    }

    @discardableResult
    func credentialsSet(provider: RPCCredentialProvider, key: String) async throws -> RPCCredentialEntry {
        let params = AnyEncodable(CredentialsSetParams(provider: provider, key: key))
        let resp: CredentialsSetResponse = try await rpc.call("credentials.set", params: params)
        // The daemon's `CredentialsSetResponse` carries only presence —
        // it doesn't include a fresh `last_used` because no read of the
        // key has happened yet (Keychain writes don't bump it). Mirror
        // that by returning `last_used = nil`; the next `credentialsList`
        // or a successful `credentialsTest` will populate it.
        return RPCCredentialEntry(
            provider: resp.provider,
            has_key: resp.has_key,
            last_used: nil
        )
    }

    @discardableResult
    func credentialsDelete(provider: RPCCredentialProvider) async throws -> Bool {
        let params = AnyEncodable(CredentialsDeleteParams(provider: provider))
        let resp: CredentialsDeleteResponse = try await rpc.call("credentials.delete", params: params)
        return resp.deleted
    }

    func credentialsTest(provider: RPCCredentialProvider) async throws -> RPCCredentialsTestResult {
        let params = AnyEncodable(CredentialsTestParams(provider: provider))
        return try await rpc.call("credentials.test", params: params)
    }

    func recentRepos() async throws -> [RPCRecentRepo] {
        // Older daemons (pre-getskoga/skoga#91) don't speak this RPC; swallow
        // METHOD_NOT_FOUND so the Dispatch screen just renders without pills
        // and falls through to the folder picker. Anything else (transport,
        // decode) propagates — the view treats those the same as empty.
        let params = AnyEncodable(SessionRecentReposParams(limit: nil))
        do {
            let resp: SessionRecentReposResponse = try await rpc.call(
                "session.recent_repos", params: params
            )
            return resp.repos
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            return []
        }
    }

    func listModels(adapter: String?) async throws -> [RPCModelChoice] {
        // Errors propagate (including METHOD_NOT_FOUND on older daemons) so
        // `DaemonClientHolder.refreshModels` can distinguish "old daemon →
        // keep the baked-in fallback silently" from "transport failure →
        // also keep the fallback". Mirroring the credentials.list /
        // github.status pattern rather than recentRepos' swallow-at-client
        // shape, because here an empty list and an unsupported daemon mean
        // different things to the dropdown.
        let params = AnyEncodable(ModelsListParams(adapter: adapter))
        let resp: ModelsListResponse = try await rpc.call("models.list", params: params)
        return resp.models
    }

    func listNamedAgents() async throws -> [NamedAgent] {
        // Older daemons (pre-getskoga/skoga#33) don't speak `agents.list`;
        // swallow METHOD_NOT_FOUND so the dispatch grid and sidebar fall
        // back cleanly to ephemeral-only behavior. Transport/decode errors
        // still propagate — the consuming surfaces treat them the same as
        // an empty list, but the polling-fallback in AppCoordinator can
        // log them.
        do {
            let resp: AgentsListResponse = try await rpc.call("agents.list")
            return resp.agents
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            return []
        }
    }

    @discardableResult
    func createNamedAgent(name: String, role: String, defaultRepo: String?, defaultModel: String?) async throws -> NamedAgent {
        let params = AnyEncodable(AgentsCreateParams(
            name: name,
            role: role,
            default_repo: defaultRepo,
            default_model: defaultModel
        ))
        do {
            let resp: AgentsCreateResponse = try await rpc.call("agents.create", params: params)
            return resp.agent
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            // Older daemons (pre-skoga-mac#33 daemon-side work item)
            // don't speak `agents.create`. Translate -32601 into a
            // user-friendly error so the conversation-footer save
            // button toasts "Permanent agents need a newer daemon"
            // rather than a raw "method not found".
            throw NamedAgentsError.daemonUnsupported
        }
    }

    @discardableResult
    func updateNamedAgent(id: String, name: String?, role: String?, defaultRepo: String?, defaultModel: String?) async throws -> NamedAgent {
        let params = AnyEncodable(AgentsUpdateParams(
            id: id,
            name: name,
            role: role,
            default_repo: defaultRepo,
            default_model: defaultModel
        ))
        do {
            let resp: AgentsUpdateResponse = try await rpc.call("agents.update", params: params)
            return resp.agent
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            throw NamedAgentsError.daemonUnsupported
        }
    }

    @discardableResult
    func deleteNamedAgent(id: String) async throws -> Bool {
        let params = AnyEncodable(AgentsDeleteParams(id: id))
        do {
            let resp: AgentsDeleteResponse = try await rpc.call("agents.delete", params: params)
            return resp.deleted
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            throw NamedAgentsError.daemonUnsupported
        }
    }

    nonisolated func policyDenials(sessionId: String?) async throws -> [RPCDenial] {
        // Older daemons (pre-getskoga/skoga#162) don't ship the
        // containment denial log; swallow METHOD_NOT_FOUND so the Policy
        // panel renders its "nothing denied" empty state rather than the
        // connection banner flipping to .notRunning on every poll. Any
        // other RPC error (transport, decode) propagates — the panel's
        // own loadDenials surfaces it as an error row, and the ride-along
        // poll in refresh() uses `try?` so it can't clobber the roster.
        let params = AnyEncodable(PolicyDenialsParams(session_id: sessionId))
        do {
            let resp: PolicyDenialsResponse = try await rpc.call("policy.denials", params: params)
            return resp.denials
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            return []
        }
    }

    func promoteDenial(id: String, scope: PolicyPromoteScope) async throws {
        // No METHOD_NOT_FOUND swallow here, mirroring `sendInput`: a
        // promote is a user-driven mutation, so an older daemon that
        // can't honor it should surface a real toast (via the
        // coordinator's catch) rather than appearing to succeed while
        // the denial silently persists. The daemon also rejects
        // deny-floor entries with an RPC error, which propagates the
        // same way — the UI already hides the promote control on floor
        // rows, so that path only fires on a stale optimistic click.
        let params = AnyEncodable(PolicyPromoteParams(id: id, scope: scope.rawValue))
        let resp: PolicyPromoteResponse = try await rpc.call("policy.promote", params: params)
        // `ok: false` means the daemon accepted the call but didn't apply
        // the rule. Throw so the coordinator toasts and keeps the row —
        // returning normally would optimistically drop a denial whose
        // access is still blocked. The daemon today only ever returns
        // `ok: true` on success (rejections come back as RPC errors), so
        // this guards the reserved idempotent path the response's doc
        // comment describes rather than a path that fires today.
        guard resp.ok else { throw PolicyError.notPromoted }
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

}

/// Failure modes for the daemon-client action paths that can't be served
/// by an RPC under App Sandbox. Surfaced to the user via toasts.
enum DaemonActionError: LocalizedError {
    /// Reattaching a terminal session relaunches the agent via the CLI,
    /// which a sandboxed daemon client can't do. Gated out of the UI in
    /// the App Store build; see `LiveDaemonClient.attachSession`.
    case attachUnavailable

    var errorDescription: String? {
        switch self {
        case .attachUnavailable:
            return "Reattaching to a finished session isn't available in this build yet."
        }
    }
}

// MARK: – RPCSession → Agent

extension Agent {
    /// Translate a daemon `Session` into a Mac `Agent`. `tokens` and
    /// `cost` come from the daemon's transcript-derived `usage` block
    /// (see getskoga/skoga#86); `commits` and `files` come from the
    /// cached `diff_stat` field (see getskoga/skoga#87). Either can be
    /// absent on older daemons or while the first refresh is still in
    /// flight — both fall back to 0 / `nil` so the UI renders zeros
    /// rather than crashing. `name`/`role` are derived from the id and
    /// the configured agent adapter.
    static func from(rpc s: RPCSession) -> Agent {
        let pendingQuestion = s.pending_question?.toConversationMessage()
        let pendingQuestionPayload: ConversationMessage.QuestionPayload? = {
            guard case .question(let q) = pendingQuestion else { return nil }
            return q
        }()
        let status = AgentStatus(rpc: s.state, waiting: s.waiting_since, idle: s.idle_since)
        let waiting = s.waiting_since != nil
        let conflicted = s.state == .conflicted || s.state == .syncBroken
        // Once a PR is open / merged / shipping, the agent is *expected* to
        // be paused awaiting review — `waiting_since` will be set by the
        // post-land hook, but that's the agent doing the right thing, not
        // a needs-attention signal. Suppress `attn` for these states so
        // the card doesn't render with the red blocked treatment.
        let inReview = s.state == .prOpen || s.state == .prMerged || s.state == .prClosed || s.state == .shipping
        let attn = (waiting && !inReview) || conflicted

        let attnMessage: String? = {
            if pendingQuestionPayload != nil { return "Agent is asking a question" }
            if waiting && !inReview { return "Agent is blocked waiting on input" }
            if s.state == .conflicted { return "Rebase conflict — needs resolution" }
            if s.state == .syncBroken { return "Sync broken — run `skoga sync --debug`" }
            return nil
        }()

        // `tokens_total` is `u64` on the wire — clamp into `Int` so a
        // pathological session can't trap on Int(_:) truncation. Any
        // 64-bit Mac will accept the full range; the clamp is belt-and-
        // suspenders against a malformed daemon emission.
        let tokens = s.usage.map { Int(clamping: $0.tokens_total) } ?? 0
        let cost = s.usage?.cost_usd ?? 0
        let usageByModel: [String: Agent.ModelUsage] = s.usage?.by_model.reduce(into: [:]) { acc, kv in
            acc[kv.key] = Agent.ModelUsage(
                tokens: Int(clamping: kv.value.tokens_total),
                cost: kv.value.cost_usd
            )
        } ?? [:]

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
            runtime: runtimeLabel(since: s.created_at),
            tokens: tokens,
            cost: cost,
            // `nil` diff_stat (older daemon, or the cache hasn't been
            // populated since session create yet) renders as 0/0 so the
            // run-details / card meta rows don't have to special-case
            // absence — same approach as the `usage` fallback above.
            commits: s.diff_stat?.commits ?? 0,
            files: s.diff_stat?.files_changed ?? 0,
            attn: attn,
            attnMessage: attnMessage,
            prUrl: s.landed_pr_url,
            usageByModel: usageByModel,
            pendingQuestion: pendingQuestionPayload,
            // Only meaningful while the daemon still has us in `.conflicted`.
            // The daemon clears the field on any transition out of conflict
            // (so a follow-up conflict re-arms the button), but suppressing
            // here as well means a stale value from an in-flight race never
            // leaks into the non-conflicted card.
            rebasePromptDispatchedAt: s.state == .conflicted ? s.rebase_prompt_dispatched_at : nil,
            // `.prMerged` / `.prClosed` (not `.shipping`) are the auto-ship
            // triggers: the daemon has reconciled the PR as merged or
            // closed-without-merge remotely but hasn't begun teardown.
            // `.shipping` is already mid-teardown, so we skip it to avoid
            // a redundant rejected RPC every poll.
            needsAutoShip: s.state == .prMerged || s.state == .prClosed,
            base: s.base,
            baseSha: s.base_sha,
            hostWorktree: s.worktree,
            createdAt: s.created_at,
            namedAgentId: s.named_agent_id
        )
    }
}

private extension AgentStatus {
    init(rpc state: RPCSessionState, waiting: Date?, idle: Date?) {
        // The state machine wins for any state past `.running` — once the
        // daemon has the session in pr-open / shipping / done / etc., a
        // `waiting_since` from the post-land hook shouldn't drag the pill
        // back to "Blocked" (the bug this init originally had). Waiting
        // only ever resolves to `.blocked` while the agent is still doing
        // active work.
        switch state {
        case .running:
            // .idle here means "Claude finished a turn, awaiting next prompt"
            // — the process is alive, just dormant. Distinct from .exited.
            if waiting != nil { self = .blocked }
            else if idle != nil { self = .idle }
            else { self = .running }
        case .conflicted, .syncBroken:
            self = .blocked
        case .killing:
            // .stopping is the transitional teardown state: process is being
            // wound down but cleanup hasn't completed. Kept distinct from
            // .exited so a card stuck mid-teardown (cleanup hung) is visibly
            // different from a cleanly-exited agent.
            self = .stopping
        case .agentExited:
            // .exited means the Claude process is gone (Ctrl-C, crash, or
            // post-teardown) but the daemon hasn't called this session
            // terminal yet — the worktree's still on disk. Distinct from
            // `.idle` because the user can't just "send another message"
            // to wake it; kept distinct from `.killed` for the user-facing
            // pill (a cleanly-exited agent reads differently from one the
            // daemon force-killed) even though both are re-attachable.
            self = .exited
        case .killed:
            // Daemon-terminal: original worktree torn down. Still
            // re-attachable — `session.attach` provisions a fresh worktree
            // from the recorded base branch + SHA. Kept distinct from
            // `.exited` so the pill conveys that the daemon force-killed
            // the agent rather than it exiting cleanly.
            self = .killed
        case .prOpen:
            self = .prOpen
        case .prMerged, .shipping:
            // `.shipping` is the post-merge teardown — the PR landed and the
            // daemon is winding the worktree down. Surfacing it as PR merged
            // (rather than a distinct "shipping" pill) keeps the user-facing
            // story simple: open → merged → done. `.prClosed` gets its own
            // pill (below) so an abandoned PR doesn't read as "merged".
            self = .prMerged
        case .prClosed:
            self = .prClosed
        case .done:
            self = .done
        }
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
