import Foundation

enum AgentStatus: String, CaseIterable, Codable, Hashable {
    case running, blocked, prOpen, prMerged, prClosed, done, idle, stopping, exited

    var label: String {
        switch self {
        case .running:  "Running"
        case .blocked:  "Blocked"
        case .prOpen:   "PR open"
        case .prMerged: "PR merged"
        case .prClosed: "PR closed"
        case .done:     "Done"
        case .idle:     "Idle"
        case .stopping: "Stopping"
        case .exited:   "Exited"
        }
    }

    /// Ordering used by the Roster — blocked first because it needs the manager.
    /// `.stopping` sits between `.running` and `.prOpen` because a card that
    /// gets stuck mid-teardown is something the user needs to *see* and act on.
    /// `.exited` lands after `.idle` — both are "agent isn't doing anything"
    /// but exited carries less urgency (process is gone, not just paused).
    /// `.prClosed` (abandoned PR) sits next to `.prMerged` — both are
    /// post-review terminal-ish states; the visual + auto-ship treatment is
    /// the same, only the toast text and pill color differ.
    /// Terminal states — the agent process is gone and the tmux pane
    /// has been torn down, so the live PTY path can't attach. The
    /// History view drives the user into these sessions and the
    /// ConversationView branches to a read-only transcript renderer
    /// when this is true.
    var isTerminal: Bool {
        switch self {
        case .done, .exited, .prMerged, .prClosed: true
        case .running, .blocked, .prOpen, .idle, .stopping: false
        }
    }

    var sortRank: Int {
        switch self {
        case .blocked:  0
        case .running:  1
        case .stopping: 2
        case .prOpen:   3
        case .prMerged: 4
        case .prClosed: 5
        case .done:     6
        case .idle:     7
        case .exited:   8
        }
    }
}

struct Agent: Identifiable, Hashable {
    /// Per-model slice of a session's cumulative token + cost totals.
    /// Built from the daemon's `SessionUsage.by_model` map and rolled up
    /// across the roster by the Telemetry view. `tokens` is the four-bucket
    /// sum (input + output + cache_creation + cache_read) so the by-model
    /// table totals reconcile with the session-level "tokens" cell.
    struct ModelUsage: Hashable {
        let tokens: Int
        let cost: Double
    }

    let id: String
    let name: String
    let role: String
    let model: String
    let status: AgentStatus
    let task: String
    let repo: String
    let branch: String
    /// Base branch the session was forked from (`s.base` on the wire).
    /// Used by the conversation side-panel's run-details row alongside
    /// `baseSha` so the user can see which long-lived branch this run
    /// will eventually merge into.
    let base: String
    /// Short SHA the session was forked at, if the daemon resolved one.
    /// Rendered as the suffix after `base` (e.g. "main · a91f3d2") so
    /// debugging long-lived runs against a moving target branch is
    /// possible. `nil` for legacy sessions persisted before the daemon
    /// started recording this, and for mock seeds that don't bother.
    let baseSha: String?
    let runtime: String
    let tokens: Int
    let cost: Double
    /// Per-model breakdown of this session's `tokens`/`cost`. Empty for
    /// mock seeds and for sessions whose daemon doesn't compute usage yet
    /// (pre-getskoga/skoga#86) — Telemetry falls back to bucketing by
    /// `Agent.model` when this is empty so the table still renders.
    let usageByModel: [String: ModelUsage]
    let commits: Int
    let files: Int
    let attn: Bool
    let attnMessage: String?
    let prUrl: String?
    /// Structured `AskUserQuestion` prompt the agent is currently waiting
    /// on, if any. The conversation view renders this as a `ConvQuestionRow`
    /// with clickable options. `nil` for sessions whose agent isn't
    /// currently asking — the common case.
    let pendingQuestion: ConversationMessage.QuestionPayload?
    /// Daemon timestamp of the last `session.resolve_rebase_conflict`
    /// dispatch on the current conflict. `nil` means no prompt has been
    /// sent for this conflict yet; the AgentCard renders the active
    /// "Ask agent to rebase" button. When `Some`, the button flips to a
    /// disabled "Prompt sent" state. The daemon clears this field on
    /// any transition out of `.conflicted`, so a new conflict re-arms
    /// the button automatically.
    let rebasePromptDispatchedAt: Date?
    /// True when the daemon's raw RPC state is `pr-merged` or `pr-closed`
    /// — the PR landed or was abandoned remotely but `session.ship` hasn't
    /// been called yet. The coordinator uses this to fire an automatic ship
    /// so a finished PR autocloses its session the same way `skoga ship`
    /// would. Distinct from `AgentStatus.prMerged` (which collapses
    /// `pr-merged` and `shipping` into one pill) because shipping a session
    /// that's already shipping would just be a redundant rejected RPC.
    let needsAutoShip: Bool
    /// Filesystem path to the session's linked git worktree, mirroring
    /// `RPCSession.worktree`. Surfaced here so the "Drop into editor"
    /// quick action (issue #9) can hand the path off to the user's
    /// editor of choice. `nil` for sessions whose daemon doesn't expose
    /// it yet or where path resolution failed daemon-side — the action
    /// degrades to a "couldn't resolve worktree" toast in that case.
    let hostWorktree: String?
    /// Wall-clock timestamp the session was created. Mirrors
    /// `RPCSession.created_at`. Used by the History view's date-range
    /// filter and "when" column. Mock seeds get `Date()` via the
    /// memberwise default so the 20+ existing literals don't have to
    /// be edited.
    let createdAt: Date

