import SwiftUI
import AppKit
import Foundation

/// Thin coordinator over the four scoped slices. Owns the bootstrap, the
/// event/polling loops, and any action method that has to mutate more
/// than one slice at a time (dispatch flips view + opens conversation;
/// kill mutates roster + toasts; openConversation flips view + sets
/// openAgentId + kicks off a load).
///
/// Action methods live here even when they only mutate one slice's data
/// (e.g. `pause` just toasts) so views have one place to find them —
/// they don't have to know which slice owns the underlying mutation.
@MainActor
@Observable
final class AppCoordinator {

    let roster: RosterState
    let conversation: ConversationState
    let modal: ModalState
    let daemon: DaemonClientHolder

    // ── Visibility gating ────────────────────────────────────
    // The polling loop suspends when the app is hidden (cmd+H) or the
    // main window is minimized, and resumes via `resumeContinuation`
    // when either condition clears. `mainWindow` is registered by
    // `WindowAccessor` and used to scope `NSWindow.didMiniaturize`
    // matching to the host window — other windows (sheets, future
    // inspectors) shouldn't gate the polling loop.
    @ObservationIgnored private weak var mainWindow: NSWindow?
    @ObservationIgnored private var appHidden: Bool = false
    @ObservationIgnored private var windowMinimized: Bool = false
    @ObservationIgnored private var resumeContinuation: CheckedContinuation<Void, Never>?
    private var isVisible: Bool { !appHidden && !windowMinimized }

    /// Session ids for which we've already fired the auto-ship RPC. The
    /// daemon's `.prMerged` state is sticky — it stays set until our
    /// `session.ship` call transitions it to `.shipping` — so without
    /// this set we'd re-issue ship on every 5s poll between the call
    /// and the daemon's response. Idempotency on the daemon side covers
    /// the worst case, but spamming rejected RPCs muddies the audit log.
    @ObservationIgnored private var autoShippedSessionIds: Set<String> = []

    init(client: DaemonClient? = nil, isMock: Bool = true) {
        self.roster = RosterState()
        self.conversation = ConversationState()
        self.modal = ModalState()
        self.daemon = DaemonClientHolder(client: client ?? MockDaemonClient(), isMock: isMock)
    }

    func bootstrap() async {
        await refresh()
        // Fire-and-forget the gh-status fetch — it shells out to
        // `gh auth status` on the daemon side, which costs a few hundred
        // ms. Blocking the bootstrap means the Roster takes that long to
        // appear; the PR modal and Settings each await the same call on
        // their own surface anyway.
        Task { await daemon.refreshGitHubStatus() }
        startEventLoop()
        startPollingFallback()

        if let id = ProcessInfo.processInfo.environment["SKOGA_OPEN"],
           roster.agents.contains(where: { $0.id == id }) {
            openConversation(for: id)
        }
        if let view = ProcessInfo.processInfo.environment["SKOGA_VIEW"],
           let v = AppView(rawValue: view) {
            modal.view = v
        }
        if let pr = ProcessInfo.processInfo.environment["SKOGA_PR"],
           roster.agents.contains(where: { $0.id == pr }) {
            modal.prAgentId = pr
        }
        if ProcessInfo.processInfo.environment["SKOGA_CMD"] != nil {
            modal.commandPaletteOpen = true
        }
    }

    /// Re-fetch the agent list and, on the live path, update
    /// `daemon.daemonStatus` based on whether `daemon.version` +
    /// `session.list` round-trip cleanly. The activity series stays on
    /// whatever the client returned at boot (zero-length on live; the
    /// seed wave on mock) — skogad doesn't emit per-minute load yet so
    /// re-polling it is wasted work.
    func refresh() async {
        if daemon.isMock {
            if let next = try? await daemon.client.listAgents() {
                roster.apply(agents: next)
            }
            if let series = try? await daemon.client.activitySeries() {
                roster.apply(activity: series)
            }
            return
        }
        do {
            let version = try await daemon.client.daemonVersion()
            let next = try await daemon.client.listAgents()
            roster.apply(agents: next)
            daemon.setDaemonStatus(.connected(version: version))
            autoShipMergedSessions()
        } catch {
            daemon.setDaemonStatus(.notRunning(detail: error.toastMessage))
        }
    }

