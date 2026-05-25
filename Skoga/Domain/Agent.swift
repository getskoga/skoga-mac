import Foundation

enum AgentStatus: String, CaseIterable, Codable, Hashable {
    case running, blocked, review, done, idle, stopping, exited

    var label: String {
        switch self {
        case .running:  "Running"
        case .blocked:  "Blocked"
        case .review:   "PR up"
        case .done:     "Done"
        case .idle:     "Idle"
        case .stopping: "Stopping"
        case .exited:   "Exited"
        }
    }

    /// Ordering used by the Roster — blocked first because it needs the manager.
    /// `.stopping` sits between `.running` and `.review` because a card that
    /// gets stuck mid-teardown is something the user needs to *see* and act on.
    /// `.exited` lands after `.idle` — both are "agent isn't doing anything"
    /// but exited carries less urgency (process is gone, not just paused).
    var sortRank: Int {
        switch self {
        case .blocked:  0
        case .running:  1
        case .stopping: 2
        case .review:   3
        case .done:     4
        case .idle:     5
        case .exited:   6
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

    /// `branch` after the first slash, used to label rows like "auth-scope-refresh".
    var branchSlug: String {
        guard let i = branch.firstIndex(of: "/") else { return branch }
        return String(branch[branch.index(after: i)...])
    }

    /// Two-letter initial used in avatar tiles.
    var initials: String {
        String(name.prefix(2))
    }

    /// Short model label — "claude-sonnet" from "claude-sonnet-4.7".
    var shortModel: String {
        let parts = model.split(separator: "-")
        return parts.prefix(2).joined(separator: "-")
    }
}
