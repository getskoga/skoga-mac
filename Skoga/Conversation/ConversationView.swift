import SwiftUI

/// Selects how the conversation surface renders. `.skoga` is the parsed
/// transcript with the native composer; `.native` renders the agent's own
/// TUI in SwiftTerm, fed by the daemon's `session.attach_stream` RPC
/// (see `RemoteTerminalView`). Persisted globally via AppStorage — it's a
/// viewing preference, not per-agent state.
enum ConversationFeedMode: String, CaseIterable {
    case skoga
    case native

    var label: String {
        switch self {
        case .skoga:  "Skoga"
        case .native: "Native"
        }
    }
}

struct ConversationView: View {
    @Environment(\.palette) private var p
    @Environment(ConversationState.self) private var conversation
    @Environment(DaemonClientHolder.self) private var daemon
    let agent: Agent

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ConvHeader(agent: agent)
                // Terminal sessions can't attach to a live PTY (the tmux
                // pane is gone), so we render the parsed transcript
                // straight out of `session.conversation` instead — the
                // same data that's already loaded by `loadConversation`.
                // Live sessions keep the embedded TUI; the read-only
                // path here only kicks in for History-style entries.
                if agent.status.isTerminal {
                    ParsedTranscriptView(
                        messages: conversation.conversation,
                        hasLoaded: conversation.loadedConversationIds.contains(agent.id)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // The TUI owns its own input loop, so the skoga composer is
                    // intentionally hidden here — the user types directly into
                    // the SwiftTerm pane. `id(agent.id)` forces SwiftUI to
                    // rebuild the view (and therefore the byte stream
                    // subscription) when the user navigates between agents.
                    // The chrome frames the terminal as its own "embedded app"
                    // with traffic-light buttons + title bar, so it reads as a
                    // distinct thing inside Skoga.
                    EmbeddedTUIChrome(
                        title: "\(agent.model) — \(agent.branch)",
                        subtitle: agent.runtime
                    ) {
                        RemoteTerminalView(sessionId: agent.id, client: daemon.client)
                            .id(agent.id)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                }

                SavePermanentAgentBanner(agent: agent)
                ConvActionsFooter(agent: agent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .trailing) {
                Hairline(axis: .vertical).frame(width: Tokens.Hairline.width)
            }

            ConvSidePanel(agent: agent, timeline: conversation.timeline)
                .frame(width: Tokens.convAsideWidth)
        }
    }
}

// MARK: – Header

private struct ConvHeader: View {
    @Environment(\.palette) private var p
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(ModalState.self) private var modal
    let agent: Agent

    var body: some View {
        HStack(spacing: 14) {
            Button {
                coordinator.backToRoster()
            } label: {
                Image(skoga: .back).skogaIconSize(14)
                    .frame(width: 26, height: 26)
                    .foregroundStyle(p.inkMute)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .fill(p.paper2)
                            .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                    )
            }
            .buttonStyle(.plain)

            Text(agent.initials)
                .font(SkogaFont.serifName(17))
                .foregroundStyle(p.ink)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9).fill(p.paper4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(agent.name)
                    .font(SkogaFont.serifHeading(21))
                    .foregroundStyle(p.ink)
                Text("\(agent.role) · \(agent.model) · \(agent.repo)")
                    .font(SkogaFont.mono(11))
                    .foregroundStyle(p.inkMute)
            }

            Spacer(minLength: 0)

