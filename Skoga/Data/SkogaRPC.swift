import Foundation

// MARK: – JSON-RPC 2.0 wire types

struct RPCRequest: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: AnyEncodable?
    let id: Int

    init(method: String, params: AnyEncodable? = nil, id: Int) {
        self.method = method
        self.params = params
        self.id = id
    }
}

struct RPCResponse<R: Decodable>: Decodable {
    let jsonrpc: String
    let id: Int
    let result: R?
    let error: RPCError?
}

struct RPCError: Decodable, Error {
    let code: Int
    let message: String
}

/// Notification frame: `{"jsonrpc":"2.0","method":"events.event","params":<Event>}`.
struct RPCNotification<P: Decodable>: Decodable {
    let jsonrpc: String
    let method: String
    let params: P
}

/// Erased Encodable for `params`. Used because each RPC takes a different params struct
/// and we want one `RPCRequest` type rather than a generic one per call site.
struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    init<E: Encodable>(_ wrapped: E) {
        self.encode = wrapped.encode
    }
    func encode(to encoder: Encoder) throws { try encode(encoder) }
}

// MARK: – Domain payloads (mirror crates/skoga-core/src/protocol.rs and session.rs)

/// Subset of the Rust `Session` struct — only the fields the Mac UI actually
/// consumes. Codable ignores unknown JSON keys, so adding more fields here as
/// they become needed is non-breaking.
struct RPCSession: Decodable {
    let id: String
    let task: String
    let agent: String
    let base: String
    let branch: String
    let repo_root: String
    /// Filesystem path to the session's linked git worktree. Needed by the
    /// Mac app to compute `git diff base...HEAD` for the Claude-drafted
    /// commit message that pre-fills the PR modal — without it we'd have
    /// to reimplement the daemon's sandbox-mode path resolution in Swift.
    let worktree: String?
    let created_at: Date
    let state: RPCSessionState
    let landed_pr_url: String?
    let waiting_since: Date?
    let idle_since: Date?
    /// Mirrors the daemon's `Session.pending_question` — set when the agent
    /// has an in-flight `AskUserQuestion` and the user hasn't answered yet.
    /// `nil` keeps the field optional so older daemons (pre-#100) still
    /// decode cleanly.
    let pending_question: RPCPendingQuestion?
    /// Specific model the adapter was launched with (e.g.
    /// `"claude-opus-4-7"`). `nil` for legacy sessions created before
    /// #92 and for sessions where the caller didn't pin a model. The
    /// Roster prefers this over `agent` when rendering the model line.
    let agent_model: String?
    /// Set by the daemon when the user invokes `session.resolve_rebase_conflict`
    /// (one-shot per conflict). Cleared automatically when the session
    /// transitions out of `.conflicted`. The Mac uses presence to flip
    /// the AgentCard's "Ask agent to rebase" button into a disabled
    /// "Prompt sent" state so a double-click can't paste the fix-up
    /// prompt twice into the agent's TUI.
    let rebase_prompt_dispatched_at: Date?
}

enum RPCSessionState: String, Decodable {
    case running
    case conflicted
    case agentExited     = "agent-exited"
    case prOpen          = "pr-open"
    case prMerged        = "pr-merged"
    case shipping
    case killing
    case done
    case killed
    case syncBroken      = "sync-broken"
}

struct VersionResponse: Decodable {
    let version: String
}

struct SessionListParams: Encodable {
    let include_terminal: Bool
}

struct SessionCreateParams: Encodable {
    let task: String
    let agent: String
    let base: String
    let repo_root: String
    let task_auto: Bool
    /// When true, skogad spawns a detached `skoga _dispatch_launch <id>`
    /// after persisting the session so the agent actually starts in a tmux
    /// pane. The Mac app has no in-process way to spawn tmux, so it always
    /// passes true — without it the daemon would create a worktree the
    /// agent never enters, and the session would reap to AgentExited
    /// 30 seconds later.
    let auto_launch: Bool
    /// First message handed to Claude on launch (the brief from the
    /// Dispatch form). Without this, the agent boots into its empty
    /// welcome screen and the conversation view stays blank — there's no
    /// way from the Mac to get the conversation started, so a missing
    /// initial prompt makes the whole flow look broken even when the
    /// agent is alive.
    let initial_prompt: String?
    /// Adapter-specific model identifier (e.g. `"claude-opus-4-7"`,
    /// `"gpt-5-codex"`). Persisted on the session record and forwarded
    /// to the adapter's CLI on every (re)launch — Claude becomes
    /// `claude --model <agent_model>`; the generic `exec:` adapter
    /// ignores it. `nil` means "use the adapter's CLI default".
    let agent_model: String?
}