    /// Fire `session.ship` on any session the daemon has flagged as
    /// `.prMerged` / `.prClosed` but that we haven't already auto-shipped.
    /// Mirrors what the user would get by running `skoga ship` from the CLI
    /// — the PR landed (or was abandoned), so the session should autoclose.
    /// Mock mode is excluded because the mock has no real teardown path.
    /// Errors are swallowed (with one tracked retry permitted on the next
    /// poll) so a transient RPC failure doesn't deadlock the auto-ship for
    /// this session id.
    private func autoShipMergedSessions() {
        guard !daemon.isMock else { return }
        for agent in roster.agents where agent.needsAutoShip && !autoShippedSessionIds.contains(agent.id) {
            autoShippedSessionIds.insert(agent.id)
            let id = agent.id
            let name = agent.name
            // Capture status now: by the time the ship RPC returns the
            // daemon has already advanced to `.shipping`, so a later read
            // wouldn't be able to tell merged from closed.
            let toast = agent.status == .prClosed
                ? "PR closed — closing \(name)."
                : "PR merged — closing \(name)."
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.daemon.client.shipSession(id: id)
                    self.modal.showToast(toast)
                } catch {
                    // Drop from the set so the next poll retries. The
                    // expected races (already shipping / already done)
                    // resolve themselves as the daemon advances state
                    // and `needsAutoShip` flips to false.
                    self.autoShippedSessionIds.remove(id)
                }
            }
        }
    }

    /// Persist the PR-modal default reviewer to the daemon's config.
    /// Trim + treat empty as a clear so the Settings text field can both
    /// set and unset the value with the same Save action. Surfaces
    /// failures via a toast — losing this silently would leave the user
    /// thinking the value stuck.
    func setDefaultReviewer(_ reviewer: String) async {
        let trimmed = reviewer.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let updated = try await daemon.client.githubSetDefaultReviewer(trimmed)
            daemon.applyGithubStatus(updated)
            // Toast off the daemon's canonical form rather than the user's
            // input. The daemon may normalize (strip a leading `@`,
            // lowercase the handle, expand org aliases) — toasting the
            // pre-normalized text would tell the user a different story
            // than the value that actually landed in config.
            if let persisted = updated.default_reviewer, !persisted.isEmpty {
                modal.showToast("Default reviewer set to \(persisted).")
            } else {
                modal.showToast("Cleared default reviewer.")
            }
        } catch {
            modal.showToast("Couldn't save reviewer: \(error.toastMessage)")
        }
    }

    /// Persist an API key to the daemon's Keychain bridge. The Models
    /// & keys row pre-validates that `key` is non-empty (the daemon
    /// rejects empty input), so callers should treat blank input as
    /// "use `deleteCredential`". On success we update the matching
    /// entry in-place and drop any stale test result for the provider
    /// — an old "✓ Probe succeeded" next to a freshly-rotated key
    /// would mislead the user about which key was actually tested.
    @discardableResult
    func setCredential(provider: RPCCredentialProvider, key: String) async -> Bool {
        do {
            let updated = try await daemon.client.credentialsSet(provider: provider, key: key)
            daemon.applyCredentialEntry(updated)
            daemon.setCredentialTestResult(nil, for: provider)
            modal.showToast("\(provider.displayName) key saved.")
            return true
        } catch {
            modal.showToast("Couldn't save \(provider.displayName) key: \(error.toastMessage)")
            return false
        }
    }

    /// Remove the persisted key for `provider`. Same toast / state
    /// hygiene as `setCredential` — clear the cached test result so
    /// the UI doesn't claim "✓ Probe succeeded" next to a now-empty
    /// row.
    @discardableResult
    func deleteCredential(provider: RPCCredentialProvider) async -> Bool {
        do {
            let deleted = try await daemon.client.credentialsDelete(provider: provider)
            daemon.applyCredentialEntry(RPCCredentialEntry(provider: provider, has_key: false, last_used: nil))
            daemon.setCredentialTestResult(nil, for: provider)
            modal.showToast(deleted ? "Cleared \(provider.displayName) key." : "No \(provider.displayName) key to clear.")
            return true
        } catch {
            modal.showToast("Couldn't clear \(provider.displayName) key: \(error.toastMessage)")
            return false
        }
    }

    /// Run `credentials.test` against `provider`. Per the daemon
    /// contract, this only throws on transport failure — every other
    /// outcome (no key, 401, 403, network) comes back as a
    /// `RPCCredentialsTestResult` with `ok: false` + a message we
    /// render inline. We also refresh the entry's `last_used` from
    /// `credentials.list` because a successful probe bumps it daemon-
    /// side and the row's "used Xm ago" chip should reflect that
    /// without waiting for the user to leave + come back.
    @discardableResult
    func testCredential(provider: RPCCredentialProvider) async -> RPCCredentialsTestResult? {
        do {
            let result = try await daemon.client.credentialsTest(provider: provider)
            daemon.setCredentialTestResult(result, for: provider)
            // Refresh just this provider's entry — `credentials.test`
            // updates `last_used` on success, and the chip should pick
            // that up. Cheap (single list call) and keeps the rest of
            // the UI from flickering on the same tick.
            if result.ok, let refreshed = try? await daemon.client.credentialsList().first(where: { $0.provider == provider }) {
                daemon.applyCredentialEntry(refreshed)
            }
            return result
        } catch {
            // Surface transport failures as a toast — the inline
            // result row only carries daemon-contracted outcomes, and
            // pretending a transport error is "ok: false" would muddy
            // the signal.
            modal.showToast("Probe failed: \(error.toastMessage)")
            return nil
        }
    }

    func dispatch(task: String, agent: String, model: String?, base: String, repoRoot: URL, initialPrompt: String?) async {
        do {
            let created = try await daemon.client.createSession(task: task, agent: agent, model: model, base: base, repoRoot: repoRoot, initialPrompt: initialPrompt)
            let title = task.count > 48 ? task.prefix(48) + "…" : Substring(task)
            modal.showToast("Dispatched \"\(title)\" → \(created.repo) (\(created.name))")
            // Jump straight to the new session's conversation view instead of
            // bouncing back to the roster. Before this change, the user had
            // to find the freshly-dispatched card and click it — and because
            // the daemon now also spawns the agent process (auto_launch),
            // there's a real conversation about to appear here. The view
            // starts empty (no transcript on disk yet) and fills in once
            // Claude's SessionStart hook records the agent_session_id, which
            // happens within a couple of seconds of tmux bringing the pane
            // up. The 5s session.conversation poll picks it up from there.
            await refresh()
            openConversation(for: created.id)
        } catch {
            modal.showToast("Dispatch failed: \(error.toastMessage)")
        }
    }

    func kill(agentId: String) async {
        do {
            try await daemon.client.killSession(id: agentId)
            modal.showToast("Killed session \(agentId.prefix(6))")
            await refresh()
        } catch {
            modal.showToast("Kill failed: \(error.toastMessage)")
        }
    }

    /// Interrupt the agent's current turn without tearing the session down.
    /// We send a single ESC into the tmux pane — Claude Code's TUI treats
    /// that as "stop generating", which is the closest thing the agent has
    /// to a pause. The session, worktree, and conversation history all
    /// remain intact and the user can send a follow-up message to resume.
    func pause(agentId: String) async {
        do {
            try await daemon.client.ptyWrite(sessionId: agentId, bytes: Data([0x1b]))
            let name = roster.agents.first(where: { $0.id == agentId })?.name ?? "agent"
            modal.showToast("Paused \(name).")
        } catch {
            modal.showToast("Pause failed: \(error.toastMessage)")
        }
    }

    /// Deliver a composed reply to the running agent. The daemon pastes it
    /// into the agent's tmux pane; the message will surface in the feed on
    /// the next conversation poll (a few seconds), since the transcript
    /// jsonl is the source of truth for what's displayed.
    func sendReply(to agentId: String, text: String) async {
        do {
            try await daemon.client.sendInput(sessionId: agentId, text: text)
            let name = roster.agents.first(where: { $0.id == agentId })?.name ?? "agent"
            modal.showToast("Sent to \(name).")
        } catch {
            modal.showToast("Send failed: \(error.toastMessage)")
        }
    }

    /// Dispatch the rebase-conflict fix-up prompt to a `.conflicted`
    /// session's agent. The daemon does the actual paste; we refresh the
    /// roster so `rebasePromptDispatchedAt` propagates onto the card and
    /// the button flips to its "Prompt sent" state.
    func resolveRebaseConflict(agentId: String) async {
        do {
            try await daemon.client.resolveRebaseConflict(sessionId: agentId)
            let name = roster.agents.first(where: { $0.id == agentId })?.name ?? "agent"
            modal.showToast("Asked \(name) to rebase.")
            await refresh()
        } catch {
            modal.showToast("Rebase request failed: \(error.toastMessage)")
        }
    }

    /// Submit the user's selection to a pending `AskUserQuestion`. The
    /// daemon drives Claude's TUI picker via tmux key strokes and clears
    /// the pending state. We optimistically drop the question row from the
    /// conversation so the UI doesn't show a stale picker between answer
    /// and the next refresh.
    func answerQuestion(to agentId: String, selectedIndices: [Int]) async {
        let toolUseId = roster.agents.first(where: { $0.id == agentId })?.pendingQuestion?.toolUseId
        do {
            try await daemon.client.answerQuestion(sessionId: agentId, selectedIndices: selectedIndices)
            if let toolUseId {
                conversation.dropQuestion(toolUseId: toolUseId)
            }
            await refresh()
            await loadConversation(agentId)
        } catch {
            modal.showToast("Answer failed: \(error.toastMessage)")
        }
    }

    private func startEventLoop() {
        let stream = daemon.client.events()
        Task { [weak self] in
            for await _ in stream {
                await self?.refresh()
            }
        }
    }

    /// Backstop for when the event stream isn't viable (mock mode, daemon
    /// down, socket closed after subscribe). A 5s tick is cheap and means a
    /// user who starts skogad after launching the app doesn't have to
    /// restart — the next poll switches the banner from `.notRunning` to
    /// `.connected` and the Roster lights up.
    ///
    /// When a conversation is open, we also refetch its messages on the
    /// same tick. The daemon reconstructs them from Claude's transcript
    /// jsonl, which is append-only and ids each row by uuid, so SwiftUI's
    /// ForEach keeps stable identity across polls — scroll position,
    /// focus, and animations stay put. Without this, a freshly dispatched
    /// agent never appears to "speak": loadConversation runs once on
    /// open, when the transcript is still empty.
    private func startPollingFallback() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            while !Task.isCancelled {
                guard let self else { return }
                // If we're not visible, park on a continuation until
                // setAppHidden/setWindowMinimized clears both flags.
                // Resume falls through to the refresh below, so the
                // first poll after a restore happens on the same
                // MainActor turn rather than 5s later.
                if !self.isVisible {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        self.resumeContinuation = cont
                    }
                }
                await self.refresh()
                if let id = self.conversation.openAgentId {
                    await self.loadConversation(id)
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    /// Called by the root view when `NSApplication.didHide/didUnhide`
    /// or `NSWindow.didMiniaturize/didDeminiaturize` fires. When either
    /// condition clears we wake the polling loop's suspended
    /// continuation so the next refresh happens immediately.
    func setAppHidden(_ hidden: Bool) {
        appHidden = hidden
        if isVisible { resumePolling() }
    }

    func setWindowMinimized(_ minimized: Bool) {
        windowMinimized = minimized
        if isVisible { resumePolling() }
    }

    /// `WindowAccessor` calls this once it has resolved the host
    /// `NSWindow`. Used to scope `NSWindow.didMiniaturize` matching to
    /// the main window so sheets / future auxiliary windows don't
    /// accidentally pause the polling loop.
    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
    }

    /// Identity check exposed for the `.onReceive` filter — the
    /// `mainWindow` reference itself stays private.
    func isMainWindow(_ object: Any?) -> Bool {
        guard let window = object as? NSWindow, let main = mainWindow else { return false }
        return window === main
    }

    private func resumePolling() {
        guard let cont = resumeContinuation else { return }
        resumeContinuation = nil
        cont.resume()
    }

    var openAgent: Agent? {
        guard let id = conversation.openAgentId else { return nil }
        return roster.agents.first(where: { $0.id == id })
    }

    func openConversation(for id: String) {
        conversation.setOpenAgent(id)
        modal.view = .conversation
        conversation.pendingReply = ""
        Task { await loadConversation(id) }
    }

    func backToRoster() {
        modal.view = .roster
        conversation.setOpenAgent(nil)
    }

    /// Jump to a top-level view (Roster / Dispatch / Review / Telemetry
    /// / Settings) without going through the conversation surface. Clears
    /// `openAgentId` so the conversation slice's open-agent lookup
    /// resolves to nil — otherwise the conversation poll would keep
    /// firing for an agent the user is no longer watching.
    func navigate(to view: AppView) {
        modal.view = view
        conversation.setOpenAgent(nil)
    }

    func loadConversation(_ id: String) async {
        // Mock client never throws; the live path throws on transport / RPC
        // failures. Empty-conversation is *not* an error (the daemon returns
        // [] for sessions with no transcript yet) — only surface real
        // failures so a fresh session doesn't toast on every open.
        do {
            var msgs = try await daemon.client.conversation(for: id)
            // The daemon's transcript-based conversation doesn't include the
            // in-flight AskUserQuestion (Claude only writes the tool_use
            // block once it completes), so append a synthesized question row
            // from the session's pending_question. The Agent has it after
            // the most recent refresh().
            if let pending = roster.agents.first(where: { $0.id == id })?.pendingQuestion {
                let alreadyHas = msgs.contains {
                    if case .question(let q) = $0 { return q.id == pending.id }
                    return false
                }
                if !alreadyHas {
                    msgs.append(.question(pending))
                }
            }
            conversation.apply(messages: msgs)
        } catch {
            conversation.clearTranscript()
            modal.showToast("Conversation load failed: \(error.toastMessage)")
        }
        do {
            let newTimeline = try await daemon.client.timeline(for: id)
            conversation.apply(timeline: newTimeline)
        } catch {
            conversation.clearTimeline()
        }
    }

    var contextLabel: String {
        switch modal.view {
        case .roster:       "Roster · \(roster.counts.total) agents"
        case .conversation: openAgent.map { "1:1 with \($0.name)" } ?? "Conversation"
        case .dispatch:     "Dispatch · new run"
        case .review:       "Review · \(roster.counts.prOpen) open"
        case .telemetry:    "Telemetry"
        }
    }
}