            if hasRunControls {
                GhostPillButton(label: "Pause", icon: .pause) {
                    Task { await coordinator.pause(agentId: agent.id) }
                }
                GhostPillButton(label: "Stop", icon: .stop, color: p.ember) {
                    modal.stopAgentId = agent.id
                }
            }
        }
        .padding(.horizontal, Tokens.Pad.viewX)
        .padding(.top, 16).padding(.bottom, 14)
        .background(p.paper)
        .overlay(alignment: .bottom) { Hairline() }
    }

    /// Pause/Stop ride along while the agent still has work to interrupt
    /// (`.running` / `.blocked` / `.idle` / `.stopping`). Terminal states
    /// (`.exited`, `.killed`, `.done`, `.prOpen`, `.prMerged`, `.prClosed`)
    /// omit them — there's nothing left to pause and a kill would no-op on
    /// a process that's already gone.
    private var hasRunControls: Bool {
        guard agent.prUrl == nil else { return false }
        switch agent.status {
        case .running, .blocked, .idle, .stopping:                      return true
        case .prOpen, .prMerged, .prClosed, .done, .exited, .killed:    return false
        }
    }
}

// MARK: – Actions footer

/// Footer sits below the embedded TUI and hosts the "Open as PR" CTA
/// alongside the always-available "Push" verb. Both CTAs are decoupled
/// from `agent.status` so the manager can always reach for them. The PR
/// button toggles to "View PR on GitHub" once `prUrl != nil` so a second
/// click doesn't try to re-land; the Push button rides along regardless,
/// since pushing a branch without opening a PR is a first-class use case
/// (and updating an already-open PR after the agent revises is another).
private struct ConvActionsFooter: View {
    @Environment(\.palette) private var p
    @Environment(ModalState.self) private var modal
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(DaemonClientHolder.self) private var daemon
    let agent: Agent

    @State private var pushing = false
    @State private var attaching = false

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if agent.status.isTerminal {
                // Terminal-from-Mac's-view sessions (done/exited/
                // killed/PR-merged/PR-closed) can't be pushed to or
                // re-PR'd from here. The "Attach" CTA bridges back to
                // a working session via `skoga attach` — but only for
                // states the daemon will accept (`.canAttach`:
                // exited/PrMerged/PrClosed, whose worktrees still
                // exist). Done/Killed have torn-down worktrees so
                // their footer collapses to just the read-only label
                // + (if landed) the PR link, rather than offering a
                // button we know will fail.
                Text("Read-only — session is closed")
                    .font(SkogaFont.small(11.5))
                    .foregroundStyle(p.inkMute)
                if let url = agent.prUrl {
                    GhostPillButton(label: "View PR on GitHub", icon: .github) {
                        openPRURL(url)
                    }
                }
                if agent.status.canAttach {
                    AttachButton(busy: attaching) {
                        Task { await attach() }
                    }
                }
            } else {
                PushButton(busy: pushing) {
                    pushBranch()
                }
                if let url = agent.prUrl {
                    GhostPillButton(label: "View PR on GitHub", icon: .github) {
                        openPRURL(url)
                    }
                } else {
                    PrimaryButton(label: "Open as PR", icon: .github, tint: .forest) {
                        modal.prAgentId = agent.id
                    }
                }
            }
        }
        .padding(.horizontal, Tokens.Pad.viewX)
        .padding(.vertical, 12)
        .background(p.paper)
        .overlay(alignment: .top) { Hairline() }
    }

    /// Open the PR's GitHub URL in the user's default browser. Mock seed
    /// uses "#" as a placeholder — skip the open when we'd otherwise hand
    /// `NSWorkspace` a garbage URL.
    private func openPRURL(_ url: String) {
        guard url != "#", let parsed = URL(string: url) else { return }
        NSWorkspace.shared.open(parsed)
    }

    /// Shell `skoga push <id>` via the daemon client and surface the
    /// outcome as a toast. Mirrors the PR-submit pattern: toast that work
    /// is in flight up front, run the push in an unstructured `@MainActor`
    /// task, and report success or failure via a follow-up toast. The
    /// user shouldn't have to sit through the round-trip — a fresh push
    /// to a slow remote can take many seconds.
    ///
    /// `pushing` still gates re-entry so a rapid second click can't spawn
    /// a parallel CLI subprocess against the same worktree.
    private func pushBranch() {
        guard !pushing else { return }
        pushing = true

        let agentBranch = agent.branch
        let agentId = agent.id
        let client = daemon.client
        let modal = modal

        modal.showToast("Pushing \(agentBranch) to remote…")

        Task { @MainActor in
            defer { pushing = false }
            do {
                try await client.pushBranch(for: agentId)
                modal.showToast("Pushed \(agentBranch) to remote.")
            } catch {
                modal.showToast("Push failed: \(error.localizedDescription)", duration: 8)
            }
        }
    }

    /// Revive a terminal session via `coordinator.attach`. The double-fire
    /// guard matches `pushBranch` — the daemon's worktree fork + adapter
    /// relaunch takes a moment, and a rapid second click would queue a
    /// second `session.attach` against an id that's already mid-revive.
    private func attach() async {
        guard !attaching else { return }
        attaching = true
        defer { attaching = false }
        await coordinator.attach(agentId: agent.id)
    }
}

