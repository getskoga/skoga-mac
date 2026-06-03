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
    /// SHA the session's branch was forked from. Resolved by the daemon at
    /// `session.create` against the freshly-fetched sandbox tracking ref and
    /// persisted on the session record. `nil` for legacy sessions created
    /// before the field landed and for the rare case where the ref-resolve
    /// failed at create time. The conversation side-panel renders
    /// `base · short(base_sha)` when set, falling back to just `base`.
    let base_sha: String?
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
    /// Cumulative token + cost totals across the session, computed by the
    /// daemon from the Claude Code transcript jsonl (see getskoga/skoga#86).
    /// `nil` for older daemons that don't compute usage yet, or while the
    /// transcript hasn't produced an assistant turn yet — both render as
    /// "0 tok / $0.00" in the UI rather than as an error.
    let usage: RPCSessionUsage?
    /// Cached `merge_base(HEAD, base)..HEAD` diff stats for the session,
    /// populated by the daemon on `session.list` (see getskoga/skoga#87).
    /// `nil` means "never computed yet" — the side panel and agent card
    /// fall back to zeros until the next refresh fills it in. Distinct
    /// from the standalone `session.diff_stat` RPC, which the PR modal
    /// uses to force a fresh recompute regardless of cache state.
    let diff_stat: RPCDiffStat?
    /// `agents.list` id of the permanent agent this session was
    /// dispatched against, when the caller pinned one in the Dispatch
    /// grid (see `SessionCreateParams.named_agent_id`). `nil` for the
    /// ephemeral path and for any older daemon that doesn't stamp
    /// this on session records yet. The Sidebar reads it to route a
    /// pin click straight to the right open session instead of
    /// matching by display-name (which would alias across renames).
    let named_agent_id: String?
}

/// Cumulative token + cost totals for a session, mirroring
/// `crates/skoga-core/src/protocol.rs::SessionUsage`. `cost_usd` is the
/// sum across `by_model.values()`; tokens are summed across all the
/// per-model buckets. A bucket whose model id isn't in the daemon's
/// price config contributes `0` to cost but its tokens still count
/// toward `tokens_total`.
struct RPCSessionUsage: Decodable, Equatable {
    let tokens_input: UInt64
    let tokens_output: UInt64
    let tokens_cache_creation: UInt64
    let tokens_cache_read: UInt64
    let tokens_total: UInt64
    let cost_usd: Double
    let by_model: [String: RPCModelUsage]
}

struct RPCModelUsage: Decodable, Equatable {
    let tokens_input: UInt64
    let tokens_output: UInt64
    let tokens_cache_creation: UInt64
    let tokens_cache_read: UInt64
    let cost_usd: Double

    /// Sum of all four token buckets — what the by-model telemetry table
    /// renders as "Tokens". Mirrors `SessionUsage.tokens_total` for the
    /// session-level rollup; computed on the Mac side because the daemon
    /// only carries the four buckets per model, not the per-model total.
    var tokens_total: UInt64 {
        tokens_input
            &+ tokens_output
            &+ tokens_cache_creation
            &+ tokens_cache_read
    }
}

