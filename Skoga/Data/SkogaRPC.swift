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
    let created_at: Date
    let state: RPCSessionState
    let landed_pr_url: String?
    let waiting_since: Date?
    let idle_since: Date?
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
