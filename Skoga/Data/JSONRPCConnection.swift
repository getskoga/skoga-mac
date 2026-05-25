import Foundation
import Darwin

/// One-shot JSON-RPC client over a Unix domain socket. Each `call` opens a
/// fresh connection, sends a line-delimited request, reads one line back, and
/// closes. Trading a few-ms-per-call for a vastly simpler concurrency model —
/// no shared mutable id counter, no response-id dispatch table, no half-open
/// recovery. Matches what a UI app needs (low call rate, easy cancellation).
///
/// `EventStream` does keep a persistent connection — see below.
///
/// Why raw `Darwin.socket()` instead of `NWConnection`: NWConnection's Unix
/// transport on macOS wraps the fd so the server's `getpeereid()` returns
/// `ENOTCONN`, which trips skogad's same-uid peer-credential check and gets
/// every RPC rejected at handshake. A plain `SOCK_STREAM` Unix socket via
/// `connect(2)` behaves correctly — and NWConnection's DNS/TLS/path-monitoring
/// features aren't useful for a local UDS anyway.
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
        let line = try Self.encodeRequest(method: method, params: params, id: 1)
        let path = socketPath.path
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<R, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let socket = try UnixSocket.connect(path: path)
                    defer { socket.close() }
                    try socket.writeAll(line)
                    let response = try socket.readLine()
                    let result: R = try Self.decode(response, type: R.self)
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Open a persistent connection, issue `session.attach_stream`, await
    /// the handshake response (which carries the initial pane snapshot),
    /// and return an `AsyncStream` that yields raw PTY bytes for every
    /// `session.pty_data` notification the daemon pushes afterward.
    ///
    /// The stream owns the socket for the duration of its consumer's
    /// lifetime — on `onTermination` the socket is closed, the daemon
    /// drops this connection's subscription, and the FIFO + pipe-pane
    /// stay up only if other clients are subscribed.
    ///
    /// Throws synchronously if the handshake fails (socket missing,
    /// session unknown, snapshot decode failure). Once `bytes` is
    /// streaming, transport errors silently terminate the stream — the
    /// view can observe the finish and decide whether to retry.
    func openPTYStream(sessionId: String, cols: UInt16?, rows: UInt16?) async throws -> AttachedPTYStream {
        if !FileManager.default.fileExists(atPath: socketPath.path) {
            throw JSONRPCError.socketMissing(socketPath)
        }
        let params = SessionAttachStreamParams(id: sessionId, cols: cols, rows: rows)
        let req = try Self.encodeRequest(method: "session.attach_stream", params: AnyEncodable(params), id: 1)
        let path = socketPath.path

        // Phase 1: blocking handshake on a worker, bridged to async.
        let (snapshot, session, socket) = try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<(Data, RPCSession, UnixSocket), Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let s = try UnixSocket.connect(path: path)
                    do {
                        try s.writeAll(req)
                        let response = try s.readLine()
                        let decoded: SessionAttachStreamResponse = try Self.decode(
                            response, type: SessionAttachStreamResponse.self
                        )
                        guard let snapshotData = Data(base64Encoded: decoded.snapshot_b64) else {
                            s.close()
                            cont.resume(throwing: JSONRPCError.decode("snapshot_b64 was not valid base64"))
                            return
                        }
                        cont.resume(returning: (snapshotData, decoded.session, s))
                    } catch {
                        s.close()
                        cont.resume(throwing: error)
                    }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }

        // Phase 2: long-lived notification reader.
        // Hold the socket in a class so the read-loop and the onTermination
        // closure both reach it; closing from termination unblocks read(2)
        // with EBADF.
        final class SocketHolder: @unchecked Sendable {
            var socket: UnixSocket?
        }
        let holder = SocketHolder()
        holder.socket = socket

        let bytes = AsyncStream<Data> { continuation in
            let queue = DispatchQueue(
                label: "dev.getskoga.Skoga.PTYStream.\(sessionId)",
                qos: .userInitiated
            )
            queue.async {
                while true {
                    let line: Data
                    do {
                        line = try socket.readLine()
                    } catch {
                        break
                    }
                    if line.isEmpty { continue }
                    if let payload: RPCPtyDataNotification = try? Self.decodePtyData(line) {
                        if let data = Data(base64Encoded: payload.bytes_b64) {
                            continuation.yield(data)
                        }
                    }
                }
                socket.close()
                continuation.finish()
            }
            continuation.onTermination = { _ in
                holder.socket?.close()
            }
        }

        return AttachedPTYStream(snapshot: snapshot, session: session, bytes: bytes)
    }

    /// Open a persistent connection, issue `events.subscribe`, and return an
    /// `AsyncStream` that yields one `RPCEvent` per pushed notification. The
    /// stream ends when the daemon closes the socket or the caller cancels
    /// the consuming Task.
    func eventStream() -> AsyncStream<RPCEvent> {
        let path = socketPath.path
        return AsyncStream { continuation in
            // Hold the socket in a class so the read-loop closure and the
            // `onTermination` closure can both reach it. Closing the fd from
            // termination unblocks `read(2)` on the worker thread with EBADF.
            final class SocketHolder: @unchecked Sendable {
                var socket: UnixSocket?
            }
            let holder = SocketHolder()
            let queue = DispatchQueue(label: "dev.getskoga.Skoga.JSONRPCEventStream", qos: .userInitiated)
            queue.async {
                do {
                    let socket = try UnixSocket.connect(path: path)
                    holder.socket = socket
                    let req = try Self.encodeRequest(method: "events.subscribe", params: nil, id: 1)
                    try socket.writeAll(req)
                    // Drain the subscribe ack (the first line back) before
                    // entering the notification loop. Subsequent lines are
                    // `events.event` frames.
                    _ = try? socket.readLine()
                    while true {
                        let line: Data
                        do {
                            line = try socket.readLine()
                        } catch {
                            break
                        }
                        if let event: RPCEvent = try? Self.decodeNotification(line) {
                            continuation.yield(event)
                        }
                    }
                    socket.close()
                } catch {
                    // Connection setup failed — terminate the stream so the
                    // consumer can fall back to polling / show the banner.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                holder.socket?.close()
            }
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

    static func decodePtyData(_ data: Data) throws -> RPCPtyDataNotification {
        let decoder = makeDecoder()
        let envelope = try decoder.decode(RPCNotification<RPCPtyDataNotification>.self, from: data)
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
}

// MARK: – Raw Unix socket

/// Thin wrapper around a `SOCK_STREAM` Unix-domain fd. Blocking I/O on the
/// caller's thread — callers schedule work on a `DispatchQueue` worker and
/// bridge to async via `withCheckedThrowingContinuation`.
private final class UnixSocket: @unchecked Sendable {
    private var fd: Int32
    private var readBuffer = Data()
    private let closeLock = NSLock()
    private var didClose = false

    private init(fd: Int32) { self.fd = fd }

    static func connect(path: String) throws -> UnixSocket {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            throw JSONRPCError.connectFailed("socket: \(errnoMessage())")
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        // sun_len exists on macOS (BSD-derived) but is harmless to set; leave
        // `connect(2)` to use the explicit length argument either way.
        let pathBytes = Array(path.utf8)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1 // 103 on macOS
        if pathBytes.count > maxLen {
            Darwin.close(fd)
            throw JSONRPCError.connectFailed("socket path too long: \(pathBytes.count) > \(maxLen)")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            sunPathPtr.withMemoryRebound(to: UInt8.self, capacity: maxLen + 1) { dst in
                for (i, byte) in pathBytes.enumerated() {
                    dst[i] = byte
                }
                dst[pathBytes.count] = 0
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, len)
            }
        }
        if rc < 0 {
            let msg = errnoMessage()
            Darwin.close(fd)
            throw JSONRPCError.connectFailed("connect: \(msg)")
        }
        return UnixSocket(fd: fd)
    }

    func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            guard let base = buf.baseAddress else { return }
            var offset = 0
            let total = buf.count
            while offset < total {
                let n = Darwin.write(fd, base.advanced(by: offset), total - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw JSONRPCError.sendFailed(UnixSocket.errnoMessage())
                }
                if n == 0 {
                    throw JSONRPCError.sendFailed("write returned 0")
                }
                offset += n
            }
        }
    }

    /// Read until `\n`. Buffers leftover bytes across calls so the event
    /// stream can receive multiple frames on one connection.
    func readLine() throws -> Data {
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            if let nlIdx = readBuffer.firstIndex(of: 0x0a) {
                let line = readBuffer.subdata(in: readBuffer.startIndex..<nlIdx)
                readBuffer.removeSubrange(readBuffer.startIndex...nlIdx)
                return line
            }
            let n = chunk.withUnsafeMutableBufferPointer { ptr -> Int in
                guard let base = ptr.baseAddress else { return 0 }
                return Darwin.read(fd, base, ptr.count)
            }
            if n < 0 {
                if errno == EINTR { continue }
                throw JSONRPCError.readFailed(UnixSocket.errnoMessage())
            }
            if n == 0 {
                if readBuffer.isEmpty {
                    throw JSONRPCError.emptyResponse
                }
                // Peer closed mid-line — surface whatever arrived so a
                // partial frame shows up in diagnostics instead of vanishing.
                let line = readBuffer
                readBuffer.removeAll(keepingCapacity: false)
                return line
            }
            chunk.withUnsafeBufferPointer { ptr in
                if let base = ptr.baseAddress {
                    readBuffer.append(base, count: n)
                }
            }
        }
    }

    func close() {
        closeLock.lock(); defer { closeLock.unlock() }
        if !didClose {
            _ = Darwin.close(fd)
            didClose = true
        }
    }

    deinit {
        close()
    }

    private static func errnoMessage() -> String {
        String(cString: strerror(errno))
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
