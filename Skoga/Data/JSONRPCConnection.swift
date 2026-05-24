import Foundation
import Network

/// One-shot JSON-RPC client over a Unix domain socket. Each `call` opens a
/// fresh connection, sends a line-delimited request, reads one line back, and
/// closes. Trading a few-ms-per-call for a vastly simpler concurrency model —
/// no shared mutable id counter, no response-id dispatch table, no half-open
/// recovery. Matches what a UI app needs (low call rate, easy cancellation).
///
/// `EventStream` does keep a persistent connection — see below.
enum JSONRPCError: Error, LocalizedError {
    case socketMissing(URL)
    case connectFailed(String)
    case sendFailed(String)
    case readFailed(String)
    case emptyResponse
    case decode(String)
    case rpc(RPCError)

    var errorDescription: String? {
        switch self {
        case .socketMissing(let url):     "Daemon socket missing at \(url.path)"
        case .connectFailed(let m):       "Connect failed: \(m)"
        case .sendFailed(let m):          "Send failed: \(m)"
        case .readFailed(let m):          "Read failed: \(m)"
        case .emptyResponse:              "Daemon closed the connection without responding"
        case .decode(let m):              "Decode failed: \(m)"
        case .rpc(let e):                 "Daemon error \(e.code): \(e.message)"
        }
    }
}

struct JSONRPCClient {
    let socketPath: URL

    /// Issue one RPC. Throws on transport failure or RPC-level error.
    func call<R: Decodable>(_ method: String, params: AnyEncodable? = nil, decoding: R.Type = R.self) async throws -> R {
        if !FileManager.default.fileExists(atPath: socketPath.path) {
            throw JSONRPCError.socketMissing(socketPath)
        }
        let conn = NWConnection(to: .unix(path: socketPath.path), using: .tcp)
        let line = try Self.encodeRequest(method: method, params: params, id: 1)
        try await Self.start(conn)
        defer { conn.cancel() }
        try await Self.send(conn, line: line)
        let response = try await Self.readLine(conn)
        return try Self.decode(response, type: R.self)
    }

    /// Open a persistent connection, issue `events.subscribe`, and return an
    /// `AsyncStream` that yields one `RPCEvent` per pushed notification. The
    /// stream ends when the daemon closes the socket or the caller cancels
    /// the consuming Task.
    func eventStream() -> AsyncStream<RPCEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let conn = NWConnection(to: .unix(path: socketPath.path), using: .tcp)
                    try await Self.start(conn)
                    let req = try Self.encodeRequest(method: "events.subscribe", params: nil, id: 1)
                    try await Self.send(conn, line: req)
                    // Drain the subscribe ack (the first line back) before
                    // entering the notification loop. Subsequent lines are
                    // `events.event` frames.
                    _ = try? await Self.readLine(conn)
                    while !Task.isCancelled {
                        let line: Data
                        do {
                            line = try await Self.readLine(conn)
                        } catch {
                            break
                        }
                        if let event: RPCEvent = try? Self.decodeNotification(line) {
                            continuation.yield(event)
                        }
                    }
                    conn.cancel()
                } catch {
                    // Connection setup failed — terminate the stream so the
                    // consumer can fall back to polling / show the banner.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: – Encoding / decoding

    static func encodeRequest(method: String, params: AnyEncodable?, id: Int) throws -> Data {
        let req = RPCRequest(method: method, params: params, id: id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        var data = try encoder.encode(req)
        data.append(0x0a) // \n
        return data
    }

    static func decode<R: Decodable>(_ data: Data, type: R.Type) throws -> R {
        let decoder = makeDecoder()
        let envelope: RPCResponse<R>
        do {
            envelope = try decoder.decode(RPCResponse<R>.self, from: data)
        } catch {
            throw JSONRPCError.decode("\(error)")
        }
        if let err = envelope.error { throw JSONRPCError.rpc(err) }
        guard let result = envelope.result else {
            throw JSONRPCError.decode("response missing both result and error")
        }
        return result
    }

    static func decodeNotification(_ data: Data) throws -> RPCEvent {
        let decoder = makeDecoder()
        let envelope = try decoder.decode(RPCNotification<RPCEvent>.self, from: data)
        return envelope.params
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        // skogad uses chrono's default serialization: RFC3339 with fractional
        // seconds (`2026-05-24T18:42:11.123456Z`). The built-in `.iso8601`
        // strategy rejects fractional seconds, so use a formatter that accepts
        // both, then fall through to plain ISO8601 for `daemon.version`-shaped
        // values that don't carry microseconds.
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let str = try decoder.singleValueContainer().decode(String.self)
            if let date = withFractional.date(from: str) { return date }
            if let date = plain.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "expected RFC3339 timestamp, got \(str)"
            )
        }
        return d
    }

    // MARK: – NWConnection async wrappers

    static func start(_ conn: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // `stateUpdateHandler` may fire more than once (.ready, then .failed
            // on disconnect). `resumed` flips on the first terminal state so we
            // don't resume the same continuation twice — that's a runtime crash.
            var resumed = false
            conn.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    cont.resume()
                case .failed(let err):
                    resumed = true
                    cont.resume(throwing: JSONRPCError.connectFailed("\(err)"))
                case .cancelled:
                    resumed = true
                    cont.resume(throwing: JSONRPCError.connectFailed("cancelled before ready"))
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    static func send(_ conn: NWConnection, line: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: line, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: JSONRPCError.sendFailed("\(error)"))
                } else {
                    cont.resume()
                }
            })
        }
    }

    /// Read until `\n`. Buffers across multiple receive callbacks because
    /// NWConnection doesn't promise framing — a single response may arrive
    /// across two `receive` deliveries, or two responses in one.
    static func readLine(_ conn: NWConnection) async throws -> Data {
        actor LineBuffer {
            var data = Data()
            func append(_ chunk: Data) -> Data? {
                data.append(chunk)
                if let nl = data.firstIndex(of: 0x0a) {
                    let line = data.subdata(in: 0..<nl)
                    data.removeSubrange(0...nl)
                    return line
                }
                return nil
            }
        }
        let buffer = LineBuffer()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            var resumed = false
            func receiveOne() {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                    if resumed { return }
                    if let error {
                        resumed = true
                        cont.resume(throwing: JSONRPCError.readFailed("\(error)"))
                        return
                    }
                    Task {
                        if let chunk = data, !chunk.isEmpty {
                            if let line = await buffer.append(chunk) {
                                if !resumed {
                                    resumed = true
                                    cont.resume(returning: line)
                                }
                                return
                            }
                        }
                        if isComplete {
                            if !resumed {
                                resumed = true
                                cont.resume(throwing: JSONRPCError.emptyResponse)
                            }
                            return
                        }
                        receiveOne()
                    }
                }
            }
            receiveOne()
        }
    }
}

extension URL {
    /// `~/.skoga/sock`, honoring `SKOGA_HOME`. Mirrors `paths::socket_path()`
    /// in skoga-core so an env override moves both sides together.
    static var skogaSocket: URL {
        let env = ProcessInfo.processInfo.environment
        let home: URL
        if let override = env["SKOGA_HOME"], !override.isEmpty {
            home = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".skoga")
        }
        return home.appendingPathComponent("sock")
    }
}