struct SessionCreateResponse: Decodable {
    let session: RPCSession
}

struct SessionKillParams: Encodable {
    let id: String
}

struct SessionKillResponse: Decodable {
    let session: RPCSession
}

struct SessionSendInputParams: Encodable {
    let id: String
    /// Free-form text the daemon will paste into the agent's tmux pane
    /// (bracketed paste + Enter). Mirrors the `skoga revise` delivery path,
    /// so multi-line replies arrive at Claude as one paste event rather
    /// than a sequence of per-line submissions.
    let text: String
}

struct SessionSendInputResponse: Decodable {
    let session: RPCSession
}

struct SessionResolveRebaseConflictParams: Encodable {
    let id: String
}

struct SessionResolveRebaseConflictResponse: Decodable {
    let session: RPCSession
}

// MARK: – PTY streaming (session.attach_stream / pty_write / pty_resize)

struct SessionAttachStreamParams: Encodable {
    let id: String
    /// Initial pane dimensions to apply on attach. `nil` (or 0) tells the
    /// daemon to leave the existing tmux pane size alone — useful for
    /// cold-attach reconnects after a window resize during a disconnect,
    /// where we want to use whatever the previous attach set.
    let cols: UInt16?
    let rows: UInt16?
}

struct SessionAttachStreamResponse: Decodable {
    let session: RPCSession
    /// Base64-encoded bytes representing the visible pane state at the
    /// moment of attach. Clients should feed this into their terminal
    /// renderer BEFORE processing subsequent `session.pty_data`
    /// notifications so the cold-start view is the same as if they'd been
    /// attached the whole time.
    let snapshot_b64: String
}

struct SessionPtyWriteParams: Encodable {
    let id: String
    /// Base64-encoded raw input bytes (keystrokes, escape sequences,
    /// control bytes) to inject into the agent's tmux pane.
    let bytes_b64: String
}

struct SessionPtyWriteResponse: Decodable {}

struct SessionPtyResizeParams: Encodable {
    let id: String
    let cols: UInt16
    let rows: UInt16
}

struct SessionPtyResizeResponse: Decodable {}

/// `session.pty_data` notification payload. Streamed continuously on the
/// connection that issued `session.attach_stream` until the connection
/// closes or the agent's tmux session exits.
struct RPCPtyDataNotification: Decodable {
    let id: String
    let bytes_b64: String
}

/// Result of a successful `session.attach_stream`. The snapshot is the
/// pane's visible state at the moment of attach — feed it into the
/// terminal renderer first, then drain `bytes` for subsequent updates.
struct AttachedPTYStream {
    let snapshot: Data
    let session: RPCSession
    let bytes: AsyncStream<Data>
}

// MARK: – AskUserQuestion (session.pending_question / session.answer_question)

struct RPCPendingQuestion: Decodable, Hashable {
    let tool_use_id: String
    let question: String
    let header: String?
    let multi_select: Bool
    let options: [RPCQuestionOption]
    let asked_at: Date
}

struct RPCQuestionOption: Decodable, Hashable {
    let label: String
    let description: String?
}

struct SessionPendingQuestionParams: Encodable {
    let id: String
}

struct SessionPendingQuestionResponse: Decodable {
    let session: RPCSession
    let question: RPCPendingQuestion?
}

struct SessionAnswerQuestionParams: Encodable {
    let id: String
    /// Zero-based indices into the pending question's options. Single-
    /// select sends a one-element array; multi-select sends the full
    /// chosen set. Daemon rejects empty arrays.
    let selected_indices: [Int]
}

struct SessionAnswerQuestionResponse: Decodable {
    let session: RPCSession
}

