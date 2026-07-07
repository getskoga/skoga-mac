import Foundation
import AppKit

/// Reads files out of `$SKOGA_HOME` (default `~/.skoga`) in a way that works
/// in both the unsandboxed Direct build and a future sandboxed Mac App Store
/// build.
///
/// - Unsandboxed (today): the app has plain filesystem access to the user's
///   home, so `Data(contentsOf:)` on `~/.skoga/daemon-endpoint.json` just
///   works and this type never prompts.
/// - Sandboxed (MAS): the sandbox denies direct reads of `~/.skoga`. The
///   first denied read triggers a one-time `NSOpenPanel` asking the user to
///   grant the `~/.skoga` folder; we persist a **security-scoped bookmark**
///   for the folder (not the file) in `UserDefaults` and resolve +
///   `startAccessingSecurityScopedResource()` it on later launches so we
///   never prompt again.
///
/// Only the *folder grant* is persisted. The daemon's per-run bearer token
/// (read out of the endpoint file) is never written here or anywhere else —
/// it lives only in the in-memory connection.
final class SkogaHomeAccess: @unchecked Sendable {
    static let shared = SkogaHomeAccess()

    /// `UserDefaults` key holding the security-scoped bookmark for `~/.skoga`.
    /// Bookmark data only — no token, no file contents.
    private static let bookmarkKey = "dev.getskoga.Skoga.skogaHomeBookmark"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The `$SKOGA_HOME` directory, honoring the env override exactly like
    /// `paths::skoga_home()` in skoga-core so a test or dev override moves the
    /// daemon and the app together. Single source of truth for this resolution:
    /// `URL.skogaSocket` derives the socket path from it, so the env-override
    /// semantics never drift between the two sites.
    static var skogaHomeURL: URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["SKOGA_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".skoga")
    }

    /// Read a file living directly under `$SKOGA_HOME`. Tries a direct read
    /// first (the unsandboxed happy path — never prompts); only on a
    /// *permission* denial does it fall back to the security-scoped bookmark
    /// flow, prompting once if no grant has been stored yet.
    ///
    /// A genuinely-missing file (daemon not running / TCP disabled) surfaces
    /// the underlying `NSFileReadNoSuchFileError` unchanged — the caller
    /// treats that as "no endpoint", distinct from "access denied".
    func read(fileName: String) throws -> Data {
        let fileURL = Self.skogaHomeURL.appendingPathComponent(fileName)
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            guard Self.isPermissionError(error) else { throw error }
            return try readViaBookmark(fileName: fileName)
        }
    }

    // MARK: – Security-scoped bookmark flow (sandboxed builds)

    private func readViaBookmark(fileName: String) throws -> Data {
        let folderURL = try resolveOrRequestFolder()
        let scoped = folderURL.startAccessingSecurityScopedResource()
        defer { if scoped { folderURL.stopAccessingSecurityScopedResource() } }
        let fileURL = folderURL.appendingPathComponent(fileName)
        return try Data(contentsOf: fileURL)
    }

    /// Resolve the stored `~/.skoga` bookmark, or prompt for it once and
    /// persist it. Re-prompts (and re-persists) if the stored bookmark has
    /// gone stale.
    private func resolveOrRequestFolder() throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        if let data = defaults.data(forKey: Self.bookmarkKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if !isStale { return url }
                // Stale (e.g. the folder moved) — refresh the grant below.
            }
        }
        return try requestFolderGrant()
    }

    /// Present the one-time open panel asking the user to grant `~/.skoga`,
    /// then mint and persist a security-scoped bookmark for it.
    private func requestFolderGrant() throws -> URL {
        let home = Self.skogaHomeURL
        let folderURL = try Self.runOnMain { () throws -> URL in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = false
            panel.directoryURL = home
            panel.prompt = "Grant Access"
            panel.message = "Skoga needs read access to your \(home.path) folder to connect to the local daemon."
            guard panel.runModal() == .OK, let url = panel.url else {
                throw SkogaHomeAccessError.accessDenied
            }
            // `directoryURL` is only a starting hint — the panel lets the user
            // navigate anywhere and pick a different folder. Persisting a
            // bookmark for the wrong directory would silently redirect every
            // later read, surfacing as a confusing `daemonUnavailable` instead
            // of "you granted the wrong folder". Reject a mismatch up front with
            // an actionable error rather than banking a useless grant.
            guard Self.sameDirectory(url, home) else {
                throw SkogaHomeAccessError.wrongFolderSelected(
                    expected: home.path, selected: url.path
                )
            }
            return url
        }
        let bookmark = try folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: Self.bookmarkKey)
        return folderURL
    }

    // MARK: – Helpers

    /// A permission denial on a read — the sandbox signal to fall back to the
    /// bookmark flow. Distinct from a missing file, which is a legitimate
    /// "no endpoint" answer we must not swallow.
    private static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoPermissionError
    }

    /// Whether two URLs name the same directory. Compares symlink- and
    /// `.`/`..`-normalized paths so the macOS `/Users` → `/System/Volumes/Data/
    /// Users` firmlink alias (which the open panel routinely returns) still
    /// matches the resolved `$SKOGA_HOME`, avoiding a false rejection.
    private static func sameDirectory(_ a: URL, _ b: URL) -> Bool {
        a.resolvingSymlinksInPath().standardizedFileURL.path
            == b.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func runOnMain<T>(_ body: @escaping () throws -> T) throws -> T {
        if Thread.isMainThread { return try body() }
        var result: Result<T, Error>!
        DispatchQueue.main.sync { result = Result { try body() } }
        return try result.get()
    }
}

enum SkogaHomeAccessError: Error, LocalizedError {
    case accessDenied
    /// The open panel returned a folder other than `$SKOGA_HOME`, so the grant
    /// was rejected instead of being persisted against the wrong directory.
    case wrongFolderSelected(expected: String, selected: String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Access to the ~/.skoga folder was not granted, so the app can't reach the local daemon over TCP."
        case let .wrongFolderSelected(expected, selected):
            "Skoga needs access to \(expected), but \(selected) was selected. Re-open the grant prompt and choose the \(expected) folder."
        }
    }
}
