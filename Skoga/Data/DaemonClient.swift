import Foundation

/// The protocol the SwiftUI app talks through. `LiveDaemonClient` speaks
/// JSON-RPC 2.0 over `~/.skoga/sock`; `MockDaemonClient` carries the design's
/// seed data for previews and for running the app without skogad installed.
@MainActor
protocol DaemonClient: AnyObject {
    /// `nonisolated` so the full JSON decode + RPCSession→Agent transform
    /// runs on the global cooperative executor, not MainActor. The roster
    /// is re-fetched every 5s and on every events.event notification; for
    /// a manager juggling 20+ agents, keeping the decode off main avoids
    /// stealing frames from typing in the dispatch form or scrolling the
    /// open conversation.
    nonisolated func listAgents() async throws -> [Agent]
    /// `nonisolated` for the same reason as [`listAgents`], with sharper
    /// stakes: `session.conversation` returns the full transcript
    /// reconstructed from Claude's append-only JSONL, which for a
    /// long-running agent runs hundreds of messages with embedded tool-use
    /// payloads. Decoding that on main during the 5s poll produces
    /// perceptible hitches in the conversation view; running the whole
    /// pipeline (JSONDecoder + RPCConversationMessage→domain transform)
    /// off main keeps scroll and animations smooth.
    nonisolated func conversation(for agentId: String) async throws -> [ConversationMessage]
    func activitySeries() async throws -> [Double]
    func timeline(for agentId: String) async throws -> [TimelineEntry]

    /// Returns the daemon's reported version (`daemon.version`). Used at
    /// bootstrap to gate against an installed-but-too-old skogad.
    func daemonVersion() async throws -> String

    /// Start a new skoga session. `agent` is the adapter name (e.g. `"claude"`);
    /// `base` is the branch to fork from (typically `"main"`); `repoRoot` is
    /// the absolute path to the host clone. `initialPrompt`, when non-empty,
    /// is handed to the agent as its first message so the conversation
    /// populates immediately rather than landing on Claude's empty welcome
    /// screen. `model`, when non-nil, pins the adapter's CLI model flag
    /// (e.g. `claude --model claude-opus-4-7`) and is persisted on the
    /// session record so re-launches keep using it.
    func createSession(task: String, agent: String, model: String?, base: String, repoRoot: URL, initialPrompt: String?) async throws -> Agent

    /// Tear a session down (`session.kill`). Worktree removal happens
    /// asynchronously; subscribers see the `session.killed` event when done.
    func killSession(id: String) async throws

    /// Push a follow-up user message to a running agent (`session.send_input`).
    /// The daemon pastes `text` into the agent's tmux pane via bracketed
    /// paste — multi-line input arrives at Claude as one paste event. Throws
    /// when the session is unknown, mid-teardown, or the agent's tmux pane
    /// is gone (process crashed / never launched).
    func sendInput(sessionId: String, text: String) async throws

    /// Hand a `.conflicted` session off to its agent
    /// (`session.resolve_rebase_conflict`). The daemon reads the conflicted
    /// file list off the worktree, builds the same fix-up prompt
    /// `skoga land` uses today, and pastes it into the agent's tmux pane.
    /// Sets `rebase_prompt_dispatched_at` so the Mac's button switches
    /// to "Prompt sent" until the conflict resolves. Throws when the
    /// session isn't actually conflicted, when the agent's tmux pane
    /// is gone, or on transport / `METHOD_NOT_FOUND` against an older
    /// daemon.
    func resolveRebaseConflict(sessionId: String) async throws

    /// Fetch the session's in-flight `AskUserQuestion`, if any. Returns nil
    /// when the agent has no pending picker. Used as a polled fallback for
    /// older daemons that don't yet include `pending_question` on
    /// `RPCSession`.
    func pendingQuestion(for agentId: String) async throws -> RPCPendingQuestion?

    /// Deliver the user's selection back to the agent. `selectedIndices`
    /// are zero-based into the pending question's options. Daemon
    /// translates this into tmux key strokes that drive Claude's picker.
    /// Single-select expects a one-element array; multi-select the full
    /// chosen set.
    func answerQuestion(sessionId: String, selectedIndices: [Int]) async throws

    /// Push notification stream from `events.subscribe`. Implementations that
    /// can't subscribe (mock, offline) return an empty stream that completes
    /// immediately so consumers fall back to polling.
    nonisolated func events() -> AsyncStream<RPCEvent>

    /// Open a remote PTY stream for the agent's tmux pane. The returned
    /// `AttachedPTYStream` carries the initial pane snapshot (feed it into
    /// the terminal renderer first) and an `AsyncStream` of subsequent
    /// raw byte chunks. The Mac app uses this in place of `tmux attach`
    /// so SwiftTerm sees a real byte stream and can own scrollback /
    /// selection / copy in native Mac fashion.
    ///
    /// `cols` / `rows` set the initial pane dimensions when present. Pass
    /// the current SwiftTerm view's geometry on first attach; the daemon
    /// translates them into a tmux `resize-window` before snapshotting.
    func openPTYStream(sessionId: String, cols: UInt16?, rows: UInt16?) async throws -> AttachedPTYStream

