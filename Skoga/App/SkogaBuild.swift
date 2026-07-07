import Foundation

/// Distribution-channel flags. The Mac App Store build runs under App
/// Sandbox and must stay a pure daemon client — no local subprocesses.
/// The Direct (non-MAS) build ships without the sandbox and can therefore
/// re-enable the affordances that need to spawn a process (custom editor
/// shell commands; external-terminal / reattach flows that relaunch an
/// agent via the CLI).
///
/// `isDirectBuild` is the single switch those affordances gate on. It's
/// driven by the `SKOGA_DIRECT_BUILD` active-compilation-condition (add it
/// to the Direct scheme in `project.yml`) with an env-var escape hatch
/// (`SKOGA_DIRECT_BUILD=1`) for local runs of the sandbox-free build. The
/// default — no condition, no env — is the sandboxed App Store behavior.
enum SkogaBuild {
    static let isDirectBuild: Bool = {
        #if SKOGA_DIRECT_BUILD
        return true
        #else
        return ProcessInfo.processInfo.environment["SKOGA_DIRECT_BUILD"] == "1"
        #endif
    }()
}
