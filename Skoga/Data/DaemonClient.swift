import Foundation

/// The protocol the SwiftUI app talks through. `LiveDaemonClient` speaks
/// JSON-RPC 2.0 over `~/.skoga/sock`; `MockDaemonClient` carries the design's
/// seed data for previews and for running the app without skogad installed.
@MainActor
protocol DaemonClient: AnyObject {
    func listAgents() async throws -> [Agent]
    func conversation(for agentId: String) async throws -> [ConversationMessage]
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
    /// screen.
    func createSession(task: String, agent: String, base: String, repoRoot: URL, initialPrompt: String?) async throws -> Agent

    /// Tear a session down (`session.kill`). Worktree removal happens
    /// asynchronously; subscribers see the `session.killed` event when done.
    func killSession(id: String) async throws

    /// Push a follow-up user message to a running agent (`session.send_input`).
    /// The daemon pastes `text` into the agent's tmux pane via bracketed
    /// paste — multi-line input arrives at Claude as one paste event. Throws
    /// when the session is unknown, mid-teardown, or the agent's tmux pane
    /// is gone (process crashed / never launched).
    func sendInput(sessionId: String, text: String) async throws

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
