import Foundation

/// Modal/navigation slice — which view is active and which overlay (if
/// any) is up. The toast also lives here since toasts are an overlay in
/// the same chrome-level z-stack as PR/Stop/CommandPalette, and routing
/// them through here keeps the "what's drawn on top of the main area"
/// state in one place.
@MainActor
@Observable
final class ModalState {
    /// All UI-driven — views write these directly (toggle the palette,
    /// open/close modals, switch the active screen).
    var view: AppView = .roster
    var prAgentId: String? = nil
    var stopAgentId: String? = nil
    var commandPaletteOpen: Bool = false
    var bugReportOpen: Bool = false
    var kongleHelperOpen: Bool = false

    /// Set only via `showToast` so the dismiss timer's identity check
    /// can de-dup correctly — a direct write would dodge the timer and
    /// leave a stale message pinned on screen.
    private(set) var toast: String? = nil

    /// Show a transient toast for `duration` seconds, then clear it
    /// unless something else has overwritten it in the meantime. The
    /// identity check is the de-dup mechanism — back-to-back toasts each
    /// spawn a timer; only the timer whose remembered text still matches
    /// the live toast clears it, so an early dismiss can't clobber a
    /// later message that fired within the window.
    func showToast(_ message: String, duration: TimeInterval = 6.0) {
        toast = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if self?.toast == message { self?.toast = nil }
        }
    }
}
