import SwiftUI
import Foundation

enum AppView: String, Hashable {
    case roster, conversation, dispatch, review, telemetry, settings
}

/// Top-level app state mirroring the React App's local state — view selection, filters,
/// the currently open agent, search query, toasts, and the optional in-flight PR target.
@MainActor
final class AppState: ObservableObject {

    // ── Selection ────────────────────────────────────────────
    @Published var view: AppView = .roster
    @Published var openAgentId: String? = nil
    @Published var prAgentId: String? = nil
    @Published var stopAgentId: String? = nil
    @Published var commandPaletteOpen: Bool = false

    // ── Filters ──────────────────────────────────────────────
    enum Filter: String, CaseIterable, Hashable { case all, running, blocked, prOpen, done, idle, stopping, exited }
    @Published var filter: Filter = .all
    @Published var query: String = ""

    // ── Composer ─────────────────────────────────────────────
    @Published var pendingReply: String = ""

    // ── Toast ────────────────────────────────────────────────
    @Published var toast: String? = nil

    // ── Data ─────────────────────────────────────────────────
    @Published private(set) var agents: [Agent] = []
    @Published private(set) var activity: [Double] = []
    @Published private(set) var conversation: [ConversationMessage] = []
    @Published private(set) var timeline: [TimelineEntry] = []
    @Published private(set) var daemonStatus: DaemonStatus
    /// Last fetched `gh` CLI status from the daemon. `nil` before the
    /// first fetch completes — Settings → GitHub renders a loading row
    /// in that window, and the PR modal's reviewer field falls back to
    /// the "+ add" placeholder.
    @Published private(set) var githubStatus: RPCGitHubStatus?
    /// True when the daemon doesn't speak `github.status` (METHOD_NOT_FOUND).
    /// Surfaced as a distinct Settings row so the user sees "Upgrade the
    /// daemon" instead of a misleading "Install gh CLI" CTA when in fact
    /// `gh` may already be on disk and authenticated.
    @Published private(set) var githubDaemonUnsupported: Bool = false
    /// Localized error from the most recent github.status fetch, kept
    /// only when we have no cached status to fall back on. Background
    /// poll failures while a status is already in hand stay silent —
    /// the existing UI doesn't need to flicker on every transient drop.
    @Published private(set) var githubStatusError: String?

    let client: DaemonClient
    private let isMock: Bool

    init(client: DaemonClient? = nil, isMock: Bool = true) {
        self.client = client ?? MockDaemonClient()
        self.isMock = isMock
        self.daemonStatus = isMock ? .mock : .connecting
    }

    func bootstrap() async {
        await refresh()
        // Fire-and-forget the gh-status fetch — it shells out to
        // `gh auth status` on the daemon side, which costs a few hundred
        // ms. Blocking the bootstrap means the Roster takes that long to
        // appear; the PR modal and Settings each await the same call on
        // their own surface anyway.
        Task { await refreshGitHubStatus() }
        startEventLoop()
        startPollingFallback()

        if let id = ProcessInfo.processInfo.environment["SKOGA_OPEN"], agents.contains(where: { $0.id == id }) {
            openConversation(for: id)
        }
        if let view = ProcessInfo.processInfo.environment["SKOGA_VIEW"], let v = AppView(rawValue: view) {
            self.view = v
        }
        if let pr = ProcessInfo.processInfo.environment["SKOGA_PR"], agents.contains(where: { $0.id == pr }) {
            self.prAgentId = pr
        }
        if ProcessInfo.processInfo.environment["SKOGA_CMD"] != nil {
            self.commandPaletteOpen = true
        }
    }

