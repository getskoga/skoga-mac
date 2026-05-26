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
        // 11pt matches `SkogaFont.mono`, the app's standard monospace size
        // for code-shaped text. SwiftTerm's default font is noticeably
        // larger and clashes with the surrounding chrome.
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let view = TerminalView(frame: .zero, font: font)
        view.terminalDelegate = context.coordinator
        view.configureNativeColors()
        // SwiftTerm defaults to a 500-line scrollback buffer, which an
        // active agent fills in seconds — the user can scroll up a
        // little, then the wheel deadens against the top of the buffer
        // long before reaching the start of the conversation. Allocate
        // headroom that's effectively unbounded for any plausible
        // single-session run; the buffer is a circular list of
        // lazily-materialized lines, so the unused slots cost one
        // pointer each (~8 bytes), not a full line of cells.
        view.getTerminal().changeScrollback(50_000)
        // Keep the caret drawing as if focused even when first-responder is
        // temporarily elsewhere. SwiftUI's focus engine occasionally yanks
        // first-responder during arrow-key handling; without this flag the
        // caret pops to a hollow outline (or disappears entirely under
        // Metal) and the pane visually feels "asleep" even while bytes are
        // still flowing. The event monitor below reclaims focus on the
        // next keystroke, but until then we still want a live-looking caret.
        view.caretViewTracksFocus = false
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
        /// Local event monitor that promotes the terminal to first responder
        /// when the user clicks inside it OR when a key arrives while the
        /// pane is mounted but focus has drifted (SwiftUI's focus engine
        /// claims arrow keys for keyboard nav, which yanks first-responder
        /// away after the first arrow press — without reclamation, the
        /// very next character is dropped). SwiftTerm's own `mouseDown`
        /// handles selection but never calls `makeFirstResponder(self)`,
        /// so this is also the only thing promoting it on first click.
        private var eventMonitor: Any?
        /// Consumes the daemon's PTY stream. Cancelling tears down the
        /// persistent JSONRPCClient connection — the daemon notices the
        /// drop and stops broadcasting to this subscriber.
        private var streamTask: Task<Void, Never>?
        /// Set once `sizeChanged` first delivers real dimensions and we've
        /// opened the daemon stream. We defer opening until then so the
        /// daemon resizes tmux to our actual SwiftTerm cell grid BEFORE
        /// capturing the snapshot — otherwise the agent's absolute-cursor
        /// escape codes (calibrated to tmux's pane size) collide with
        /// SwiftTerm's column count and the pane renders scrambled.
        private var hasOpenedStream = false
        /// Latest cols/rows from `sizeChanged`. SwiftUI typically does
        /// several layout passes when the conversation view first mounts
        /// (chrome height settles, side panel reveals, …); each pass fires
        /// a fresh `sizeChanged`. We coalesce them via `streamOpenTask`
        /// so the daemon snapshot is captured at the FINAL dimensions
        /// rather than an intermediate one.
        private var latestCols: UInt16 = 0
        private var latestRows: UInt16 = 0
        /// Debounce timer for opening the stream. Reset on every
        /// `sizeChanged` before `hasOpenedStream`; fires once dimensions
        /// have been stable for `streamOpenDebounceNanos`.
        private var streamOpenTask: Task<Void, Never>?
        /// 150ms of layout silence is plenty for SwiftUI to settle even
        /// when the window is mid-animation, and short enough that the
        /// human eye reads attach as immediate.
        private let streamOpenDebounceNanos: UInt64 = 150_000_000

        func attach(view: TerminalView, sessionId: String, client: DaemonClient) {
            self.view = view
            self.sessionId = sessionId
            self.client = client
            installEventMonitor()
            // Stream open is deferred to the first `sizeChanged` delegate
            // callback so we hand the daemon real dimensions. SwiftUI's
            // first layout pass triggers that callback shortly after
            // `makeNSView` returns.
        }

        private func installEventMonitor() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .keyDown]
            ) { [weak self] event in
                guard let self,
                      let view = self.view,
                      let window = view.window,
                      event.window === window
                else { return event }
                switch event.type {
                case .leftMouseDown:
                    let pointInView = view.convert(event.locationInWindow, from: nil)
                    if view.bounds.contains(pointInView), window.firstResponder !== view {
                        window.makeFirstResponder(view)
                    }
                case .keyDown:
                    // The Native pane has no other text-input children, so a
                    // keystroke arriving while first-responder is anything
                    // OTHER than a recognized text widget is almost always
                    // a SwiftUI focus-engine hijack (e.g. arrows for sidebar
                    // nav). Reclaim focus, then let AppKit dispatch the
                    // event via its normal sendEvent path — that routes it
                    // to whichever responder is current AT dispatch time,
                    // which is now our view. Skip when a real text input is
                    // focused (command palette / search field) so we don't
                    // steal keystrokes the user meant for those.
                    //
                    // Don't manually call `view.keyDown(with:)` here: it
                    // bypasses NSWindow's responder bookkeeping for the
                    // NSTextInputClient bridge that SwiftTerm relies on,
                    // and printable characters then arrive at the view
                    // without ever invoking `send(source:data:)`.
                    if window.firstResponder !== view,
                       !isTextInputResponder(window.firstResponder)
                    {
                        window.makeFirstResponder(view)
                    }
                default:
                    break
                }
                return event
            }
        }

        private func isTextInputResponder(_ responder: NSResponder?) -> Bool {
            responder is NSText || responder is NSTextField || responder is NSSearchField
        }

        private func openStreamIfNeeded(cols: UInt16, rows: UInt16) {
            guard !hasOpenedStream, cols > 0, rows > 0, let client else { return }
            hasOpenedStream = true
            // First time we know the view is laid out AND in a window —
            // claim first responder so the user's first keystroke after
            // opening Native mode reaches the agent. (Subsequent click-to-
            // focus and key-event focus-reclaim happen via the event
            // monitor in `installEventMonitor`.)
            if let view, view.window?.firstResponder !== view {
                view.window?.makeFirstResponder(view)
            }
            let sid = sessionId
            streamTask?.cancel()
            streamTask = Task { [weak self] in
                await self?.consumeStream(
                    sessionId: sid,
                    client: client,
                    initialCols: cols,
                    initialRows: rows
                )
            }
        }

        nonisolated func detach() {
            Task { @MainActor [weak self] in
                self?.streamTask?.cancel()
                self?.streamTask = nil
                self?.streamOpenTask?.cancel()
                self?.streamOpenTask = nil
            }
        }

        deinit {
            // Tear the consumer down on the way out. The Task may already
            // be ending if the view's been removed; cancel is idempotent.
            streamTask?.cancel()
            streamOpenTask?.cancel()
            if let m = eventMonitor { NSEvent.removeMonitor(m) }
        }

        private func consumeStream(
            sessionId: String,
            client: DaemonClient,
            initialCols: UInt16,
            initialRows: UInt16
        ) async {
            do {
                // Squeeze the pane by one row BEFORE attach_stream so the
                // daemon's resize-back-to-initialRows is guaranteed to be a
                // real dimension change. tmux only propagates SIGWINCH when
                // dims actually change, and on re-attach our requested dims
                // already match the pane's current state (we set them on
                // the previous attach). Without a real change, Claude Code
                // doesn't redraw and capture-pane hands us whatever wrap
                // state was last rendered — which the user reports as
                // broken wrapping after navigating away and back. Forcing a
                // SIGWINCH on every attach gives us a clean repaint.
                if initialCols > 0, initialRows > 1 {
                    try? await client.ptyResize(
                        sessionId: sessionId,
                        cols: initialCols,
                        rows: initialRows - 1
                    )
                }
                let attached = try await client.openPTYStream(
                    sessionId: sessionId,
                    cols: initialCols > 0 ? initialCols : nil,
                    rows: initialRows > 0 ? initialRows : nil
                )
                // Wipe SwiftTerm's buffer before feeding the snapshot so
                // any stray cells from a prior attach (or from the
                // default-sized warm-up before our first sizeChanged)
                // don't bleed through. The snapshot from `tmux capture-pane`
                // doesn't always begin with an explicit clear, so without
                // this the top of the pane can hold stale content the
                // agent never overwrites until its next full redraw.
                if let clear = "\u{1b}[2J\u{1b}[H".data(using: .utf8) {
                    feed(clear)
                }
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
                self?.enqueueWrite(payload)
            }
        }

        /// Pending bytes waiting to ship to the daemon. We coalesce because
        /// each keystroke arrives via its own `send` delegate call; without
        /// coalescing, every keystroke spawns its own `ptyWrite` Task and
        /// they race during the network await (the daemon dispatches them
        /// in whatever order they land, scrambling input order — e.g.
        /// "UN" becomes "NU"). A single flushing Task drains the buffer
        /// in order, so multi-byte input is delivered as one tmux
        /// `send-keys -H` invocation per network roundtrip.
        private var pendingWriteBuffer = Data()
        private var writeFlushing = false

        private func enqueueWrite(_ bytes: Data) {
            pendingWriteBuffer.append(bytes)
            if !writeFlushing {
                writeFlushing = true
                Task { @MainActor [weak self] in
                    await self?.flushWrites()
                }
            }
        }

        private func flushWrites() async {
            defer { writeFlushing = false }
            while !pendingWriteBuffer.isEmpty {
                guard let client else { return }
                let chunk = pendingWriteBuffer
                pendingWriteBuffer.removeAll(keepingCapacity: true)
                try? await client.ptyWrite(sessionId: sessionId, bytes: chunk)
            }
        }

        nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            let cols = UInt16(clamping: newCols)
            let rows = UInt16(clamping: newRows)
            Task { @MainActor [weak self] in
                guard let self, cols > 0, rows > 0 else { return }
                self.latestCols = cols
                self.latestRows = rows
                if !self.hasOpenedStream {
                    // Debounce: SwiftUI fires several `sizeChanged`s in
                    // quick succession during initial layout (chrome
                    // settles, side panel reveals). Opening on the FIRST
                    // one captures a snapshot at intermediate dimensions
                    // that won't match the final SwiftTerm cell grid —
                    // the user then sees overlapped cells until a manual
                    // window resize forces Claude Code to redraw.
                    self.scheduleStreamOpen()
                } else if let client = self.client {
                    try? await client.ptyResize(
                        sessionId: self.sessionId, cols: cols, rows: rows
                    )
                }
            }
        }

        private func scheduleStreamOpen() {
            streamOpenTask?.cancel()
            streamOpenTask = Task { @MainActor [weak self] in
                guard let nanos = self?.streamOpenDebounceNanos else { return }
                try? await Task.sleep(nanoseconds: nanos)
                guard let self, !Task.isCancelled else { return }
                self.openStreamIfNeeded(cols: self.latestCols, rows: self.latestRows)
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