enum RPCSessionState: String, Decodable {
    case running
    case conflicted
    case agentExited     = "agent-exited"
    case prOpen          = "pr-open"
    case prMerged        = "pr-merged"
    case prClosed        = "pr-closed"
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

/// Params for `session.list_terminal` — the paginated terminal-state
/// listing that backs the Mac History view (skoga-mac#34). `since`/`until`
/// are ISO8601 strings because `JSONEncoder` has no global date strategy
/// set and the daemon wants RFC3339 timestamps; the coordinator converts
/// at the boundary. `cursor` is opaque to the client and re-fed verbatim
/// for the next page.
struct SessionListTerminalParams: Encodable {
    let limit: Int?
    let cursor: String?
    let since: String?
    let until: String?
}

struct SessionListTerminalResponse: Decodable {
    let sessions: [RPCSession]
    let next_cursor: String?
    let total_estimate: Int?
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
    /// `agents.list` id of the permanent agent this session is
    /// dispatched against, when the user picked one in the Dispatch
    /// grid. The daemon uses this to (a) stamp the session record so
    /// `agents.list` can roll up per-agent telemetry, (b) bump the
    /// agent's `last_used` immediately, and (c) increment `total_runs`
    /// on the session's eventual `.prMerged` / `.done` transition.
    /// `nil` is the existing ephemeral-dispatch path. Older daemons
    /// that don't recognize the field silently drop it (serde
    /// `#[serde(default)]` on the matching Rust struct).
    let named_agent_id: String?
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

struct SessionShipParams: Encodable {
    let id: String
}

struct SessionShipResponse: Decodable {
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

struct SessionInjectFeedbackParams: Encodable {
    let id: String
}

struct SessionInjectFeedbackResponse: Decodable {
    let session: RPCSession
}

// MARK: – spend.today

/// Wire shape of `spend.today` — total cost in USD across ALL sessions
/// started today (running + terminal), aggregated server-side. The
/// per-session `listAgents` path only sees open sessions, so this is
/// what the Cockpit / Budgets / Telemetry surfaces read to avoid
/// spend dropping the moment a session terminates.
struct SpendTodayResponse: Decodable {
    let total_usd: Double
    /// RFC3339 timestamp of when the daemon last rolled the total up.
    /// Decoded but unused today — kept on the wire so a future "as of
    /// 2:36p" caption can read it without a daemon change.
    let as_of: String
}

// MARK: – cockpit.activity

/// Wire shape of `cockpit.activity` (getskoga/skoga#89). The daemon
/// maintains an in-memory ring buffer of the last 30 one-minute buckets,
/// summed across every live session. Each bucket carries a Unix epoch
/// start timestamp and the raw `tokens/min` rate; the renderer
/// (`ActivityBars`) normalizes to the max of the series so the bar
/// scale stays sensible whether the guild is emitting 3k or 3M tok/min.
struct CockpitActivityResponse: Decodable {
    let buckets: [CockpitActivityBucket]
}

struct CockpitActivityBucket: Decodable {
    /// Unix epoch seconds at the start of the minute bucket. Unused by
    /// the current sparkline (the bars are anchored to "last 30m"
    /// implicitly) but kept on the wire so a future hover tooltip can
    /// render the bucket's wall-clock time.
    let start: Int
    let tokens_per_min: Double
}

// MARK: – session.diff_stat

struct SessionDiffStatParams: Encodable {
    let id: String
}

/// Wire shape of `session.diff_stat`'s result envelope
/// (`SessionDiffStatResponse` in skoga-core/protocol.rs). The daemon always
/// returns a populated `diff_stat` — compute failures fall back to a
/// zero-default rather than RPC-erroring — so this wrapper isn't optional.
struct SessionDiffStatResponse: Decodable {
    let diff_stat: RPCDiffStat
}

/// Inner payload from `session.diff_stat` (getskoga/skoga#87 / #110).
/// Counts the session's diff against its base branch, cached on the
/// session record with a 30s TTL on the daemon side. Used by the PR
/// modal to render the real "+N −M" header instead of the old
/// `commits * 18` placeholder.
struct RPCDiffStat: Decodable, Equatable {
    let commits: Int
    let files_changed: Int
    let lines_added: Int
    let lines_removed: Int
}

// MARK: – session.changed_files

struct SessionChangedFilesParams: Encodable {
    let id: String
}

/// Files the agent has touched in this session — committed since base
/// + uncommitted (staged + unstaged) + untracked, deduped and sorted
/// by the daemon. Paths are relative to the worktree root so the Mac
/// can prefix them with the worktree path before handing them to
/// editors. Used by the "Drop into editor" quick action to open the
/// changed files as tabs alongside the worktree root.
struct SessionChangedFilesResponse: Decodable {
    let files: [String]
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

/// Lightweight model of the `events.event` notification payload. Most
/// callers only read `type` + `session_id` and treat the event as a
/// "refetch sessions" trigger. `payload` is decoded as a generic
/// `Decodable` shape so the notifications service can pull the
/// type-specific fields (`headline`, `summary`, `pct`, `silenced`, …)
/// without forcing every event into a discriminated union.
struct RPCEvent: Decodable {
    let type: String
    let session_id: String?
    let payload: RPCEventPayload?

