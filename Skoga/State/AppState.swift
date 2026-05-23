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

    let client: DaemonClient

    init(client: DaemonClient? = nil) {
        self.client = client ?? MockDaemonClient()
    }

    func bootstrap() async {
        do {
            agents   = try await client.listAgents()
            activity = try await client.activitySeries()
        } catch {
            // mock client doesn't throw; real client wiring will surface this in a banner.
        }
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
