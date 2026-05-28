import Foundation
import UserNotifications
import AppKit

/// Bridges the daemon's `notification.*` audit events to macOS user
/// notifications. Two gates decide whether a banner fires:
///
/// 1. The daemon stamps each `notification.*` event with a `silenced:
///    bool` reflecting its own config + quiet-hours window.
/// 2. The Mac re-evaluates the same logic against the user's local
///    `@AppStorage` toggles (Settings → Notifications), since the
///    `config.set` round-trip from Mac UI → daemon config isn't wired
///    yet (see NotificationsSettingsSection's persistence note).
///
/// We suppress when EITHER side says silenced — a defensive AND of the
/// two gates so a config drift between daemon and Mac can't produce a
/// banner the user thought they'd disabled. Today, daemon defaults are
/// wide-open, so the Mac's local prefs do the real gating; when the
/// config bridge lands, the two sides will agree by construction.
///
/// Click-through hands the session id back through `openSession` so
/// the coordinator can foreground the app and route to the matching
/// conversation view. Because macOS may dispatch a launch-via-click
/// before the coordinator has wired its callback (cold launch from
/// Notification Center), we buffer one pending click id and replay it
/// the moment `openSession` is assigned.
///
/// Single instance via `NotificationsService.shared` — there's only
/// one `UNUserNotificationCenter` per process, and the
/// `AppDelegate` adaptor needs to set the delegate before any
/// SwiftUI scene exists, well before `AppCoordinator` is constructed.
@MainActor
final class NotificationsService: NSObject {

    /// Process-wide instance. Owned by the AppDelegate adaptor so its
    /// `UNUserNotificationCenter.delegate` registration in
    /// `applicationWillFinishLaunching` can target a stable object,
    /// and the coordinator can wire callbacks into the same one when
    /// it boots later.
    static let shared = NotificationsService()

    /// Wired by `AppCoordinator` on construction. Called on the main
    /// actor when the user clicks a notification; the coordinator
    /// activates the app, deminiaturizes the window, and opens the
    /// session's conversation. Setting this replays any
    /// `pendingClickSessionId` that arrived before the coordinator
    /// was ready (cold-launch from Notification Center).
    var openSession: ((String) -> Void)? {
        didSet {
            guard let openSession, let pending = pendingClickSessionId else { return }
            pendingClickSessionId = nil
            openSession(pending)
        }
    }

    /// Wired by `AppCoordinator` to bring the main window forward
    /// without the service having to guess the right `NSWindow`.
    /// Called immediately before `openSession` on click-through.
    var activateWindow: (() -> Void)?

    /// Called once on first launch to drop a non-blocking explainer
    /// toast before the system permission prompt appears, so the
    /// user knows why macOS is asking. Wired to `modal.showToast`.
    var explainerToast: ((String) -> Void)?

    /// One-slot buffer for a click that landed before `openSession`
    /// was wired. macOS delivers the launch-via-notification response
    /// after the delegate is set, but BEFORE the SwiftUI scene's
    /// `.task` modifiers run — so the AppDelegate-set delegate is
    /// guaranteed to receive it, but the coordinator's callback may
    /// not be assigned yet. A single slot is enough; subsequent
    /// clicks while the app is "still booting" are vanishingly rare
    /// and the user can re-click.
    private var pendingClickSessionId: String?

    /// Tracks the most recent fire time per `(sessionId, kind)` for
    /// the kinds where the daemon doesn't already de-dupe (run-finished
    /// and budget-alert). `attentionNeeded` is intentionally excluded —
    /// the daemon emits one per `became_waiting` edge, and a real
    /// agent Q&A flow (answer → next question within seconds) IS a
    /// new edge that the user needs to see. The 5s window covers
    /// transport reconnects only.
    private var lastFired: [String: Date] = [:]
    private static let dedupeWindow: TimeInterval = 5

    /// Persist "have we asked yet?" so re-launches don't re-request
    /// authorization on every cold boot. macOS would silently no-op
    /// the duplicate ask anyway, but keeping the flag local lets us
    /// gate the one-time explainer toast on the same condition.
    private static let authRequestedKey = "skoga.notifications.authRequested"

    /// Sentinel UNUserNotificationContent userInfo keys.
    private enum InfoKey {
        static let sessionId = "skoga.sessionId"
        static let kind      = "skoga.kind"
    }