    /// Re-fetch the agent list and, on the live path, update `daemonStatus`
    /// based on whether `daemon.version` + `session.list` round-trip cleanly.
    /// The activity series stays on whatever the client returned at boot
    /// (zero-length on live; the seed wave on mock) — skogad doesn't emit
    /// per-minute load yet so re-polling it is wasted work.
    func refresh() async {
        if isMock {
            agents = (try? await client.listAgents()) ?? agents
            activity = (try? await client.activitySeries()) ?? activity
            return
        }
        do {
            let version = try await client.daemonVersion()
            agents = try await client.listAgents()
            daemonStatus = .connected(version: version)
        } catch {
            daemonStatus = .notRunning(detail: describe(error))
        }
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
            githubStatus = updated
            githubDaemonUnsupported = false
            githubStatusError = nil
        } catch let JSONRPCError.rpc(rpcError) where rpcError.code == -32601 {
            githubDaemonUnsupported = true
            githubStatusError = nil
        } catch {
            githubDaemonUnsupported = false
            if githubStatus == nil {
                githubStatusError = describe(error)
            }
        }
    }

    /// Persist the PR-modal default reviewer to the daemon's config.
    /// Trim + treat empty as a clear so the Settings text field can both
    /// set and unset the value with the same Save action. Surfaces
    /// failures via a toast — losing this silently would leave the user
    /// thinking the value stuck.
    func setDefaultReviewer(_ reviewer: String) async {
        let trimmed = reviewer.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let updated = try await client.githubSetDefaultReviewer(trimmed)
            githubStatus = updated
            // Toast off the daemon's canonical form rather than the user's
            // input. The daemon may normalize (strip a leading `@`,
            // lowercase the handle, expand org aliases) — toasting the
            // pre-normalized text would tell the user a different story
            // than the value that actually landed in config.
            if let persisted = updated.default_reviewer, !persisted.isEmpty {
                showToast("Default reviewer set to \(persisted).")
            } else {
                showToast("Cleared default reviewer.")
            }
        } catch {
            showToast("Couldn't save reviewer: \(describe(error))")
        }
    }

    func dispatch(task: String, agent: String, model: String?, base: String, repoRoot: URL, initialPrompt: String?) async {
        do {
            let created = try await client.createSession(task: task, agent: agent, model: model, base: base, repoRoot: repoRoot, initialPrompt: initialPrompt)
            let title = task.count > 48 ? task.prefix(48) + "…" : Substring(task)
            showToast("Dispatched \"\(title)\" → \(created.repo) (\(created.name))")
            // Jump straight to the new session's conversation view instead of
            // bouncing back to the roster. Before this change, the user had
            // to find the freshly-dispatched card and click it — and because
            // the daemon now also spawns the agent process (auto_launch),
            // there's a real conversation about to appear here. The view
            // starts empty (no transcript on disk yet) and fills in once
            // Claude's SessionStart hook records the agent_session_id, which
            // happens within a couple of seconds of tmux bringing the pane
            // up. The 5s session.conversation poll picks it up from there.
            await refresh()
            openConversation(for: created.id)
        } catch {
            showToast("Dispatch failed: \(describe(error))")
        }
    }

    func kill(agentId: String) async {
        do {
            try await client.killSession(id: agentId)
            showToast("Killed session \(agentId.prefix(6))")
            await refresh()
        } catch {
            showToast("Kill failed: \(describe(error))")
        }
    }

    /// Interrupt the agent's current turn without tearing the session down.
    /// We send a single ESC into the tmux pane — Claude Code's TUI treats
    /// that as "stop generating", which is the closest thing the agent has
    /// to a pause. The session, worktree, and conversation history all
    /// remain intact and the user can send a follow-up message to resume.
    func pause(agentId: String) async {
        do {
            try await client.ptyWrite(sessionId: agentId, bytes: Data([0x1b]))
            let name = agents.first(where: { $0.id == agentId })?.name ?? "agent"
            showToast("Paused \(name).")
        } catch {
            showToast("Pause failed: \(describe(error))")
        }
    }

    /// Deliver a composed reply to the running agent. The daemon pastes it
    /// into the agent's tmux pane; the message will surface in the feed on
    /// the next conversation poll (a few seconds), since the transcript
    /// jsonl is the source of truth for what's displayed.
    func sendReply(to agentId: String, text: String) async {
        do {
            try await client.sendInput(sessionId: agentId, text: text)
            let name = agents.first(where: { $0.id == agentId })?.name ?? "agent"
            showToast("Sent to \(name).")
        } catch {
            showToast("Send failed: \(describe(error))")
        }
    }

    /// Submit the user's selection to a pending `AskUserQuestion`. The
    /// daemon drives Claude's TUI picker via tmux key strokes and clears
    /// the pending state. We optimistically drop the question row from the
    /// conversation so the UI doesn't show a stale picker between answer
    /// and the next refresh.
    func answerQuestion(to agentId: String, selectedIndices: [Int]) async {
        let toolUseId = agents.first(where: { $0.id == agentId })?.pendingQuestion?.toolUseId
        do {
            try await client.answerQuestion(sessionId: agentId, selectedIndices: selectedIndices)
            if let toolUseId {
                conversation.removeAll {
                    if case .question(let q) = $0, q.toolUseId == toolUseId { return true }
                    return false
                }
            }
            await refresh()
            await loadConversation(agentId)
        } catch {
            showToast("Answer failed: \(describe(error))")
        }
    }

    private func startEventLoop() {
        let stream = client.events()
        Task { [weak self] in
            for await _ in stream {
                await self?.refresh()
            }
        }
    }

    /// Backstop for when the event stream isn't viable (mock mode, daemon
    /// down, socket closed after subscribe). A 5s tick is cheap and means a
    /// user who starts skogad after launching the app doesn't have to
    /// restart — the next poll switches the banner from `.notRunning` to
    /// `.connected` and the Roster lights up.
    ///
    /// When a conversation is open, we also refetch its messages on the
    /// same tick. The daemon reconstructs them from Claude's transcript
    /// jsonl, which is append-only and ids each row by uuid, so SwiftUI's
    /// ForEach keeps stable identity across polls — scroll position,
    /// focus, and animations stay put. Without this, a freshly dispatched
    /// agent never appears to "speak": loadConversation runs once on
    /// open, when the transcript is still empty.
    private func startPollingFallback() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self else { return }
                await self.refresh()
                if let id = self.openAgentId {
                    await self.loadConversation(id)
                }
            }
        }
    }

    private func describe(_ error: Error) -> String {
        if let rpc = error as? JSONRPCError {
            return rpc.errorDescription ?? "\(rpc)"
        }
        return error.localizedDescription
    }

    var openAgent: Agent? {
        guard let id = openAgentId else { return nil }
        return agents.first(where: { $0.id == id })
    }

    func openConversation(for id: String) {
        openAgentId = id
        view = .conversation
        pendingReply = ""
        Task { await loadConversation(id) }
    }

    func backToRoster() {
        view = .roster
        openAgentId = nil
        conversation = []
        timeline = []
    }

    private func loadConversation(_ id: String) async {
        // Mock client never throws; the live path throws on transport / RPC
        // failures. Empty-conversation is *not* an error (the daemon returns
        // [] for sessions with no transcript yet) — only surface real
        // failures so a fresh session doesn't toast on every open.
        do {
            var msgs = try await client.conversation(for: id)
            // The daemon's transcript-based conversation doesn't include the
            // in-flight AskUserQuestion (Claude only writes the tool_use
            // block once it completes), so append a synthesized question row
            // from the session's pending_question. The Agent has it after
            // the most recent refresh().
            if let pending = agents.first(where: { $0.id == id })?.pendingQuestion {
                let alreadyHas = msgs.contains {
                    if case .question(let q) = $0 { return q.id == pending.id }
                    return false
                }
                if !alreadyHas {
                    msgs.append(.question(pending))
                }
            }
            conversation = msgs
        } catch {
            conversation = []
            showToast("Conversation load failed: \(describe(error))")
        }
        do {
            timeline = try await client.timeline(for: id)
        } catch {
            timeline = []
        }
    }

    // ── Derived counts ───────────────────────────────────────

    struct Counts {
        let total: Int
        let running: Int
        let blocked: Int
        let prOpen: Int
        let done: Int
        let idle: Int
        let stopping: Int
        let exited: Int
        let tokens: Int
    }

    var counts: Counts {
        Counts(
            total:    agents.count,
            running:  agents.filter { $0.status == .running  }.count,
            blocked:  agents.filter { $0.status == .blocked  }.count,
            prOpen:   agents.filter { $0.status == .prOpen   }.count,
            done:     agents.filter { $0.status == .done     }.count,
            idle:     agents.filter { $0.status == .idle     }.count,
            stopping: agents.filter { $0.status == .stopping }.count,
            exited:   agents.filter { $0.status == .exited   }.count,
            tokens:   agents.reduce(0) { $0 + $1.tokens }
        )
    }

    struct Spend { let today: Double; let budget: Double }
    var spend: Spend { Spend(today: agents.reduce(0) { $0 + $1.cost }, budget: 40) }

    var filteredSortedAgents: [Agent] {
        var xs = agents
        if filter != .all, let status = AgentStatus(rawValue: filter.rawValue) {
            xs = xs.filter { $0.status == status }
        }
        if !query.isEmpty {
            let q = query.lowercased()
            xs = xs.filter {
                $0.name.lowercased().contains(q) ||
                $0.task.lowercased().contains(q) ||
                $0.repo.lowercased().contains(q) ||
                $0.role.lowercased().contains(q)
            }
        }
        return xs.sorted { $0.status.sortRank < $1.status.sortRank }
    }

    var contextLabel: String {
        switch view {
        case .roster:       "Roster · \(counts.total) agents"
        case .conversation: openAgent.map { "1:1 with \($0.name)" } ?? "Conversation"
        case .dispatch:     "Dispatch · new run"
        case .review:       "Review · \(counts.prOpen) open"
        case .telemetry:    "Telemetry"
        case .settings:     "Settings"
        }
    }

    // ── Toast helper ─────────────────────────────────────────
    func showToast(_ message: String, duration: TimeInterval = 3.4) {
        toast = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run { if self?.toast == message { self?.toast = nil } }
        }
    }
}