/// Lightweight model of the `events.event` notification payload. Only the
/// fields we route on; the rest of the audit Event schema can be ignored
/// because we treat any event as a "refetch sessions" trigger.
struct RPCEvent: Decodable {
    let type: String
    let session_id: String?
}

// MARK: – session.conversation

struct SessionConversationParams: Encodable {
    let id: String
}

struct SessionConversationResponse: Decodable {
    let messages: [RPCConversationMessage]
}

/// Wire shape of one conversation entry. Discriminated by `kind` to mirror
/// the daemon's `ConversationMessage` enum. Converted to the Mac's domain
/// `ConversationMessage` at the boundary because the domain type isn't
/// directly Codable.
///
/// `id` is critical: the daemon sources it from the Claude transcript's
/// per-record uuid (with a block-index suffix for assistant records that
/// emit multiple entries), so repeated polls produce the same id for the
/// same logical row. Without that, SwiftUI's `ForEach` would see every
/// cell as new on every refetch and tear down scroll position / focus.
struct RPCConversationMessage: Decodable {
    let id: String
    let kind: Kind
    let from: String?
    let when: String?
    let text: [String]?
    let runtime_label: String?
    let tool: String?
    let path: String?
    let cmd: String?
    let lines: String?
    let result: String?
    let adds: Int?
    let rems: Int?

    enum Kind: String, Decodable {
        case msg, tool, write
    }

    /// Map a wire entry to a domain `ConversationMessage`. Returns nil for
    /// malformed entries (missing required fields) so the UI doesn't have
    /// to handle partial rows.
    func toDomain() -> ConversationMessage? {
        switch kind {
        case .msg:
            guard let from, let when, let text else { return nil }
            return .msg(.init(
                id: id,
                from: from,
                when: when,
                text: text,
                runtimeLabel: runtime_label,
                initialOverride: nil
            ))
        case .tool:
            guard let tool else { return nil }
            return .tool(.init(
                id: id,
                tool: tool,
                path: path,
                lines: lines,
                cmd: cmd,
                result: result
            ))
        case .write:
            guard let path, let adds, let rems else { return nil }
            return .write(.init(id: id, path: path, adds: adds, rems: rems))
        }
    }
}

extension RPCPendingQuestion {
    /// Materialize the daemon's pending question as an in-feed conversation
    /// row. The session.conversation RPC reconstructs history from the
    /// Claude transcript, which doesn't yet contain a `tool_result` for an
    /// in-flight AskUserQuestion — so the question would otherwise be
    /// invisible in the feed until the user answers and the agent
    /// continues. Synthesizing the row here gives the user something to
    /// click while the call is still pending.
    ///
    /// The row id is the tool_use_id so SwiftUI's ForEach identifies the
    /// row stably across polls.
    func toConversationMessage() -> ConversationMessage {
        .question(.init(
            id: tool_use_id,
            label: header ?? "Question",
            body: question.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
            options: options.map { .init(label: $0.label, description: $0.description) },
            multiSelect: multi_select,
            toolUseId: tool_use_id
        ))
    }
}

// MARK: – session.recent_repos

/// One entry in the `session.recent_repos` response (see getskoga/skoga#91).
/// Each entry aggregates every past `session.create` against `repo_root`
/// into a single pill the Dispatch screen renders — `last_used` drives
/// ordering, `runs_count` lets the UI hint at activity (not currently
/// shown, but kept on the wire for future use).
struct RPCRecentRepo: Decodable, Hashable, Identifiable {
    let repo_root: String
    let display_name: String
    let last_used: Date
    let runs_count: Int

    /// `Identifiable` over `repo_root` because the daemon dedups by path,
    /// so it's stable across refetches. Lets `ForEach` keep the pill's
    /// selection state stable when the polled list reshuffles by
    /// `last_used`.
    var id: String { repo_root }
}

struct SessionRecentReposParams: Encodable {
    /// Cap on the number of entries returned. `nil` lets the daemon
    /// apply its default (currently 8).
    let limit: Int?
}

struct SessionRecentReposResponse: Decodable {
    let repos: [RPCRecentRepo]
}

