import Foundation

/// One of the user's permanent, user-defined agents — Astrid the
/// frontend specialist, Bjorn the platform agent, etc. Lives alongside
/// the deterministic Norse-named pool from [`NordicNames`] but with
/// stable identity: the user picks the name, the daemon persists it,
/// and dispatches against the same NamedAgent route back to the same
/// permanent identity across daemon restarts (vs. ephemeral sessions,
/// whose name is just a hash of the session id).
///
/// Mirrors the daemon's `~/.skoga/state/named_agents.json` schema (see
/// daemon RPCs `agents.list / agents.create / agents.update /
/// agents.delete`). Carries everything the Mac UI needs to render the
/// agent's row in the sidebar guild list, prefer-pinned slot in the
/// Dispatch assignee grid, and the per-agent "X total runs" telemetry.
struct NamedAgent: Identifiable, Hashable, Codable {
    /// Stable identifier minted daemon-side at `agents.create`. Opaque
    /// to the Mac; we never construct one client-side so the daemon
    /// remains the source of truth for the namespace.
    let id: String
    /// User-chosen display name. Defaulted from the deterministic Norse
    /// name when the user accepts the "Save as permanent agent?" prompt,
    /// but free-form after that — they can rename "Astrid" to "Frontend
    /// Astrid" without losing the underlying NamedAgent identity.
    let name: String
    /// Free-form role label rendered in the assignee grid subline and
    /// the sidebar pin tooltip ("Frontend / SwiftUI"). Has no semantic
    /// effect on dispatch — the model is the only thing that affects
    /// runtime behavior — but lets the user file their permanent
    /// agents into mental buckets.
    let role: String
    /// Host clone path this agent prefers to work in. When set, the
    /// Dispatch screen surfaces the agent in the "Permanent" slot ahead
    /// of others whenever the selected repo matches. `nil` means "any
    /// repo" — the agent is still permanent, just unbiased on repo.
    let defaultRepo: String?
    /// Adapter+model id the agent is dispatched with by default
    /// (e.g. `"claude-opus-4-7"`). Mirrors `agent_model` on session
    /// records. `nil` means "use whatever the Dispatch form has
    /// selected".
    let defaultModel: String?
    /// Cumulative count of completed runs assigned to this agent.
    /// Bumped daemon-side on session terminal-success transitions
    /// (`.prMerged` / `.done`); the Mac only reads it for display.
    let totalRuns: Int
    /// Wall-clock timestamp of the agent's most recent dispatch.
    /// Drives the sidebar pin ordering ("Astrid · used 2h ago"). `nil`
    /// if the agent was created but never dispatched against yet.
    let lastUsed: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, role
        case defaultRepo = "default_repo"
        case defaultModel = "default_model"
        case totalRuns = "total_runs"
        case lastUsed = "last_used"
    }

    /// Two-letter avatar tile initials — matches the pattern
    /// [`Agent.initials`] uses for ephemeral agents so a permanent
    /// agent's tile reads visually identical to its ephemeral
    /// counterparts at the same name.
    var initials: String { String(name.prefix(2)) }
}

// MARK: – Wire types

/// Params for `agents.create`. The daemon mints `id` and stamps
/// `total_runs = 0` + `last_used = nil` — the Mac only supplies the
/// user-chosen pieces.
struct AgentsCreateParams: Encodable {
    let name: String
    let role: String
    let default_repo: String?
    let default_model: String?
}

struct AgentsCreateResponse: Decodable {
    let agent: NamedAgent
}

/// Params for `agents.update`. Any field set to `nil` is left alone
/// daemon-side (this is the "PATCH" shape, not the "PUT" shape). The
/// `id` selects the target.
struct AgentsUpdateParams: Encodable {
    let id: String
    let name: String?
    let role: String?
    let default_repo: String?
    let default_model: String?
}

struct AgentsUpdateResponse: Decodable {
    let agent: NamedAgent
}

struct AgentsDeleteParams: Encodable {
    let id: String
}

struct AgentsDeleteResponse: Decodable {
    let deleted: Bool
}

struct AgentsListResponse: Decodable {
    let agents: [NamedAgent]
}

// MARK: – Errors

/// Mac-side error surfaced when a write RPC (`agents.create / update
/// / delete`) hits a daemon that doesn't speak it yet. `listNamedAgents`
/// can degrade silently to `[]` because the dispatch grid and sidebar
/// just render empty, but a *write* attempt deserves a user-facing
/// message — "Permanent agents need a newer daemon" reads honestly,
/// while the raw `JSON-RPC -32601: method not found` doesn't.
enum NamedAgentsError: LocalizedError {
    case daemonUnsupported

    var errorDescription: String? {
        switch self {
        case .daemonUnsupported:
            "Permanent agents need a newer skogad. Run `skoga daemon upgrade`."
        }
    }
}
