import AppKit
import SwiftTerm
import SwiftUI

/// Renders a skoga session's tmux pane via the daemon's `session.attach_stream`
/// RPC. Bytes the agent emits arrive as `session.pty_data` notifications and
/// are fed straight into a SwiftTerm `TerminalView`; the user's keystrokes
/// flow back through `session.pty_write`; pane size changes go through
/// `session.pty_resize`.
///
/// Unlike the old tmux-shellout flow, the Mac app never spawns `tmux attach`
/// itself: the daemon owns the pipe-pane and we own the renderer. That moves
/// scrollback, selection, and copy/paste back into SwiftTerm's hands —
/// native Mac behavior throughout.
///
/// Apply `.id(sessionId)` at the call site so SwiftUI rebuilds the view
/// (and tears down its byte stream) when the user switches agents.
struct RemoteTerminalView: NSViewRepresentable {
    let sessionId: String
    let client: DaemonClient

    func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        view.configureNativeColors()
        context.coordinator.attach(view: view, sessionId: sessionId, client: client)
        return view
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, TerminalViewDelegate {
        private weak var view: TerminalView?
        private var sessionId: String = ""
        private var client: DaemonClient?
        /// Consumes the daemon's PTY stream. Cancelling tears down the
        /// persistent JSONRPCClient connection — the daemon notices the
        /// drop and stops broadcasting to this subscriber.
        private var streamTask: Task<Void, Never>?

        func attach(view: TerminalView, sessionId: String, client: DaemonClient) {
            self.view = view
            self.sessionId = sessionId
            self.client = client
            let initialCols = UInt16(clamping: view.terminal?.cols ?? 0)
            let initialRows = UInt16(clamping: view.terminal?.rows ?? 0)
            streamTask?.cancel()
            streamTask = Task { [weak self] in
                await self?.consumeStream(
                    sessionId: sessionId,
                    client: client,
                    initialCols: initialCols,
                    initialRows: initialRows
                )
            }
        }

        nonisolated func detach() {
            Task { @MainActor [weak self] in
                self?.streamTask?.cancel()
                self?.streamTask = nil
            }
        }

        deinit {
            // Tear the consumer down on the way out. The Task may already
            // be ending if the view's been removed; cancel is idempotent.
            streamTask?.cancel()
        }

        private func consumeStream(
            sessionId: String,
            client: DaemonClient,
            initialCols: UInt16,
            initialRows: UInt16
        ) async {
            do {
                let attached = try await client.openPTYStream(
                    sessionId: sessionId,
                    cols: initialCols > 0 ? initialCols : nil,
                    rows: initialRows > 0 ? initialRows : nil
                )
                feed(attached.snapshot)
                for await chunk in attached.bytes {
                    if Task.isCancelled { break }
                    feed(chunk)
                }
            } catch {
                // Surface as an inline error line in the pane so the user
                // sees *something* instead of a perpetually-blank view.
                let msg = "\r\n[skoga] failed to attach to session stream: \(error.localizedDescription)\r\n"
                if let data = msg.data(using: .utf8) {
                    feed(data)
                }
            }
        }

        private func feed(_ data: Data) {
            guard let view else { return }
            let bytes = [UInt8](data)
            view.feed(byteArray: bytes[...])
        }

        // MARK: TerminalViewDelegate

        nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let payload = Data(data)
            Task { @MainActor [weak self] in
                guard let self, let client = self.client else { return }
                try? await client.ptyWrite(sessionId: self.sessionId, bytes: payload)
            }
        }

        nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            let cols = UInt16(clamping: newCols)
            let rows = UInt16(clamping: newRows)
            Task { @MainActor [weak self] in
                guard let self, let client = self.client, cols > 0, rows > 0 else { return }
                try? await client.ptyResize(sessionId: self.sessionId, cols: cols, rows: rows)
            }
        }

        nonisolated func setTerminalTitle(source: TerminalView, title: String) {}
        nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        nonisolated func scrolled(source: TerminalView, position: Double) {}
        nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) {
                Task { @MainActor in NSWorkspace.shared.open(url) }
            }
        }
        nonisolated func bell(source: TerminalView) {}
        nonisolated func clipboardCopy(source: TerminalView, content: Data) {
            // Forward OSC 52 to the Mac pasteboard so an agent that copies
            // (e.g. a CLI tool inside the TUI) lands on the user's clipboard.
            Task { @MainActor in
                let pb = NSPasteboard.general
                pb.clearContents()
                if let s = String(data: content, encoding: .utf8) {
                    pb.setString(s, forType: .string)
                }
            }
        }
        nonisolated func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
