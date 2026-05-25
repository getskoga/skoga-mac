import AppKit
import SwiftTerm
import SwiftUI

/// Renders a skoga session's tmux pane directly. Spawns a child PTY running
/// `tmux attach -t skoga-<sessionId>` inside a `LocalProcessTerminalView`,
/// which gives the user the same view they'd see from `skoga attach <id>`
/// in a terminal — including the agent's full TUI (Claude Code, etc.).
///
/// The PTY's lifetime is tied to the NSView's lifetime. Apply `.id(sessionId)`
/// at the call site so SwiftUI rebuilds the view (and therefore the PTY child)
/// when the user switches sessions — `updateNSView` is a deliberate no-op.
struct TerminalPaneView: NSViewRepresentable {
    let sessionId: String

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        let target = "skoga-\(sessionId)"
        // Enable mouse-wheel scroll + drag-select before attaching. Scoped
        // to this session (not `-g`) so we don't flip the option on for any
        // other tmux sessions sharing the default socket. The `;` is a
        // tmux command separator (passed as its own argv element so tmux's
        // parser sees it, not the shell). Without this, tmux blocks the
        // mouse and the pane is effectively unscrollable from SwiftTerm.
        view.startProcess(
            executable: Self.tmuxPath,
            args: ["set-option", "-t", target, "mouse", "on", ";", "attach", "-t", target]
        )
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// GUI Mac apps don't inherit the user's shell PATH, so probe the common
    /// homebrew locations explicitly rather than relying on `/usr/bin/env`.
    private static let tmuxPath: String = {
        for candidate in ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return "/opt/homebrew/bin/tmux"
    }()

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}
