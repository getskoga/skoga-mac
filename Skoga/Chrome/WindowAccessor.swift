import SwiftUI
import AppKit

/// Reaches into the underlying `NSWindow` so we can:
///   • make content extend behind the (hidden) titlebar
///   • move the real traffic-light buttons into our custom 44pt bar
/// The SwiftUI hiddenTitleBar style leaves the buttons floating at (0, 0); we
/// nudge them down a few points so they sit centered against the parchment.
struct WindowAccessor: NSViewRepresentable {
    /// Invoked once the host `NSWindow` is resolved. Lets callers
    /// scope window-specific notification filters (e.g. miniaturize)
    /// to the actual main window rather than every NSWindow in the
    /// process.
    var onWindow: ((NSWindow) -> Void)? = nil

    final class Coordinator {
        var configured = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in
            guard let window = v?.window, !context.coordinator.configured else { return }
            context.coordinator.configured = true
            configure(window)
            onWindow?(window)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let w = nsView.window, !context.coordinator.configured {
            context.coordinator.configured = true
            configure(w)
            onWindow?(w)
        }
    }

    private func configure(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear

        // Center traffic-light buttons vertically in the 44pt custom titlebar.
        // SwiftUI's hidden style positions them too high by default.
        if let close = window.standardWindowButton(.closeButton) {
            close.superview?.setFrameOrigin(.init(x: 0, y: 0))
        }
        let nudge: CGFloat = 4
        let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        kinds.forEach { kind in
            if let b = window.standardWindowButton(kind) {
                var f = b.frame
                f.origin.y -= nudge
                b.setFrameOrigin(f.origin)
            }
        }
    }
}

/// Region in the title bar that acts as a window drag handle.
/// SwiftUI doesn't expose `-webkit-app-region: drag` natively, so we install
/// an NSView that returns `true` from `mouseDownCanMoveWindow`.
struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DraggableNSView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DraggableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { self }
}