    /// Notification "kinds" — used for dedupe keys, sound choice, and
    /// per-event Settings toggles. Mirrors the daemon's three constants
    /// (`notification.attention_needed` / `run_finished` / `budget_alert`).
    enum Kind: String {
        case attentionNeeded
        case runFinished
        case budgetAlert

        init?(eventType: String) {
            switch eventType {
            case "notification.attention_needed": self = .attentionNeeded
            case "notification.run_finished":     self = .runFinished
            case "notification.budget_alert":     self = .budgetAlert
            default: return nil
            }
        }

        /// AppStorage key under `skoga.notifications.wake.*` that gates
        /// whether this kind ever fires a banner.
        var wakeKey: String {
            switch self {
            case .attentionNeeded: NotificationPrefs.Wake.blocked
            case .runFinished:     NotificationPrefs.Wake.finished
            case .budgetAlert:     NotificationPrefs.Wake.budget
            }
        }
    }

    /// Request authorization + show the first-launch explainer toast
    /// exactly once across all launches. The delegate is already
    /// registered by `SkogaAppDelegate.applicationWillFinishLaunching`
    /// — this method's only responsibility is the one-time auth flow.
    ///
    /// Safe to call repeatedly — the auth-requested flag in
    /// UserDefaults guards every side effect, so re-launches and
    /// re-entries from the onboarding-completion task are no-ops.
    func start() {
        let center = UNUserNotificationCenter.current()
        let firstTime = !UserDefaults.standard.bool(forKey: Self.authRequestedKey)
        guard firstTime else { return }
        UserDefaults.standard.set(true, forKey: Self.authRequestedKey)
        // Toast first so the user has context when macOS pops the
        // permission alert. A short delay lets the host window finish
        // its appear animation — the alert mid-animation feels jumpy.
        // We capture `self` unowned because `shared` outlives every
        // call site; a `[weak self]` would just complicate cleanup
        // around an object that never deinits.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.explainerToast?(
                "Skoga will ping you when an agent needs your decision — change in Settings → Notifications."
            )
            try? await Task.sleep(nanoseconds: 600_000_000)
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if !granted {
                // A denied prompt today means every future `.add()` is
                // a silent no-op. Surface a follow-up toast so the
                // user knows where to flip it back on; without this
                // they'd think notifications are working and wonder
                // why no banner ever appeared.
                try? await Task.sleep(nanoseconds: 400_000_000)
                self.explainerToast?(
                    "Notifications are off. Enable Skoga under System Settings → Notifications to turn them on."
                )
            }
        }
    }

    /// Dispatched from the coordinator's event loop. Returns quickly for
    /// non-`notification.*` types so the hot path stays cheap.
    func handle(event: RPCEvent) {
        guard let kind = Kind(eventType: event.type) else { return }
        // Defensive AND of daemon + Mac silencing decisions. Daemon's
        // `silenced` reflects its own config; local prefs reflect the
        // Mac Settings UI. We suppress when either side says no — see
        // the class-level doc for the rationale.
        if event.payload?.silenced == true { return }
        guard NotificationPrefs.read(NotificationPrefs.Delivery.banners) else { return }
        guard NotificationPrefs.read(kind.wakeKey) else { return }
        if isInQuietHours(at: Date()) { return }
        // Dedupe is per-kind. `attentionNeeded` skips it entirely so an
        // answer → next-question flow within seconds still surfaces —
        // the daemon already guards the `became_waiting` edge, so any
        // event we see here is a real new question. The 5s window for
        // the other kinds covers transport-reconnect re-yields without
        // swallowing genuine state transitions (a finished run can't
        // legitimately re-fire that fast; the daemon's budget-alert
        // state machine prevents same-period re-fires anyway).
        if kind != .attentionNeeded {
            let dedupeKey = "\(event.session_id ?? "system"):\(kind.rawValue)"
            if let prior = lastFired[dedupeKey], Date().timeIntervalSince(prior) < Self.dedupeWindow {
                return
            }
            lastFired[dedupeKey] = Date()
        }

        let content = makeContent(for: kind, event: event)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: – Content building

    private func makeContent(for kind: Kind, event: RPCEvent) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let payload = event.payload
        switch kind {
        case .attentionNeeded:
            content.title = "Agent needs your decision"
            // Daemon sends `headline` (the session's task) + `summary`
            // (the question text). Headline as subtitle keeps the
            // primary title generic ("Agent needs your decision")
            // while still showing which session.
            if let headline = payload?.headline, !headline.isEmpty {
                content.subtitle = headline
            }
            content.body = payload?.summary ?? "An agent is waiting on you."
        case .runFinished:
            content.title = "Agent finished a run"
            if let repo = payload?.repo, let branch = payload?.branch {
                content.subtitle = "\(repoTail(repo)) · \(branch)"
            } else if let branch = payload?.branch {
                content.subtitle = branch
            }
            if let url = payload?.pr_url, !url.isEmpty {
                content.body = "PR ready: \(url)"
            } else {
                content.body = "Run ended cleanly."
            }
        case .budgetAlert:
            let pct = Int((payload?.pct ?? 0).rounded())
            let period = payload?.period ?? "daily"
            content.title = "Budget at \(pct)% of \(period) cap"
            if let spent = payload?.spent_usd, let cap = payload?.budget_usd {
                content.body = String(
                    format: "Spent $%.2f of $%.2f.",
                    spent,
                    cap
                )
            } else {
                content.body = "Approaching your cap for this period."
            }
        }
        // Sound: per the "Sound on attention-needed only" Settings toggle.
        // When the toggle is off the chime fires for every kind; when on
        // (the default) only the blocked-agent alert plays a sound.
        let attentionOnly = NotificationPrefs.read(NotificationPrefs.Delivery.soundAttentionOnly)
        if kind == .attentionNeeded || !attentionOnly {
            content.sound = .default
        }
        // Carry the session id + kind for click-through routing. The kind
        // is included so a future Settings → notification-history view
        // can group by it without re-parsing the title.
        if let sid = event.session_id {
            content.userInfo[InfoKey.sessionId] = sid
        }
        content.userInfo[InfoKey.kind] = kind.rawValue
        return content
    }

    /// `repo` arrives as the absolute worktree path (`/Users/x/code/foo`).
    /// Trim to the last path component so the subtitle stays readable.
    private func repoTail(_ repo: String) -> String {
        (repo as NSString).lastPathComponent
    }

    // MARK: – Quiet hours

    /// Mirror of the Rust daemon's `in_quiet_hours` logic against the
    /// Mac's `skoga.notifications.quiet.*` UserDefaults values. Stored
    /// as minutes-from-midnight (0..1439); `end < start` denotes an
    /// overnight wrap-around (e.g. 22:00 → 07:00).
    private func isInQuietHours(at date: Date) -> Bool {
        guard NotificationPrefs.read(NotificationPrefs.Quiet.enabled) else { return false }
        let startMin = UserDefaults.standard.object(forKey: NotificationPrefs.Quiet.startMinutes) as? Int ?? 22 * 60
        let endMin   = UserDefaults.standard.object(forKey: NotificationPrefs.Quiet.endMinutes)   as? Int ?? 7 * 60
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let nowMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        // start == end → degenerate "always quiet" (matches daemon's
        // `start_s == end_s` branch and the user's "I never want
        // notifications" reading).
        if startMin == endMin { return true }
        if startMin < endMin {
            return nowMin >= startMin && nowMin < endMin
        }
        return nowMin >= startMin || nowMin < endMin
    }
}

// MARK: – UNUserNotificationCenterDelegate

extension NotificationsService: UNUserNotificationCenterDelegate {
    /// Click-through. Activate the app + raise the main window via the
    /// coordinator-supplied `activateWindow` callback, then route to
    /// the conversation for the session embedded in userInfo. When
    /// `openSession` hasn't been wired yet (cold launch from
    /// Notification Center before the coordinator's `.task` runs),
    /// buffer the session id — it replays from the `openSession`
    /// `didSet` the moment the coordinator wires it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let sessionId = info["skoga.sessionId"] as? String
        Task { @MainActor in
            // Activate before routing so the conversation view actually
            // becomes visible — without this, openConversation flips
            // state into a window the user can't see.
            NSApp.activate(ignoringOtherApps: true)
            self.activateWindow?()
            if let sessionId {
                if let openSession = self.openSession {
                    openSession(sessionId)
                } else {
                    // Coordinator not yet wired — stash for replay.
                    self.pendingClickSessionId = sessionId
                }
            }
            completionHandler()
        }
    }

    /// Show banners even when the app is in the foreground. macOS's
    /// default is to suppress — but a manager watching a different
    /// session's conversation still wants the "another agent went
    /// Blocked" banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