    enum CodingKeys: String, CodingKey {
        case type, session_id, payload
    }
}

/// Type-erased decode of the audit Event's `payload` object. Carries the
/// union of fields any consumer might want — every field is optional
/// because the schema is per-event-type. New event types add new
/// optional fields here without breaking existing decode sites.
struct RPCEventPayload: Decodable {
    // notification.attention_needed
    let headline: String?
    let summary: String?
    // notification.run_finished
    let pr_url: String?
    let repo: String?
    let branch: String?
    // notification.budget_alert
    let period: String?
    let pct: Double?
    let spent_usd: Double?
    let budget_usd: Double?
    // All notification.* events — daemon-side silencing decision.
    let silenced: Bool?
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

// MARK: – models.list

/// One entry in the `models.list` response. Each adapter contributes its
/// own entries daemon-side (Anthropic's `/v1/models` backs the claude
/// adapter; the codex adapter's list is curated). `recommended` is true
/// for at most one entry per adapter — the Mac uses it to seed the
/// Dispatch dropdown's initial selection when the user has no saved
/// preference.
///
/// The wire order is the daemon's responsibility and must be stable; the
/// Mac renders it verbatim. `id` is a synthetic `adapter/model` so
/// SwiftUI's `ForEach` / `Menu` selection stays stable across refetches.
struct RPCModelChoice: Decodable, Hashable, Identifiable {
    let adapter: String
    let model: String
    let label: String
    let recommended: Bool

    var id: String { "\(adapter)/\(model)" }
}

struct ModelsListParams: Encodable {
    /// Filter to a single adapter (e.g. `"claude"`). `nil` returns
    /// every adapter the daemon knows about — what the Dispatch screen
    /// asks for, since the dropdown spans providers.
    let adapter: String?
}

struct ModelsListResponse: Decodable {
    let models: [RPCModelChoice]
}

// MARK: – session.timeline

struct SessionTimelineParams: Encodable {
    let id: String
    /// `nil` is encoded as `"limit": null` by Swift's default
    /// `Encodable` synth; serde's `Option<u32>` natively maps JSON
    /// null to `None`, so the daemon's `#[serde(default)]` falls
    /// through to its 30-entry cap. The Mac never asks for an
    /// explicit number today — the side panel fits ~12 rows at
    /// typical heights, and the daemon-picked default already
    /// absorbs the scroll headroom without forcing a re-walk of
    /// the whole transcript on every 5s poll.
    let limit: UInt32?
}

struct SessionTimelineResponse: Decodable {
    let entries: [RPCTimelineEntry]
}

/// Wire shape of one activity-feed row. The daemon emits `when` as
/// RFC3339 UTC at second resolution (`SecondsFormat::Secs`); the Mac
/// formats it for display at the boundary so the rest of the app
/// continues to see `TimelineEntry.when` as a presentation string
/// (matching the seed shape `MockDaemonClient` uses).
struct RPCTimelineEntry: Decodable {
    let kind: Kind
    let when: String
    let what: String