/// Footer CTA for reviving a terminal session — same shape as `PushButton`
/// so the two read as a coordinated pair when the user is reading the
/// closing-session footer. Swaps the icon for a spinner while the
/// `session.attach` RPC is in flight (the daemon's worktree fork is the
/// slow step, not the RPC).
private struct AttachButton: View {
    @Environment(\.palette) private var p
    let busy: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .progressViewStyle(.circular)
                } else {
                    Image(skoga: .attach).skogaIconSize(13)
                }
                Text(busy ? "Reattaching…" : "Attach")
                    .font(SkogaFont.smallMedium(11.5))
            }
            .foregroundStyle(busy ? p.ink2 : .white)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(busy ? p.paper3 : (hovering ? p.forest.opacity(0.9) : p.forest))
                    .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
            )
            .opacity(busy ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onHover { hovering = $0 }
    }
}

// MARK: – Save-as-permanent prompt

/// Non-blocking "you've worked with Astrid 3 times — save as permanent
/// agent?" banner. Sits between the transcript surface and the actions
/// footer so it's visible while the user reviews the just-finished work
/// without stealing focus from the running TUI. Renders to nothing
/// when [`NamedAgentsState.shouldPromptSaveAsPermanent`] returns false
/// — that gate folds in the threshold check, the "already permanent"
/// suppression, and the per-session dismissal memory.
private struct SavePermanentAgentBanner: View {
    @Environment(\.palette) private var p
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(NamedAgentsState.self) private var namedAgents
    let agent: Agent

    @State private var saving = false

    var body: some View {
        if namedAgents.shouldPromptSaveAsPermanent(for: agent) {
            // The successful-runs counter drives the headline — Astrid's
            // saved threshold is 3 today, but the count keeps incrementing
            // past it and we want the copy to reflect what the user has
            // actually done ("4 times" reads honestly; "3+ times" reads
            // like a placeholder).
            let count = namedAgents.successfulRunsByName[agent.name] ?? NamedAgentsState.saveAsPermanentThreshold
            HStack(spacing: 10) {
                Image(skoga: .spark)
                    .skogaIconSize(14)
                    .foregroundStyle(p.forest)
                VStack(alignment: .leading, spacing: 1) {
                    Text("You've worked with \(agent.name) \(count) times.")
                        .font(SkogaFont.bodyMedium(12.5))
                        .foregroundStyle(p.ink)
                    Text("Save as a permanent agent to pin \(agent.name) to your guild.")
                        .font(SkogaFont.small(11.5))
                        .foregroundStyle(p.inkMute)
                }
                Spacer(minLength: 0)
                Button("Dismiss") {
                    namedAgents.dismissPrompt(for: agent.id)
                }
                .buttonStyle(.plain)
                .font(SkogaFont.smallMedium(11.5))
                .foregroundStyle(p.inkMute)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                        .fill(p.paper)
                        .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                )

                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: 6) {
                        if saving {
                            ProgressView()
                                .controlSize(.small)
                                .progressViewStyle(.circular)
                        } else {
                            Image(skoga: .plus).skogaIconSize(12)
                        }
                        Text(saving ? "Saving…" : "Save \(agent.name)")
                            .font(SkogaFont.bodyMedium(12))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .fill(p.forest)
                    )
                    .opacity(saving ? 0.7 : 1)
                }
                .buttonStyle(.plain)
                .disabled(saving)
            }
            .padding(.horizontal, Tokens.Pad.viewX)
            .padding(.vertical, 10)
            .background(p.forestSoft)
            .overlay(alignment: .top) { Hairline() }
        }
    }

    /// Guard the click so a double-tap can't fire two `agents.create`
    /// calls. The coordinator's own refresh on success makes the banner
    /// disappear (the new permanent agent enters `namedAgents.agents`
    /// and `shouldPromptSaveAsPermanent` returns false on the next
    /// observation cycle) — but if the second click races the
    /// in-flight create, two daemon-side records could land.
    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        await coordinator.saveAsPermanentAgent(from: agent)
    }
}

