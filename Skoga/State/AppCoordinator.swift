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
    let history: HistoryState
    let notifications: NotificationsService
    let namedAgents: NamedAgentsState
    let policy: PolicyState

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

    /// Just-attached sessions whose `attachSession` returned an Agent but
    /// whose row hasn't appeared in `roster.agents` yet. The race is
    /// narrow — the CLI shell-out emits a tmux session that the
    /// daemon's reconciler picks up on the same tick — but if the
    /// post-attach `refresh()` lands before the daemon sees the
    /// relaunched pane, `openAgent` would resolve to nil and the user
    /// would land on `MainWindow.placeholderView`. Cleared by
    /// `apply(agents:)` once the roster catches up; consulted last by
    /// `openAgent`'s fallback chain.
    @ObservationIgnored private var attachedFallbacks: [String: Agent] = [:]

    /// View the user was on when they opened the current conversation,
    /// remembered so the conversation's back button routes them back
    /// to it instead of always landing on `.roster`. Captured by
    /// `openConversation(for:)` only when the prior view wasn't
    /// `.conversation` itself (otherwise navigating between two
    /// conversations would lose the original anchor).
    @ObservationIgnored private var conversationOrigin: AppView = .roster

    /// The `for await` loop over `daemon.client.events()`. Tracked so a
    /// demo-mode client swap can cancel the old client's subscription
    /// before subscribing to the new one — otherwise every enter/exit
    /// would leak one loop that keeps triggering refreshes.
    @ObservationIgnored private var eventLoopTask: Task<Void, Never>?

    /// Monotonically-increasing token for in-flight `loadHistory` calls.
    /// Bumped on entry, captured locally, and re-checked after the await
    /// so a slower fetch that was superseded by a newer chip click can't
    /// stamp stale results on top of the user's current selection. The
    /// underlying RPC isn't cancellable (`withCheckedThrowingContinuation`
    /// on a worker queue) so we can't rely on `Task.isCancelled` to
    /// short-circuit — the token discards the late reply instead.
    @ObservationIgnored private var historyRequestGen: Int = 0

    init(client: DaemonClient? = nil, isMock: Bool = true) {
        self.roster = RosterState()
        self.conversation = ConversationState()
        self.modal = ModalState()
        self.daemon = DaemonClientHolder(client: client ?? MockDaemonClient(), isMock: isMock)
        self.history = HistoryState()
        self.namedAgents = NamedAgentsState()
        self.policy = PolicyState()
        // Singleton — the AppDelegate adaptor already registered it as
        // the UNUserNotificationCenter delegate in
        // `applicationWillFinishLaunching`, before this coordinator
        // existed. Assigning `openSession` here triggers replay of any
        // click that landed during cold launch via the service's
        // `didSet` on the property.
        self.notifications = NotificationsService.shared
        self.notifications.openSession = { [weak self] id in
            guard let self else { return }
            self.openConversation(for: id)
        }
        self.notifications.activateWindow = { [weak self] in
            guard let window = self?.mainWindow else { return }
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        self.notifications.explainerToast = { [weak self] message in
            self?.modal.showToast(message, duration: 6)
        }
    }

    func bootstrap() async {
        // Notification authorization is requested when `FirstRunGate`
        // observes `onboarding.completed == true` — see
        // `notifications.start()` call there. Deferring keeps the
        // first-launch explainer toast from rendering UNDER the
        // onboarding overlay and avoids racing the system permission
        // prompt against the wizard.
        await refresh()
        // Fire-and-forget the gh-status fetch — it shells out to
        // `gh auth status` on the daemon side, which costs a few hundred
        // ms. Blocking the bootstrap means the Roster takes that long to
        // appear; the PR modal and Settings each await the same call on
        // their own surface anyway.
        Task { await daemon.refreshGitHubStatus() }
        // Fire-and-forget the models.list fetch too — Dispatch and
        // Settings each retrigger on their own `.task`, but seeding the
        // holder at bootstrap means the first Dispatch open already has
        // the live list (no flash from the fallback to "now Opus 4.8 is
        // here"). Cheap RPC; no UI blocking.
        Task { await daemon.refreshModels() }
        // Seed the History slice in the background so the
        // permanent-agents successful-runs counter can fold in PR-
        // merged sessions from before this app launch (skoga-mac#33).
        // Without this, a returning user with a long history would
        // need to manually visit the History view before the
        // "Save as permanent agent?" prompt threshold reflects
        // their past work. The History view's own `.task` reuses
        // whatever this lands so navigation there is still snappy.
        Task { @MainActor [weak self] in
            await self?.loadHistory(reset: true)
            // Recount once after the page lands so the counter
            // catches up immediately rather than waiting for the
            // next 5s tick.
            if let self {
                self.namedAgents.recountSuccessfulRuns(
                    from: self.roster.agents,
                    self.history.sessions
                )
            }
        }
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
    /// `session.list` round-trip cleanly. Spend and the cockpit's
    /// activity sparkline poll alongside on the same tick — both are
    /// cheap daemon-side rollups (in-memory ring buffer for activity,
    /// pre-aggregated USD totals for spend) and feed surfaces that
    /// would otherwise stall on the next refresh after a session
    /// terminates.
    func refresh() async {
        if daemon.isMock {
            if let next = try? await daemon.client.listAgents() {
                roster.apply(agents: next)
                evictAttachedFallbacks(matchedBy: next)
            }
        } else {
            do {
                let version = try await daemon.client.daemonVersion()
                let next = try await daemon.client.listAgents()
                roster.apply(agents: next)
                evictAttachedFallbacks(matchedBy: next)
                daemon.setDaemonStatus(.connected(version: version))
                autoShipMergedSessions()
            } catch {
                daemon.setDaemonStatus(.notRunning(detail: error.toastMessage))
            }
        }
        // Spend + activity roll up independently of the agent list — a
        // transport hiccup on either shouldn't flip the connection banner
        // or drop the roster. `try?` keeps the prior values on transport
        // failure; METHOD_NOT_FOUND on older daemons returns nil/`[]` and
        // the consuming surfaces fall back to their own defaults
        // (sum-of-live-agents for spend, flat baseline for activity).
        if let total = try? await daemon.client.spendToday() {
            roster.apply(todaySpend: total)
        }
        if let series = try? await daemon.client.activitySeries() {
            roster.apply(activity: series)
        }
        // v1: the containment denial ride-along is disabled — the Policy
        // surface is hidden until the security / sandbox stack ships in v2.
        // `policyDenials` / `PolicyState` / `PolicyView` all remain in-tree;
        // restore this block to re-light the Policy sidebar badge and panel.
        //
        // Containment denials ride along so the Policy sidebar badge and
        // (when open) the panel stay live without the panel polling on
        // its own. `try?` keeps the prior list on a transport hiccup;
        // METHOD_NOT_FOUND on older daemons returns `[]` (swallowed in the
        // live client), which `apply` treats as "nothing denied". The
        // panel's own `loadDenials` owns the loading/error affordance —
        // this path never sets `.error`, so a flaky tick can't blow the
        // panel into its error state mid-read.
        // if let denials = try? await daemon.client.policyDenials(sessionId: nil) {
        //     policy.apply(denials: denials)
        // }
        // Permanent agents registry + the per-name successful-runs
        // counter ride along on every poll. `agents.list` returns []
        // on older daemons (METHOD_NOT_FOUND swallowed in the live
        // client), so the dispatch grid + sidebar pins just stay
        // empty in that case rather than dropping a banner. The
        // counter is recomputed from the freshly-applied roster +
        // whatever terminal history is already loaded, so the
        // "Save as permanent agent?" footer prompt reflects both
        // current-session activity and prior PR-merged runs from
        // before the app launched. The history slice is best-effort
        // — `bootstrap` kicks off the initial load, but until that
        // returns this just counts the live roster, which is the
        // same behavior pre-history-fold.
        if let next = try? await daemon.client.listNamedAgents() {
            namedAgents.apply(agents: next)
        }
        namedAgents.recountSuccessfulRuns(from: roster.agents, history.sessions)
        let liveIds = Set(roster.agents.map(\.id))
            .union(history.sessions.map(\.id))
        namedAgents.prune(keepingSessionIds: liveIds)
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

    /// Convert an ephemeral Norse-named identity into a permanent
    /// agent the user can re-dispatch against. Driven by the
    /// conversation footer prompt — at the call site we know the
    /// open session, so we hand its name + role + model through as
    /// NamedAgent defaults. `defaultRepo` is deliberately left `nil`:
    /// `Agent.repo` is the display slug (e.g. `"skoga/monolith-web"`),
    /// not the absolute `repo_root` path that `Settings → Agents` and
    /// `Dispatch.orderedPermanentAgents` both compare against; passing
    /// the slug would silently break the "matching repo first" sort.
    /// The user can rehome the agent later from the Settings panel.
    /// Surfaces success/failure as a toast and triggers an immediate
    /// refresh so the dispatch grid + sidebar pins reflect the new
    /// permanent agent without waiting for the next 5s tick.
    func saveAsPermanentAgent(from agent: Agent) async {
        do {
            let created = try await daemon.client.createNamedAgent(
                name: agent.name,
                role: agent.role,
                defaultRepo: nil,
                defaultModel: agent.model
            )
            modal.showToast("\(created.name) is now a permanent agent.")
            await refresh()
        } catch {
            modal.showToast("Couldn't save \(agent.name): \(error.toastMessage)")
        }
    }

    /// Rename / re-role / re-home a permanent agent (`agents.update`).
    /// PATCH-shape — `nil` arguments are left alone daemon-side, so the
    /// Settings → Agents form can submit just the field the user
    /// edited. Trims whitespace and treats blank input as a no-op so
    /// the daemon's empty-input validator doesn't get a useless RPC.
    /// Surfaces success/failure as a toast and refreshes so the
    /// dispatch grid + sidebar pins reflect the new label.
    @discardableResult
    func updatePermanentAgent(id: String, name: String?, role: String?, defaultRepo: String?, defaultModel: String?) async -> Bool {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRole = role?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameArg = (trimmedName?.isEmpty ?? true) ? nil : trimmedName
        let roleArg = (trimmedRole?.isEmpty ?? true) ? nil : trimmedRole
        do {
            let updated = try await daemon.client.updateNamedAgent(
                id: id,
                name: nameArg,
                role: roleArg,
                defaultRepo: defaultRepo,
                defaultModel: defaultModel
            )
            modal.showToast("Updated \(updated.name).")
            await refresh()
            return true
        } catch {
            modal.showToast("Couldn't update agent: \(error.toastMessage)")
            return false
        }
    }

    /// Forget a permanent agent (`agents.delete`). Open sessions
    /// dispatched against this agent keep running; only the pinned
    /// identity in the registry goes away. Refreshes on success so
    /// the dispatch grid + sidebar pins drop the row immediately.
    func deletePermanentAgent(id: String, name: String) async {
        do {
            _ = try await daemon.client.deleteNamedAgent(id: id)
            modal.showToast("Removed \(name) from permanent agents.")
            await refresh()
        } catch {
            modal.showToast("Couldn't remove \(name): \(error.toastMessage)")
        }
    }

    func dispatch(task: String, agent: String, model: String?, base: String, repoRoot: URL, initialPrompt: String?, namedAgentId: String? = nil, attachments: [URL] = []) async {
        do {
            // Attachments go directly on `session.create`. The daemon writes
            // them to `<worktree>/.skoga/attachments/` before forking
            // `_dispatch_launch` and appends a path-list section to
            // `initialPrompt`, so the agent's first turn sees the files on
            // disk and named in its brief. Failures (sanitization, size cap,
            // sha mismatch) surface as RPC errors on the create call and
            // hit the catch below — same shape as any other dispatch
            // validation failure.
            let created = try await daemon.client.createSession(
                task: task,
                agent: agent,
                model: model,
                base: base,
                repoRoot: repoRoot,
                initialPrompt: initialPrompt,
                namedAgentId: namedAgentId,
                attachments: attachments
            )
            let title = task.count > 48 ? String(task.prefix(48)) + "…" : task
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

    /// Re-arm a session via the daemon's `session.attach` RPC (driven
    /// through the `skoga attach` CLI so the agent relaunch — tmux
    /// pane, sandbox wrap, adapter exec — happens too). Flips the
    /// daemon's state back to `.running` so the existing worktree and
    /// transcript stay intact. The user lands in the conversation
    /// view, which automatically switches from the read-only
    /// `ParsedTranscriptView` to the live embedded TUI once the agent
    /// flips out of `.isTerminal`. Daemon-terminal sessions
    /// (`Done`/`Killed`, whose worktrees are gone) and mid-teardown
    /// sessions surface a clean error toast instead.
    ///
    /// Ordering matters here: we stash the returned `Agent` in the
    /// `attachedFallbacks` cache BEFORE navigating so `openAgent` can
    /// always resolve, then `refresh()` so the Roster picks up the
    /// now-live session, and only then `history.remove(id:)` — that
    /// way a `refresh()` failure leaves the History row intact so the
    /// user can retry from the same place instead of landing on the
    /// `MainWindow.placeholderView` with no agent in scope.
    func attach(agentId: String) async {
        let prior = history.sessions.first(where: { $0.id == agentId })
            ?? roster.agents.first(where: { $0.id == agentId })
        let name = prior?.name ?? "agent"
        do {
            let attached = try await daemon.client.attachSession(id: agentId)
            attachedFallbacks[agentId] = attached
            await refresh()
            history.remove(id: agentId)
            modal.showToast("Reattached to \(name).")
            openConversation(for: agentId)
        } catch {
            modal.showToast("Attach failed: \(error.toastMessage)")
        }
    }

    /// Drop any fallback whose id now appears in the freshly-fetched
    /// roster — the live record supersedes the post-attach snapshot.
    /// Called from `refresh()` so the cache doesn't grow unboundedly
    /// across the session's lifetime.
    private func evictAttachedFallbacks(matchedBy live: [Agent]) {
        guard !attachedFallbacks.isEmpty else { return }
        let liveIds = Set(live.map(\.id))
        attachedFallbacks = attachedFallbacks.filter { !liveIds.contains($0.key) }
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

    // MARK: – Demo mode

    /// Swap the app onto the seeded `MockDaemonClient` at runtime — the
    /// "Try the demo" affordance in `DaemonStatusBanner`, for users (and
    /// App Review) who don't have skogad installed and can't set the
    /// `SKOGA_USE_MOCK` env var. Lands on the Roster with the mock seeds;
    /// the banner flips to `.mock` with an "Exit demo" affordance.
    func enterDemoMode() async {
        daemon.switchClient(MockDaemonClient(), isMock: true)
        navigate(to: .roster)
        await refresh()
        startEventLoop()
        modal.showToast("Demo mode — showing sample agents.")
    }

    /// Leave demo mode: back onto a fresh `LiveDaemonClient`. If skogad
    /// still isn't running the next refresh flips the banner back to
    /// `.notRunning` (with the demo affordance available again).
    func exitDemoMode() async {
        daemon.switchClient(LiveDaemonClient(), isMock: false)
        navigate(to: .roster)
        await refresh()
        startEventLoop()
    }

    private func startEventLoop() {
        eventLoopTask?.cancel()
        let stream = daemon.client.events()
        eventLoopTask = Task { [weak self] in
            for await event in stream {
                if Task.isCancelled { return }
                await self?.refresh()
                if event.type == "pr-feedback", let id = event.session_id {
                    await self?.handlePRFeedback(sessionId: id)
                }
                // Route `notification.*` events to the user-notification
                // service. Non-notification event types short-circuit
                // inside the wrapper so the dispatch is free. Goes
                // through an `await` so the MainActor-isolated
                // `notifications` property is touched from the right
                // context — the Task body itself isn't MainActor.
                await self?.routeToNotifications(event)
            }
        }
    }

    /// MainActor-isolated wrapper used by `startEventLoop` to route
    /// daemon events to the notifications service. Pulled out so the
    /// non-isolated Task body has a single, properly-awaited entry
    /// point rather than reaching into `notifications` directly.
    private func routeToNotifications(_ event: RPCEvent) {
        notifications.handle(event: event)
    }

    /// Daemon's PR watcher just pasted review activity into the agent. We've
    /// already refetched the roster (the event loop calls `refresh()` first),
    /// so the agent's status / timestamps are current — now toast so the user
    /// notices, and re-pull the open conversation + timeline so the routed
    /// prompt and "Routed feedback from …" timeline entry show up without
    /// waiting for the 5s poll.
    private func handlePRFeedback(sessionId: String) async {
        let name = roster.agents.first(where: { $0.id == sessionId })?.name ?? "agent"
        modal.showToast("Routed PR feedback to \(name).")
        if conversation.openAgentId == sessionId {
            await loadConversation(sessionId)
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
                    // Skip the 5s re-poll for terminal sessions —
                    // their transcript is frozen at the moment of
                    // teardown so the daemon's reconstruction won't
                    // produce anything new. Saves a per-tick RPC +
                    // decode pass per History session the user is
                    // reading.
                    let isLiveSession = self.openAgent?.status.isTerminal == false
                    if isLiveSession {
                        await self.loadConversation(id)
                    }
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
        // Terminal sessions live in `history.sessions`, not `roster.agents`
        // (the roster's `session.list` call hardcodes `include_terminal:
        // false`). Without the history fallback, clicking a row in the
        // History view would land on `MainWindow.placeholderView` because
        // this lookup returns nil for any terminal session id. The
        // attached-fallback entry catches the post-attach window where
        // the daemon's reconciler hasn't yet surfaced the relaunched
        // session in `session.list`.
        return roster.agents.first(where: { $0.id == id })
            ?? history.sessions.first(where: { $0.id == id })
            ?? attachedFallbacks[id]
    }

    func openConversation(for id: String) {
        if modal.view != .conversation {
            conversationOrigin = modal.view
        }
        conversation.setOpenAgent(id)
        modal.view = .conversation
        conversation.pendingReply = ""
        Task { await loadConversation(id) }
    }

    /// Return to whichever surface the user was on before they opened
    /// this conversation — Roster for a guild click, History for a
    /// row click in the archive. Kept named "backToRoster" at the
    /// callsite-shape level for now even though the destination may
    /// not be Roster; renaming the symbol can come in a separate
    /// cleanup.
    func backToRoster() {
        modal.view = conversationOrigin
        conversation.setOpenAgent(nil)
    }

    /// Jump to a top-level view (Roster / Dispatch / Review / Telemetry
    /// / Settings) without going through the conversation surface. Clears
    /// `openAgentId` so the conversation slice's open-agent lookup
    /// resolves to nil — otherwise the conversation poll would keep
    /// firing for an agent the user is no longer watching.
    ///
    /// Persists the destination under `skoga.app.lastView` so Settings →
    /// General's "Open at: last view" can restore it on next launch.
    /// `.conversation` is excluded from persistence by `backToRoster`
    /// (which is the only path that ever lands there), so a restored
    /// value always points at a real top-level tab.
    func navigate(to view: AppView) {
        modal.view = view
        conversation.setOpenAgent(nil)
        UserDefaults.standard.set(view.rawValue, forKey: AppPrefs.lastView)
    }

    /// Fetch a page of terminal sessions for the History view. `reset == true`
    /// drops the prior page list and refetches from the start of the
    /// current date-range window — used on first open and after the
    /// user changes the date-range chip. `reset == false` appends the
    /// next page using `history.nextCursor` — used by the "Load more"
    /// affordance. Deliberately not on the 5s polling loop: the
    /// History view is a manually-explored surface and a 5s re-fetch
    /// of paginated state would invalidate the user's scroll position
    /// and "Load more" cursor for no real benefit.
    func loadHistory(reset: Bool) async {
        // Re-entering the History view should NOT blow away the user's
        // scroll position + load-more cursor. The top-level
        // `.task(id: history.dateRange)` re-fires on every view
        // appearance — bail if the sessions we already have were
        // loaded for the same dateRange. A real chip change bumps
        // `history.dateRange`, makes `loadedFor != dateRange`, and the
        // guard falls through so the refetch actually happens.
        if reset
            && history.loadState == .loaded
            && history.loadedFor == history.dateRange
            && !history.sessions.isEmpty
        {
            return
        }
        // Bump and snapshot the generation token *before* mutating any
        // state — a later call (e.g. rapid date-chip change) will bump
        // again, and the post-await guards below will see `myGen !=
        // historyRequestGen` and bail out of both apply and error
        // paths. Critically, this means the newer request is NOT
        // dropped (the earlier reentrancy guard's bug); both run, but
        // only the latest one's results land.
        historyRequestGen &+= 1
        let myGen = historyRequestGen
        if reset {
            history.reset()
        }
        history.setLoading()
        let cursor = reset ? nil : history.nextCursor
        let since = history.dateRange.since(now: Date())
        do {
            let page = try await daemon.client.listTerminalSessions(
                limit: nil,
                cursor: cursor,
                since: since,
                until: nil
            )
            guard myGen == historyRequestGen else { return }
            history.apply(page: page, replacing: reset)
        } catch {
            guard myGen == historyRequestGen else { return }
            history.setError(error.toastMessage)
        }
    }

    /// Fetch the containment denial log for the Policy panel's first
    /// open. The 5s `refresh()` already rides `policy.denials` along, so
    /// by the time the panel appears the list is usually already
    /// populated — in that case we skip the `.loading` flip so the panel
    /// doesn't flash a spinner over rows it could already show. We only
    /// surface an error here (not on the ride-along poll) because this is
    /// the user explicitly opening the surface; a transport failure on a
    /// background tick shouldn't paint the panel red.
    func loadDenials() async {
        if policy.loadState != .loaded { policy.setLoading() }
        do {
            let denials = try await daemon.client.policyDenials(sessionId: nil)
            policy.apply(denials: denials)
        } catch {
            policy.setError(error.toastMessage)
        }
    }

    /// Promote a denial into the allowlist at `scope`, then drop it from
    /// the panel. Optimistically removes the row on success so the list
    /// reflects the allow immediately (the next ride-along poll won't
    /// re-add it — the daemon clears the entry on promote). The promoting
    /// set gates the row's scope picker so a double-click can't fire two
    /// promotions. Failures (deny-floor rejection on a stale click,
    /// older daemon, transport) surface as a toast and leave the row in
    /// place so the user can retry.
    func promoteDenial(id: String, scope: PolicyPromoteScope) async {
        let denial = policy.denials.first(where: { $0.id == id })
        let label = denial?.label ?? denial?.target ?? "rule"
        policy.setPromoting(true, id: id)
        defer { policy.setPromoting(false, id: id) }
        do {
            try await daemon.client.promoteDenial(id: id, scope: scope)
            policy.remove(id: id)
            modal.showToast(Self.promoteToast(label: label, scope: scope))
        } catch {
            modal.showToast("Couldn't allow \(label): \(error.toastMessage)")
        }
    }

    private static func promoteToast(label: String, scope: PolicyPromoteScope) -> String {
        switch scope {
        case .once:    "Allowed \(label) once."
        case .session: "Allowed \(label) for this session."
        case .global:  "Allowed \(label) everywhere."
        }
    }

    func loadConversation(_ id: String) async {
        // Mock client never throws; the live path throws on transport / RPC
        // failures. Empty-conversation is *not* an error (the daemon returns
        // [] for sessions with no transcript yet) — only surface real
        // failures so a fresh session doesn't toast on every open.
        defer { conversation.markConversationLoaded(id) }
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
        case .history:      "History"
        case .policy:
            policy.pendingCount > 0
                ? "Policy · \(policy.pendingCount) to review"
                : "Policy"
        }
    }
}
