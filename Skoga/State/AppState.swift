import SwiftUI
import Foundation

enum AppView: String, Hashable {
    case roster, conversation, dispatch, review, telemetry
}

/// Top-level app state mirroring the React App's local state — view selection, filters,
/// the currently open agent, search query, toasts, and the optional in-flight PR target.
@MainActor
final class AppState: ObservableObject {

    // ── Selection ────────────────────────────────────────────
    @Published var view: AppView = .roster
    @Published var openAgentId: String? = nil
    @Published var prAgentId: String? = nil
    @Published var commandPaletteOpen: Bool = false

    // ── Filters ──────────────────────────────────────────────
    enum Filter: String, CaseIterable, Hashable { case all, running, blocked, review, done, idle }
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

    let client: DaemonClient
    private let isMock: Bool

    init(client: DaemonClient? = nil, isMock: Bool = true) {
        self.client = client ?? MockDaemonClient()
        self.isMock = isMock
        self.daemonStatus = isMock ? .mock : .connecting
    }

    func bootstrap() async {
        await refresh()
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

    func dispatch(task: String, agent: String, base: String, repoRoot: URL) async {
        do {
            let created = try await client.createSession(task: task, agent: agent, base: base, repoRoot: repoRoot)
            let title = task.count > 48 ? task.prefix(48) + "…" : Substring(task)
            showToast("Dispatched \"\(title)\" → \(created.repo) (\(created.id.prefix(6)))")
            backToRoster()
            await refresh()
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
    private func startPollingFallback() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.refresh()
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
        do {
            conversation = try await client.conversation(for: id)
            timeline = try await client.timeline(for: id)
        } catch {
            // mock won't fail
        }
    }

    // ── Derived counts ───────────────────────────────────────

    struct Counts {
        let total: Int
        let running: Int
        let blocked: Int
        let review: Int
        let done: Int
        let idle: Int
        let tokens: Int
    }

    var counts: Counts {
        Counts(
            total:   agents.count,
            running: agents.filter { $0.status == .running }.count,
            blocked: agents.filter { $0.status == .blocked }.count,
            review:  agents.filter { $0.status == .review  }.count,
            done:    agents.filter { $0.status == .done    }.count,
            idle:    agents.filter { $0.status == .idle    }.count,
            tokens:  agents.reduce(0) { $0 + $1.tokens }
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
        case .review:       "Review · \(counts.review) ready"
        case .telemetry:    "Telemetry"
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