/// Small companion to the existing `GhostPillButton` that swaps its icon
/// for an inline `ProgressView` while a push is in flight. Lives next to
/// the PR CTA in the footer and shares the same pill shape so the two
/// CTAs read as a coordinated pair.
private struct PushButton: View {
    @Environment(\.palette) private var p
    let busy: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .progressViewStyle(.circular)
                } else {
                    Image(skoga: .push).skogaIconSize(12)
                }
                Text(busy ? "Pushing…" : "Push commits")
                    .font(SkogaFont.smallMedium(11.5))
            }
            .foregroundStyle(hovering && !busy ? p.ink : p.ink2)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(hovering && !busy ? p.paper3 : p.paper)
                    .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
            )
            .opacity(busy ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onHover { hovering = $0 }
    }
}

// MARK: – Side panel

private struct ConvSidePanel: View {
    @Environment(\.palette) private var p
    @Environment(\.openSettings) private var openSettings
    @Environment(ModalState.self) private var modal
    @Environment(DaemonClientHolder.self) private var daemon
    let agent: Agent
    let timeline: [TimelineEntry]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                runDetailsBlock
                activityBlock
                actionsBlock
                Spacer(minLength: 0)
            }
        }
        .background(p.paper2)
    }

    private var runDetailsBlock: some View {
        block(title: "Run details") {
            VStack(spacing: 5) {
                kv("repo", agent.repo, mono: true)
                kv("branch", agent.branch, mono: true)
                kv("base", baseLabel, mono: true)
                kv("model", agent.model, mono: true)
                kv("runtime", agent.runtime, mono: true)
                kv("spend", String(format: "$%.2f · %dk tok", agent.cost, agent.tokens / 1000), mono: true)
                kv("commits", "\(agent.commits)", mono: true)
                kv("files", "\(agent.files)", mono: true)
            }
        }
    }

    /// `main · a91f3d2` when the daemon resolved a base SHA at session
    /// create, just `main` otherwise. The seven-char prefix matches git's
    /// `--short` default so the value lines up with what `git log` shows
    /// when the user pivots into the worktree to investigate.
    private var baseLabel: String {
        guard let sha = agent.baseSha, !sha.isEmpty else { return agent.base }
        return "\(agent.base) · \(sha.prefix(7))"
    }

    private var activityBlock: some View {
        block(title: "Activity") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(timeline) { entry in
                    TimelineRow(entry: entry)
                }
            }
            .padding(.leading, 6)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(p.rule)
                    .frame(width: Tokens.Hairline.width)
                    .padding(.vertical, 6)
                    .padding(.leading, 10)
            }
        }
    }

    private var actionsBlock: some View {
        block(title: "Quick actions") {
            VStack(spacing: 6) {
                if agent.status.isTerminal {
                    // Worktree-bound actions don't make sense once the
                    // worktree's been torn down; "Ping me when done" is
                    // nonsense for an already-terminal session. Only the
                    // GitHub link survives, and only if the agent left
                    // a PR behind.
                    if let url = agent.prUrl {
                        quickAction(label: "View PR on GitHub", icon: .github) {
                            openPRURLFromSidePanel(url)
                        }
                    } else {
                        Text("No actions for closed sessions.")
                            .font(SkogaFont.small(11.5))
                            .foregroundStyle(p.inkMute)
                            .padding(.vertical, 4)
                    }
                } else {
                    quickAction(label: "View commits on GitHub", icon: .github) {
                        Task { await openCommitsOnGitHub() }
                    }
                    quickAction(label: "Drop into editor (worktree)", icon: .doc) {
                        Task { await dropIntoEditor() }
                    }
                    quickAction(label: "Ping me when done", icon: .watch) {}
                }
            }
        }
    }

    /// Side-panel-local helper so the read-only "View PR on GitHub"
    /// quick action shares the same URL-validation shape as the
    /// footer's button. Mock seeds use "#" as a placeholder; skip the
    /// open when that's all we'd hand `NSWorkspace`.
    private func openPRURLFromSidePanel(_ url: String) {
        guard url != "#", let parsed = URL(string: url) else { return }
        NSWorkspace.shared.open(parsed)
    }

    /// Open `github.com/<owner>/<repo>/compare/<base>...<branch>` in the
    /// user's default browser. The origin remote is resolved daemon-side
    /// (`session.remote_url`) — see `GitHubCompareLauncher` for the
    /// github.com URL parsing.
    ///
    /// GitHub's compare page 404s (or claims no shared history) when the
    /// branch has never been pushed, and a sandboxed client can't cheaply
    /// probe the remote-tracking ref locally, so we always push first via
    /// `session.push` and only open once it succeeds. The push is
    /// idempotent — a redundant push is cheap; an unviewable compare page
    /// isn't. Off-happy-path:
    /// * remote isn't on github.com (or no `origin` at all) → toast.
    /// * remote lookup itself failed → surface the error as a toast.
    /// * `session.push` failed → toast the error, don't open.
    private func openCommitsOnGitHub() async {
        let remote: String?
        do {
            remote = try await daemon.client.remoteURL(for: agent.id)
        } catch {
            modal.showToast("Couldn't read the repo's remote: \(error.toastMessage)")
            return
        }
        let url: URL
        switch GitHubCompareLauncher.resolve(remoteURL: remote, base: agent.base, branch: agent.branch) {
        case .resolved(let resolved):
            url = resolved
        case .notGitHub:
            modal.showToast("This repo doesn't have a GitHub remote.")
            return
        case .failed(let message):
            modal.showToast(message)
            return
        }
        modal.showToast("Pushing \(agent.branch) to GitHub…")
        do {
            try await daemon.client.pushBranch(for: agent.id)
        } catch {
            modal.showToast("Push failed: \(error.localizedDescription)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Hand the agent's worktree to whichever editor the user picked in
    /// Settings → Editor, opening the agent's changed files as tabs
    /// alongside the workspace root.
    ///
    /// We try the daemon for the file list but tolerate it not knowing
    /// how — `changedFiles` returns nil against older daemons (no
    /// `session.changed_files` method), and a thrown error from a live
    /// daemon shouldn't block the user from still getting the folder
    /// open. Either path gracefully degrades to "folder only" rather
    /// than failing the action outright.
    ///
    /// Off-happy-path:
    /// * daemon didn't surface a worktree → toast + bail.
    /// * user picked `custom` but never filled the command → toast and
    ///   open Settings so they can finish the setup.
    /// * launch fails (`/usr/bin/open` throws) → surface the underlying
    ///   error as a toast.
    private func dropIntoEditor() async {
        let choice = EditorPrefs.readSelected()
        let custom = EditorPrefs.readCustomCommand()
        let files: [String] = await {
            // Skip the round-trip for editors that can't use a file list
            // anyway — Finder/Xcode/Terminal ignore it.
            guard choice.supportsFileTabs else { return [] }
            do {
                return try await daemon.client.changedFiles(for: agent.id) ?? []
            } catch {
                return []
            }
        }()
        let result = await EditorLauncher.open(
            worktree: agent.hostWorktree,
            choice: choice,
            customCommand: custom,
            changedFiles: files
        )
        switch result {
        case .opened(let used):
            // Don't claim "with N files" when N is 0 — the toast would
            // read confusingly on a fresh session.
            let visibleFiles = used.supportsFileTabs ? min(files.count, EditorLauncher.maxFileTabs) : 0
            let suffix = visibleFiles > 0 ? " with \(visibleFiles) changed file\(visibleFiles == 1 ? "" : "s")" : ""
            modal.showToast("Opening worktree in \(used.displayName)\(suffix)…")
        case .noWorktree:
            modal.showToast("No worktree path for this session yet.")
        case .unconfigured:
            modal.showToast("Set a custom editor command in Settings → Editor.")
            openSettings()
        case .failed(let message):
            modal.showToast(message)
        }
    }

    @ViewBuilder
    private func block<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(SkogaFont.monoTiny(9.5))
                .tracking(0.95)
                .foregroundStyle(p.inkFaint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func kv(_ key: String, _ value: String, mono: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(SkogaFont.monoSmall(10.5))
                .foregroundStyle(p.inkFaint)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(mono ? SkogaFont.monoSmall(10.5) : SkogaFont.small(11.5))
                .foregroundStyle(p.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func quickAction(label: String, icon: SkogaIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(skoga: icon).skogaIconSize(12)
                Text(label)
                    .font(SkogaFont.small(11.5))
                Spacer()
            }
            .foregroundStyle(p.ink2)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(p.paper)
                    .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TimelineRow: View {
    @Environment(\.palette) private var p
    let entry: TimelineEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            dot.frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.when)
                    .font(SkogaFont.monoTiny(9.5))
                    .foregroundStyle(p.inkFaint)
                Text(entry.what)
                    .font(SkogaFont.small(11.5))
                    .foregroundStyle(p.ink2)
                    .lineSpacing(11.5 * 0.4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var dot: some View {
        Circle()
            .fill(dotFill)
            .frame(width: 7, height: 7)
            .overlay(
                Circle().stroke(dotBorder, lineWidth: Tokens.Hairline.width)
            )
            .padding(.top, 4)
    }

    private var dotFill: Color {
        switch entry.kind {
        case .commit:  p.forest
        case .tool:    p.amber
        case .thought: p.paper
        case .state:   p.dusk
        }
    }
    private var dotBorder: Color {
        switch entry.kind {
        case .commit:  p.forest
        case .tool:    p.amber
        case .thought: p.ruleHard
        case .state:   p.dusk
        }
    }
}

// MARK: – Small button styles

private struct PrimaryButton: View {
    @Environment(\.palette) private var p
    let label: String
    let icon: SkogaIcon?
    enum Tint { case ink, forest, ember }
    let tint: Tint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(skoga: icon).skogaIconSize(12) }
                Text(label).font(SkogaFont.bodyMedium(12))
            }
            .padding(.horizontal, 14)
            .frame(height: 28)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(bg)
            )
        }
        .buttonStyle(.plain)
    }

    private var bg: Color {
        switch tint {
        case .ink:    p.ink
        case .forest: p.forest
        case .ember:  p.ember
        }
    }
}

private struct GhostPillButton: View {
    @Environment(\.palette) private var p
    let label: String
    let icon: SkogaIcon
    var color: Color? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(skoga: icon).skogaIconSize(12)
                Text(label).font(SkogaFont.smallMedium(11.5))
            }
            .foregroundStyle(color ?? (hovering ? p.ink : p.ink2))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(hovering ? p.paper3 : p.paper)
                    .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct TextLink: View {
    @Environment(\.palette) private var p
    let label: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(SkogaFont.smallMedium(11.5))
                .foregroundStyle(hovering ? p.ink : p.inkMute)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering ? p.paper3 : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