    enum Kind: String, Decodable {
        case thought, tool, commit, state
    }
}

extension Array where Element == RPCTimelineEntry {
    /// Map a wire response to the domain shape. Allocates a per-tuple
    /// occurrence counter so two entries that collide on
    /// `(kind, raw-when, what)` — possible because the daemon emits
    /// only second-resolution timestamps and a tool can fire twice in
    /// sub-second succession — receive distinct ids. The counter is
    /// deterministic across polls because the daemon's output is
    /// sorted stably by parsed timestamp + kind, so the "first" and
    /// "second" copy keep their slots across refetches.
    func toDomain() -> [TimelineEntry] {
        let sep = "\u{1F}"
        var seen: [String: Int] = [:]
        return map { wire in
            let baseKey = "\(wire.kind.rawValue)\(sep)\(wire.when)\(sep)\(wire.what)"
            let occurrence = seen[baseKey, default: 0]
            seen[baseKey] = occurrence + 1
            let id = occurrence == 0 ? baseKey : "\(baseKey)\(sep)\(occurrence)"
            return TimelineEntry(
                id: id,
                kind: wire.kind.toDomain,
                when: TimelineWhenFormatter.display(rfc3339: wire.when),
                what: wire.what
            )
        }
    }
}

private extension RPCTimelineEntry.Kind {
    var toDomain: TimelineEntry.Kind {
        switch self {
        case .thought: .thought
        case .tool:    .tool
        case .commit:  .commit
        case .state:   .state
        }
    }
}

/// Renders a daemon-supplied RFC3339 UTC timestamp into the short,
/// design-matched label the side-panel feed shows (e.g. "now",
/// "2:36p", "Mon · 1:34p"). Falls back to the raw input when parsing
/// fails so a malformed daemon emission still renders something
/// rather than dropping the row.
///
/// The locale is pinned to `en_US_POSIX` and the calendar to
/// proleptic-Gregorian so every install produces the same label —
/// the activity feed is a fixed-shape design surface, not a
/// locale-aware widget, and `shortTime` is already hard-English
/// ("2:36p"). Without the pin, a French-locale install would render
/// "lun. · 2:36p" — mixed English/French — which reads worse than a
/// fully-English label.
enum TimelineWhenFormatter {
    /// Daemon emits RFC3339 with `Z` and no fractional seconds
    /// (`SecondsFormat::Secs`); tolerate fractional seconds too
    /// because audit timestamps occasionally include them and
    /// ISO8601DateFormatter is strict about which option set you
    /// ask for.
    private static let parsers: [ISO8601DateFormatter] = {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [plain, withFractional]
    }()

    private static let fixedCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    static func display(rfc3339: String, now: Date = Date(), calendar: Calendar? = nil) -> String {
        let cal = calendar ?? fixedCalendar
        guard let date = parsers.lazy.compactMap({ $0.date(from: rfc3339) }).first else {
            return rfc3339
        }
        let delta = now.timeIntervalSince(date)
        if delta >= 0, delta < 60 {
            return "now"
        }
        if cal.isDateInToday(date) {
            return shortTime(date, calendar: cal)
        }
        // "this week" — same week as today. Use a weekday-prefixed form.
        let weekOfYear = cal.component(.weekOfYear, from: date)
        let yearForWeek = cal.component(.yearForWeekOfYear, from: date)
        let nowWeek = cal.component(.weekOfYear, from: now)
        let nowYearForWeek = cal.component(.yearForWeekOfYear, from: now)
        if weekOfYear == nowWeek, yearForWeek == nowYearForWeek {
            let weekday = weekdayFormatter.string(from: date)
            return "\(weekday) · \(shortTime(date, calendar: cal))"
        }
        return "\(monthDayFormatter.string(from: date)) · \(shortTime(date, calendar: cal))"
    }

    /// Match the seed's `2:36p` look — h:mma with a single lowercase
    /// letter and no leading zero. macOS's locale-aware date format
    /// would output `2:36 PM`, which doesn't match the design.
    private static func shortTime(_ date: Date, calendar: Calendar) -> String {
        let hour24 = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let suffix = hour24 < 12 ? "a" : "p"
        let hour12: Int = {
            let h = hour24 % 12
            return h == 0 ? 12 : h
        }()
        return String(format: "%d:%02d%@", hour12, minute, suffix)
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "EEE"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "MMM d"
        return f
    }()
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
