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
