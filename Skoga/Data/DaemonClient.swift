import Foundation

/// The protocol the SwiftUI app talks through. A real implementation will speak
/// JSON-RPC 2.0 over `~/.skoga/sock` (Unix domain socket) per the skoga architecture doc.
/// For now `MockDaemonClient` carries the design's seed data.
@MainActor
protocol DaemonClient: AnyObject {
    func listAgents() async throws -> [Agent]
    func conversation(for agentId: String) async throws -> [ConversationMessage]
    func activitySeries() async throws -> [Double]
    func timeline(for agentId: String) async throws -> [TimelineEntry]
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