// MARK: – github.status / github.set_default_reviewer

/// Wire shape of `github.status` (see getskoga/skoga#97). All fields are
/// independently optional so the UI can render partial truths: `gh` may be
/// installed but not on PATH for our subprocess, authenticated against a
/// different host, etc. The Mac surfaces the gap as a CTA rather than an
/// error.
///
/// `default_reviewer` is the persisted-in-config value the PR modal pre-
/// fills as the reviewers chip. The daemon owns persistence so the setting
/// follows the user across machines that share the same skoga config.
struct RPCGitHubStatus: Decodable, Equatable {
    let installed: Bool
    let authenticated: Bool
    let login: String?
    let default_account: String?
    let scopes: [String]
    let default_reviewer: String?
}

struct GitHubSetDefaultReviewerParams: Encodable {
    /// Empty string clears the persisted value. The daemon's config layer
    /// treats `""` as "unset" so callers don't need a separate clear RPC.
    let reviewer: String
}

struct GitHubSetDefaultReviewerResponse: Decodable {
    let status: RPCGitHubStatus
}

// MARK: – credentials.* (model-provider API keys)

/// Provider identifier for `credentials.*` RPCs (see getskoga/skoga#103).
/// Mirrors the Rust `CredentialProvider` enum: wire format is the
/// lowercase string (`"anthropic"`, `"openai"`) so both the Mac and the
/// CLI pass the same canonical token. New providers extend this enum as
/// adapters declare env-var bindings on the daemon side.
enum RPCCredentialProvider: String, Codable, CaseIterable, Equatable, Hashable {
    case anthropic
    case openai

    /// User-facing label (Title Case) for the Settings → Models & keys
    /// section header.
    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai:    "OpenAI"
        }
    }

    /// Adapter that consumes this provider's key. Used to group the
    /// "default model" picker with its provider — the daemon's per-
    /// adapter `credential_providers` declares the binding (Claude →
    /// Anthropic, Codex → OpenAI), but the Mac doesn't have access to
    /// that map at runtime so we mirror it here.
    var adapter: String {
        switch self {
        case .anthropic: "claude"
        case .openai:    "codex"
        }
    }
}

/// One entry in the `credentials.list` response. `has_key` is the
/// presence bit — the actual key never crosses the RPC boundary on
/// reads. `last_used` is the ISO-8601 timestamp of the most recent
/// successful Keychain read (set on agent launch + on
/// `credentials.test`); `nil` means never.
struct RPCCredentialEntry: Decodable, Equatable, Identifiable {
    let provider: RPCCredentialProvider
    let has_key: Bool
    let last_used: String?

    /// `Identifiable` lets SwiftUI's `ForEach` track the row by provider
    /// across refetches so the masked-key field and any inline test
    /// result don't remount on every poll.
    var id: RPCCredentialProvider { provider }
}

struct CredentialsListResponse: Decodable {
    let entries: [RPCCredentialEntry]
}

struct CredentialsSetParams: Encodable {
    let provider: RPCCredentialProvider
    /// Raw API key. Trimmed daemon-side; empty/whitespace-only is
    /// rejected (use `credentials.delete` to clear).
    let key: String
}

struct CredentialsSetResponse: Decodable {
    let provider: RPCCredentialProvider
    let has_key: Bool
}

struct CredentialsDeleteParams: Encodable {
    let provider: RPCCredentialProvider
}

struct CredentialsDeleteResponse: Decodable {
    let provider: RPCCredentialProvider
    /// `true` if a Keychain entry existed and was deleted; `false` if
    /// there was nothing to delete (idempotent — same shape either way).
    let deleted: Bool
}

struct CredentialsTestParams: Encodable {
    let provider: RPCCredentialProvider
}

/// Outcome of `credentials.test`. Per the daemon contract, this never
/// errors at the RPC layer — every probe failure (no key, network, 401,
/// 403, malformed reply) collapses to `ok: false` with a human-readable
/// `message`. The Mac renders `message` inline next to the row.
struct RPCCredentialsTestResult: Decodable, Equatable {
    let provider: RPCCredentialProvider
    let ok: Bool
    let message: String
    let latency_ms: UInt64?
}