    /// Forward raw input bytes to the agent's tmux pane (`session.pty_write`).
    /// Bytes are arbitrary — keystrokes, escape sequences, control codes;
    /// the daemon ships them via `tmux send-keys -H` to preserve binary
    /// content. For multi-line prompt text use `sendInput` instead, which
    /// uses bracketed paste so the TUI sees it as one paste event.
    func ptyWrite(sessionId: String, bytes: Data) async throws

    /// Push a SwiftTerm view-size change down to the agent's tmux pane so
    /// the TUI re-lays out. Cheap — issue per resize event.
    func ptyResize(sessionId: String, cols: UInt16, rows: UInt16) async throws

    /// Ask the CLI what title + body it would use for this session's PR if
    /// `skoga land` ran right now. Used to pre-fill the PR modal so the user
    /// edits real defaults instead of placeholder text. Shells out to
    /// `skoga land <id> --preview`, which is read-only — no git, no daemon
    /// writes, no audit emission.
    func previewPR(for sessionId: String) async throws -> PRPreview

    /// Drive a full `skoga land <id> --title ... --body ... --yes` flow:
    /// squash, rebase, push, open PR via `gh`. The Mac app deliberately
    /// shells out to the CLI rather than reimplementing the flow in Swift —
    /// the architecture explicitly keeps git/gh side effects in the CLI
    /// process (it inherits the dev's TTY, credentials, and gh auth).
    /// Throws on any pre-flight failure (no commits, conflicts) or push/PR
    /// failure. On success the session's `landed_pr_url` is set by the
    /// daemon; callers refresh to see it.
    func landPR(for sessionId: String, title: String, body: String) async throws

    /// Current `gh` CLI state from the daemon's perspective — install,
    /// auth, login handle, scopes, and the persisted default reviewer.
    /// Polled by Settings → GitHub during sign-in to detect when the
    /// user's terminal `gh auth login` completes. Throws on transport
    /// failure; the Settings view distinguishes that from a clean
    /// "not installed" reply (where the call returns and `installed`
    /// is false).
    func githubStatus() async throws -> RPCGitHubStatus

    /// Persist the default reviewer the PR modal pre-fills (`@username`
    /// or `org/team`). Returns the updated `RPCGitHubStatus` so the
    /// caller can update local state without a second round-trip. Pass
    /// an empty string to clear.
    @discardableResult
    func githubSetDefaultReviewer(_ reviewer: String) async throws -> RPCGitHubStatus

    /// Per-provider Keychain credential presence and last-used metadata
    /// (`credentials.list`). The raw key never crosses the wire on
    /// reads — only `has_key` and an ISO-8601 `last_used` timestamp.
    /// Used by Settings → Models & keys to render the per-row status
    /// chips. Throws on transport / `METHOD_NOT_FOUND`; the Settings
    /// view surfaces the latter as a "daemon too old" row, matching
    /// the GitHub section's pattern.
    func credentialsList() async throws -> [RPCCredentialEntry]

    /// Persist an API key for `provider` to the user's login Keychain
    /// (`credentials.set`). The daemon trims and rejects empty values
    /// — callers should treat blank input as "use `credentialsDelete`".
    /// Returns the updated entry so the caller can refresh its row
    /// without a second `credentialsList` round-trip.
    @discardableResult
    func credentialsSet(provider: RPCCredentialProvider, key: String) async throws -> RPCCredentialEntry

    /// Remove the Keychain entry for `provider` (`credentials.delete`).
    /// Idempotent — returns `true` if a key existed and was removed,
    /// `false` if there was nothing to delete. Both shapes mean the
    /// provider is now configured-as-empty.
    @discardableResult
    func credentialsDelete(provider: RPCCredentialProvider) async throws -> Bool

    /// Probe `provider`'s API with the configured key
    /// (`credentials.test`). Per the daemon contract this never throws
    /// at the RPC layer — every failure mode (no key, 401, network)
    /// collapses to `ok: false` + a human-readable `message`. Swift
    /// callers should treat thrown errors as transport failures, not
    /// auth failures.
    func credentialsTest(provider: RPCCredentialProvider) async throws -> RPCCredentialsTestResult
}

/// CLI-derived PR title + body used to pre-fill the PR modal. Mirrors the
/// stdout shape of `skoga land --preview` (`{session_id, title, body}`).
struct PRPreview: Equatable {
    let title: String
    let body: String
}

/// Whether the app has a live connection to skogad. Drives the banner shown
/// at the top of `MainWindow` when something needs the user's attention.
enum DaemonStatus: Equatable {
    case connecting
    case connected(version: String)
    /// Connection refused / socket missing — daemon binary likely installed
    /// but not running. Hint: `skoga daemon start`.
    case notRunning(detail: String)
    /// Running in mock mode (env override) — used for design previews so the
    /// banner reflects "this isn't real data" instead of "skoga is broken".
    case mock
}

struct TimelineEntry: Hashable, Identifiable {
    enum Kind: String { case thought, tool, commit }
    let id = UUID()
    let kind: Kind
    let when: String
    /// Plain-text variant; tool and commit entries embed `code` spans, surfaced
    /// in the UI by wrapping backtick-delimited segments in a monospace tile.
    let what: String
}
