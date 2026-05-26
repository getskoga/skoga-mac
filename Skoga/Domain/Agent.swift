import Foundation

enum AgentStatus: String, CaseIterable, Codable, Hashable {
    case running, blocked, prOpen, prMerged, done, idle, stopping, exited

    var label: String {
        switch self {
        case .running:  "Running"
        case .blocked:  "Blocked"
        case .prOpen:   "PR open"
        case .prMerged: "PR merged"
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
    var sortRank: Int {
        switch self {
        case .blocked:  0
        case .running:  1
        case .stopping: 2
        case .prOpen:   3
        case .prMerged: 4
        case .done:     5
        case .idle:     6
        case .exited:   7
        }
    }
}

struct Agent: Identifiable, Hashable {
    let id: String
    let name: String
    let role: String
    let model: String
    let status: AgentStatus
    let task: String
    let repo: String
    let branch: String
    let progress: Double            // 0…1
    let runtime: String
    let tokens: Int
    let cost: Double
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
        progress: Double,
        runtime: String,
        tokens: Int,
        cost: Double,
        commits: Int,
        files: Int,
        attn: Bool,
        attnMessage: String?,
        prUrl: String?,
        pendingQuestion: ConversationMessage.QuestionPayload? = nil,
        rebasePromptDispatchedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.model = model
        self.status = status
        self.task = task
        self.repo = repo
        self.branch = branch
        self.progress = progress
        self.runtime = runtime
        self.tokens = tokens
        self.cost = cost
        self.commits = commits
        self.files = files
        self.attn = attn
        self.attnMessage = attnMessage
        self.prUrl = prUrl
        self.pendingQuestion = pendingQuestion
        self.rebasePromptDispatchedAt = rebasePromptDispatchedAt
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
            lhs.progress == rhs.progress &&
            lhs.tokens == rhs.tokens &&
            lhs.cost == rhs.cost &&
            lhs.commits == rhs.commits &&
            lhs.files == rhs.files &&
            lhs.attn == rhs.attn &&
            lhs.attnMessage == rhs.attnMessage &&
            lhs.prUrl == rhs.prUrl &&
            lhs.pendingQuestion == rhs.pendingQuestion &&
            lhs.rebasePromptDispatchedAt == rhs.rebasePromptDispatchedAt
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
        hasher.combine(progress)
        hasher.combine(tokens)
        hasher.combine(cost)
        hasher.combine(commits)
        hasher.combine(files)
        hasher.combine(attn)
        hasher.combine(attnMessage)
        hasher.combine(prUrl)
        hasher.combine(pendingQuestion)
        hasher.combine(rebasePromptDispatchedAt)
    }
}
