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

    /// Push notification stream from `events.subscribe`. Implementations that
    /// can't subscribe (mock, offline) return an empty stream that completes
    /// immediately so consumers fall back to polling.
    nonisolated func events() -> AsyncStream<RPCEvent>
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
