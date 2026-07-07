import Foundation
import Darwin

/// Which transport a `JSONRPCClient` uses to reach skogad.
///
/// The seam that lets a future Mac App Store build force TCP without touching
/// call sites: the Direct build ships `.unixThenTCP`, a sandboxed build would
/// ship `.tcpOnly`.
enum DaemonTransportPolicy {
    /// Direct build: try the native `~/.skoga/sock` Unix socket first (peer-
    /// credential auth, zero prompts), fall back to loopback TCP via the
    /// discovery file if the socket can't be opened.
    case unixThenTCP
    /// Sandboxed / MAS build: the sandbox can't open a Unix socket in `$HOME`,
    /// so go straight to loopback TCP + token auth.
    case tcpOnly
}

/// Parameters for the mandatory first `auth` call on a TCP connection.
/// Mirrors `skoga_core::protocol::AuthParams` — a single `token` field.
struct AuthParams: Encodable {
    let token: String
}

/// Result of a successful `auth` call: `{ "authenticated": true }`. A rejected
/// token comes back as a JSON-RPC error (-32001), not this shape.
struct AuthResult: Decodable {
    let authenticated: Bool
}

/// Parsed `$SKOGA_HOME/daemon-endpoint.json`, the discovery file skogad writes
/// (0600, atomically) on startup when its loopback TCP transport is enabled.
/// Mirrors `skogad::endpoint::DaemonEndpoint`.
///
/// The file is absent when TCP is disabled or the daemon isn't running; that
/// absence is the client's signal that TCP is unavailable. The `token` is a
/// per-run bearer secret — it lives only in this in-memory value and the
/// connection that presents it, and is never logged or persisted.
struct DaemonEndpoint: Decodable {
    /// The `127.0.0.1` TCP port skogad is listening on this run.
    let port: UInt16
    /// Per-run bearer token to present on the connection's `auth` call.
    let token: String
    /// The daemon pid, for a liveness sanity-check before we bother connecting.
    let pid: Int32
    /// Wire-protocol identifier; we only speak the one below.
    let `protocol`: String
    /// Daemon version string (informational).
    let version: String

    /// The one framing dialect this client speaks. Matches
    /// `skogad::endpoint::ENDPOINT_PROTOCOL`.
    static let expectedProtocol = "skoga-jsonrpc/1"

    /// Discovery filename under `$SKOGA_HOME`. Matches
    /// `paths::daemon_endpoint_path()`.
    static let fileName = "daemon-endpoint.json"

    /// Read + parse the discovery file, then sanity-check protocol and pid
    /// liveness. Throws a `JSONRPCError` the connection layer can surface:
    /// `.daemonUnavailable` when the file is missing / the pid is dead,
    /// `.decode` on a malformed file.
    static func resolve(access: SkogaHomeAccess = .shared) throws -> DaemonEndpoint {
        let data: Data
        do {
            data = try access.read(fileName: fileName)
        } catch let e as SkogaHomeAccessError {
            // Folder grant refused — a distinct, actionable failure.
            throw e
        } catch {
            // Missing file (daemon down / TCP disabled) or any other read
            // failure: no reachable TCP endpoint.
            throw JSONRPCError.daemonUnavailable(
                "no daemon endpoint file at ~/.skoga/\(fileName): \(error.localizedDescription)"
            )
        }

        let endpoint: DaemonEndpoint
        do {
            endpoint = try JSONDecoder().decode(DaemonEndpoint.self, from: data)
        } catch {
            throw JSONRPCError.decode("daemon-endpoint.json: \(error)")
        }

        guard endpoint.protocol == expectedProtocol else {
            throw JSONRPCError.daemonUnavailable(
                "daemon speaks protocol \(endpoint.protocol), this client speaks \(expectedProtocol)"
            )
        }
        guard endpoint.isProcessAlive else {
            throw JSONRPCError.daemonUnavailable(
                "daemon endpoint file names pid \(endpoint.pid), which is not running (stale file)"
            )
        }
        return endpoint
    }

    /// Cheap liveness check: `kill(pid, 0)` sends no signal but reports
    /// whether the process exists. `0` → alive; `EPERM` → alive but owned by
    /// another user (treat as alive); `ESRCH` → gone (stale file). If the
    /// check is inconclusive we optimistically report alive and let the
    /// connect attempt be the real test.
    var isProcessAlive: Bool {
        if kill(pid, 0) == 0 { return true }
        return errno != ESRCH
    }
}