    /// Memberwise init with a default for `pendingQuestion` so design
    /// seeds (all 20+ Agent literals in MockDaemonClient) don't have to
    /// be edited every time a new optional field lands.
    init(
        id: String,
        name: String,
        role: String,
        model: String,
        status: AgentStatus,
        task: String,
        repo: String,
        branch: String,
        runtime: String,
        tokens: Int,
        cost: Double,
        commits: Int,
        files: Int,
        attn: Bool,
        attnMessage: String?,
        prUrl: String?,
        usageByModel: [String: ModelUsage] = [:],
        pendingQuestion: ConversationMessage.QuestionPayload? = nil,
        rebasePromptDispatchedAt: Date? = nil,
        needsAutoShip: Bool = false,
        base: String = "main",
        baseSha: String? = nil,
        hostWorktree: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.model = model
        self.status = status
        self.task = task
        self.repo = repo
        self.branch = branch
        self.base = base
        self.baseSha = baseSha
        self.runtime = runtime
        self.tokens = tokens
        self.cost = cost
        self.commits = commits
        self.files = files
        self.attn = attn
        self.attnMessage = attnMessage
        self.prUrl = prUrl
        self.usageByModel = usageByModel
        self.pendingQuestion = pendingQuestion
        self.rebasePromptDispatchedAt = rebasePromptDispatchedAt
        self.needsAutoShip = needsAutoShip
        self.hostWorktree = hostWorktree
        self.createdAt = createdAt
    }

    /// `branch` after the first slash, used to label rows like "auth-scope-refresh".
    var branchSlug: String {
        guard let i = branch.firstIndex(of: "/") else { return branch }
        return String(branch[branch.index(after: i)...])
    }

    /// Two-letter initial used in avatar tiles.
    var initials: String {
        String(name.prefix(2))
    }

    /// Short model label — "claude-sonnet" from "claude-sonnet-4-7".
    var shortModel: String {
        let parts = model.split(separator: "-")
        return parts.prefix(2).joined(separator: "-")
    }

    /// True when the agent is parked specifically because the opportunistic
    /// rebase loop hit a conflict — distinct from other `attn` flavors
    /// (waiting on input, sync broken, pending question). Gates the
    /// "Ask agent to rebase" button on the card so the action only
    /// appears where it makes sense. The check pivots on the
    /// attnMessage prefix the live client emits for `.conflicted` —
    /// the daemon's actual session state isn't carried through to the
    /// Agent model, so the string is the only signal we have here.
    var isRebaseConflict: Bool {
        attn && (attnMessage?.hasPrefix("Rebase conflict") ?? false)
    }

    // MARK: – Equatable / Hashable
    //
    // Hand-rolled to exclude `runtime`, which the live daemon recomputes
    // from `Date()` on every `session.list` round-trip (see
    // `LiveDaemonClient.runtimeLabel`). For sessions under a minute old
    // it ticks every second; older ones tick every minute. If `runtime`
    // counted toward equality, the diff-guard in `AppCoordinator.refresh()`
    // would short-circuit roughly never and `agents` would be reassigned
    // on every poll, defeating the whole point of the guard.
    //
    // The displayed runtime stays current because the live client always
    // returns the latest string in every Agent it builds — this only
    // controls whether "12s → 13s" is treated as a "did the array
    // change?" signal.

    static func == (lhs: Agent, rhs: Agent) -> Bool {
        lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.role == rhs.role &&
            lhs.model == rhs.model &&
            lhs.status == rhs.status &&
            lhs.task == rhs.task &&
            lhs.repo == rhs.repo &&
            lhs.branch == rhs.branch &&
            lhs.base == rhs.base &&
            lhs.baseSha == rhs.baseSha &&
            lhs.tokens == rhs.tokens &&
            lhs.cost == rhs.cost &&
            lhs.usageByModel == rhs.usageByModel &&
            lhs.commits == rhs.commits &&
            lhs.files == rhs.files &&
            lhs.attn == rhs.attn &&
            lhs.attnMessage == rhs.attnMessage &&
            lhs.prUrl == rhs.prUrl &&
            lhs.pendingQuestion == rhs.pendingQuestion &&
            lhs.rebasePromptDispatchedAt == rhs.rebasePromptDispatchedAt &&
            lhs.needsAutoShip == rhs.needsAutoShip &&
            lhs.hostWorktree == rhs.hostWorktree &&
            lhs.createdAt == rhs.createdAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(role)
        hasher.combine(model)
        hasher.combine(status)
        hasher.combine(task)
        hasher.combine(repo)
        hasher.combine(branch)
        hasher.combine(base)
        hasher.combine(baseSha)
        hasher.combine(tokens)
        hasher.combine(cost)
        hasher.combine(usageByModel)
        hasher.combine(commits)
        hasher.combine(files)
        hasher.combine(attn)
        hasher.combine(attnMessage)
        hasher.combine(prUrl)
        hasher.combine(pendingQuestion)
        hasher.combine(rebasePromptDispatchedAt)
        hasher.combine(needsAutoShip)
        hasher.combine(hostWorktree)
        hasher.combine(createdAt)
    }
}
