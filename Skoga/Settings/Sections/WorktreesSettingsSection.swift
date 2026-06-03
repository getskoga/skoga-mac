import AppKit
import SwiftUI

/// Settings → Worktrees. Where the daemon checks out per-agent worktrees
/// and what the on-merge cleanup behavior is. The Mac doesn't own these
/// settings (the daemon resolves the root from `SKOGA_HOME` and runs the
/// cleanup itself), so this panel is information + action — show where
/// the directory lives, list the active worktrees we know about from the
/// roster, reveal them in Finder. No fake "configure cleanup" toggles
/// that don't talk to anything; the daemon would just ignore them.
struct WorktreesSettingsSection: View {
    @Environment(\.palette) private var p
    @Environment(RosterState.self) private var roster
    @Environment(DaemonClientHolder.self) private var daemon
    @Environment(ModalState.self) private var modal

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            rootCard
            activeWorktreesCard
            cleanupCard
        }
    }

    // MARK: – Resolved path

    /// Live worktree paths, used to infer the daemon's truthful sessions
    /// root. `host_worktree` is the daemon's own resolved path, so its
    /// parent is the directory the daemon writes into — by definition
    /// authoritative even when the Mac app's env doesn't agree.
    private var liveWorktreePaths: [String] {
        roster.agents.compactMap { $0.hostWorktree }.filter { !$0.isEmpty }
    }

    private var inferredRoot: URL? {
        WorktreesInfo.inferredRoot(from: liveWorktreePaths)
    }

    /// What the panel displays + reveals. Prefers the daemon-derived
    /// path; falls back to the env-derived guess when no active session
    /// has a worktree.
    private var displayedRoot: URL {
        inferredRoot ?? WorktreesInfo.envDerivedRoot
    }

    /// True when the daemon's actual root differs from the Mac app's
    /// env-derived guess. Triggers a "MAC ENV MISMATCH" pill so the user
    /// knows their shell `SKOGA_HOME` export isn't reaching the GUI app
    /// (the daemon is correct; the Mac app's env is the stale side).
    private var envMismatch: Bool {
        guard let inferred = inferredRoot else { return false }
        return inferred.standardizedFileURL != WorktreesInfo.envDerivedRoot.standardizedFileURL
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(skoga: SettingsSectionID.worktrees.icon).skogaIconSize(15)
                    .foregroundStyle(p.ink2)
                Text(SettingsSectionID.worktrees.title)
                    .font(SkogaFont.serifTitle(24))
                    .foregroundStyle(p.ink)
            }
            Text(SettingsSectionID.worktrees.blurb)
                .font(SkogaFont.body(13))
                .foregroundStyle(p.inkMute)
                .lineSpacing(13 * 0.45)
                .frame(maxWidth: 540, alignment: .leading)
        }
    }

    // MARK: – Worktree root

    private var rootCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    SettingsCardLabel("ROOT DIRECTORY")
                    Spacer()
                    pathSourcePill
                }

                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                        Image(skoga: .branch).skogaIconSize(13).foregroundStyle(p.ink2)
                    }
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Where Skoga checks out worktrees")
                            .font(SkogaFont.bodyMedium(13))
                            .foregroundStyle(p.ink)
                        Text(rootDescription)
                            .font(SkogaFont.body(12))
                            .foregroundStyle(p.inkMute)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(displayedRoot.path)
                            .font(SkogaFont.mono(11.5))
                            .foregroundStyle(p.ink2)
                            .textSelection(.enabled)
                            .padding(.top, 4)

                        HStack(spacing: 8) {
                            Button {
                                let outcome = WorktreesInfo.revealInFinder(path: displayedRoot.path)
                                if outcome == .missing {
                                    modal.showToast("Sessions root doesn't exist yet — dispatch an agent and try again.")
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(skoga: .doc).skogaIconSize(11)
                                    Text("Reveal in Finder").font(SkogaFont.bodyMedium(12))
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .foregroundStyle(p.ink2)
                                .background(
                                    RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                                        .fill(p.paper)
                                        .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!WorktreesInfo.directoryExists(at: displayedRoot))
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Source-of-truth pill for the path on screen. Three cases:
    /// - `MAC ENV MISMATCH` (red-ish) when the daemon's actual root
    ///   differs from what `SKOGA_HOME` (or its absence) would resolve
    ///   to on the Mac side — this happens when the user set the env
    ///   var in their shell rc but launches Skoga.app from the Dock,
    ///   which doesn't inherit shell exports. The displayed path is the
    ///   daemon's; the env-derived guess is shown in the description.
    /// - `SKOGA_HOME OVERRIDE` (dusk) when env var is set and matches
    ///   the daemon's root — non-default install but everything agrees.
    /// - `ENV-DERIVED GUESS` (amber) when no active session exists, so
    ///   the panel is showing the env-derived path without confirmation.
    @ViewBuilder
    private var pathSourcePill: some View {
        if envMismatch {
            pill("MAC ENV MISMATCH", fg: p.ember, bg: p.emberSoft)
        } else if WorktreesInfo.honoringEnvOverride {
            pill("SKOGA_HOME OVERRIDE", fg: p.dusk, bg: p.duskSoft)
        } else if inferredRoot == nil {
            pill("ENV-DERIVED GUESS", fg: p.amber, bg: p.amberSoft)
        }
    }

    private func pill(_ label: String, fg: Color, bg: Color) -> some View {
        Text(label)
            .font(SkogaFont.monoTiny(9.5))
            .tracking(0.8)
            .foregroundStyle(fg)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                    .fill(bg.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                    .stroke(fg.opacity(0.45), lineWidth: Tokens.Hairline.width)
            )
    }

    private var rootDescription: String {
        if envMismatch {
            return "Path below is the daemon's actual sessions root, taken from an active worktree. Your shell-exported `SKOGA_HOME` isn't visible to the GUI app — macOS Dock/Finder launches don't inherit shell rc env. Mac-derived guess: \(WorktreesInfo.envDerivedRoot.path)"
        }
        if inferredRoot == nil {
            return "Path below is the Mac app's guess (`SKOGA_HOME`, falling back to `~/.skoga`). No active sessions to confirm against the daemon — dispatch an agent to verify."
        }
        return "Each agent gets its own `<session-id>/` subfolder here. The daemon owns the contents — manual edits inside a session's worktree are visible to its agent on the next command."
    }

    // MARK: – Active worktrees list

    /// Live list from `RosterState`. Anything currently in `.running`,
    /// `.blocked`, `.prOpen`, `.idle`, or `.stopping` should have a
    /// worktree on disk; terminal sessions (.done, .exited, etc.) have
    /// had theirs auto-cleaned and are hidden — surfacing them with a
    /// dead path would just be misleading.
    private var activeWorktreesCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    SettingsCardLabel("ACTIVE WORKTREES")
                    Spacer()
                    Text("\(activeWorktrees.count)")
                        .font(SkogaFont.monoTiny(9.5))
                        .tracking(0.8)
                        .foregroundStyle(p.inkMute)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                        )
                }

                if activeWorktrees.isEmpty {
                    emptyActiveRow
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(activeWorktrees.enumerated()), id: \.element.id) { idx, agent in
                            ActiveWorktreeRow(agent: agent) { path in
                                let outcome = WorktreesInfo.revealInFinder(path: path)
                                if outcome == .missing {
                                    modal.showToast("\(agent.name)'s worktree is gone — the daemon likely cleaned it up.")
                                }
                            }
                            if idx != activeWorktrees.count - 1 {
                                Hairline().padding(.vertical, 6)
                            }
                        }
                    }
                }
            }
        }
    }

    private var activeWorktrees: [Agent] {
        roster.agents
            .filter { !$0.status.isTerminal && $0.hostWorktree != nil }
            .sorted { $0.hostWorktree! < $1.hostWorktree! }
    }

    private var emptyActiveRow: some View {
        Text(daemon.isMock
             ? "Mock mode is on — the seeded roster doesn't ship with worktree paths so this list stays empty. Connect to a real daemon to see live worktrees."
             : "No active sessions. Dispatch an agent and a `<session-id>/` folder will appear under the root above.")
            .font(SkogaFont.body(12))
            .foregroundStyle(p.inkMute)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: – Cleanup policy

    /// The daemon decides when to delete a worktree, not the Mac. Document
    /// the actual behavior so the user can predict what disappears and
    /// when, instead of inferring from observation.
    private var cleanupCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel("CLEANUP POLICY")
                    .padding(.bottom, 14)

                CleanupRow(
                    icon: .check,
                    title: "Auto-deleted after ship",
                    detail: "Once a session moves to `shipped` — either because its PR merged, was closed, or you ran `skoga ship` from the CLI — the daemon removes the linked worktree. The git branch on the host repo is kept so you can rebase against the history."
                )
                Hairline().padding(.vertical, 12)
                CleanupRow(
                    icon: .alert,
                    title: "Kept on crash / kill",
                    detail: "A session that exits unexpectedly leaves its worktree on disk so you can inspect what happened. Use Privacy & data → Clear local state to wipe everything, or delete an individual `<session-id>/` folder yourself."
                )
                Hairline().padding(.vertical, 12)
                CleanupRow(
                    icon: .shield,
                    title: "Disk quotas: not enforced",
                    detail: "The daemon doesn't cap total worktree disk usage today. If you run many agents against large repos, periodically Reveal the root above and trim stale entries by hand. A quota guardrail is on the roadmap."
                )
            }
        }
    }
}

// MARK: – Active worktree row

private struct ActiveWorktreeRow: View {
    @Environment(\.palette) private var p
    let agent: Agent
    /// Closure so the parent can surface a toast on `.missing` —
    /// `ModalState` is reached through the parent's environment; routing
    /// it through here would couple the row to the toast layer.
    let onReveal: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(agent.name)
                        .font(SkogaFont.bodyMedium(13))
                        .foregroundStyle(p.ink)
                    StatusDot(status: agent.status)
                    Text(agent.status.label)
                        .font(SkogaFont.monoTiny(9.5))
                        .tracking(0.8)
                        .foregroundStyle(p.inkMute)
                }
                if let path = agent.hostWorktree {
                    Text(path)
                        .font(SkogaFont.mono(11))
                        .foregroundStyle(p.inkMute)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let path = agent.hostWorktree {
                Button {
                    onReveal(path)
                } label: {
                    HStack(spacing: 4) {
                        Image(skoga: .doc).skogaIconSize(10)
                        Text("Reveal").font(SkogaFont.bodyMedium(11.5))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .foregroundStyle(p.ink2)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .fill(p.paper)
                            .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct StatusDot: View {
    @Environment(\.palette) private var p
    let status: AgentStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }

    private var color: Color {
        switch status {
        case .running:  p.forest
        case .blocked:  p.ember
        case .prOpen:   p.dusk
        case .stopping: p.amber
        case .idle:     p.inkFaint
        default:        p.inkFaint
        }
    }
}

// MARK: – Cleanup row

private struct CleanupRow: View {
    @Environment(\.palette) private var p
    let icon: SkogaIcon
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                Image(skoga: icon).skogaIconSize(13).foregroundStyle(p.ink2)
            }
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(p.rule, lineWidth: Tokens.Hairline.width)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SkogaFont.bodyMedium(13))
                    .foregroundStyle(p.ink)
                Text(detail)
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: – Filesystem helpers

/// Resolves the worktree-root path the daemon uses (`$SKOGA_HOME/sessions`,
/// falling back to `~/.skoga/sessions`) and exposes the Finder reveal
/// helpers used by the panel. Lives outside the view so the path
/// resolution is testable and consistent with `URL.skogaSocket`.
enum WorktreesInfo {
    /// True iff `$SKOGA_HOME` is set and non-empty — the panel flips a
    /// pill on when this is true so the user knows the path on screen
    /// isn't `~/.skoga/`.
    static var honoringEnvOverride: Bool {
        guard let v = ProcessInfo.processInfo.environment["SKOGA_HOME"] else { return false }
        return !v.isEmpty
    }

    /// Env-derived sessions root (`$SKOGA_HOME/sessions`, falling back to
    /// `~/.skoga/sessions`). Note: macOS GUI launches (Dock/Finder) do
    /// **not** inherit shell-exported env, so a `SKOGA_HOME` set in
    /// `.zshrc` is invisible to this resolver but visible to a daemon
    /// launched from a terminal. Treat this as a guess; prefer
    /// `effectiveRoot(from:)` when active worktrees are available.
    static var envDerivedRoot: URL {
        let env = ProcessInfo.processInfo.environment
        let home: URL
        if let override = env["SKOGA_HOME"], !override.isEmpty {
            home = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".skoga")
        }
        return home.appendingPathComponent("sessions")
    }

    /// Daemon-truthful sessions root, derived from the parent directory
    /// of any active session's worktree. The daemon's own path resolver
    /// wrote those paths, so this side-steps the GUI-launch env gap. Nil
    /// when no live agent has a worktree path — caller falls back to
    /// `envDerivedRoot` and the UI flags the resulting path as a guess.
    static func inferredRoot(from worktreePaths: [String]) -> URL? {
        guard let raw = worktreePaths.first, !raw.isEmpty else { return nil }
        let expanded = (raw as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).deletingLastPathComponent()
    }

    /// Outcome of a Finder-reveal attempt. `.opened` confirms Finder
    /// actually surfaced the path; `.missing` means the path is gone
    /// (e.g. daemon already cleaned up a stopping session's worktree)
    /// — the caller decides whether to toast or just no-op.
    enum RevealOutcome: Equatable {
        case opened
        case missing
    }

    /// Reveals a path in Finder iff it exists. Returns `.missing` when
    /// the path is absent — explicitly does NOT fall back to opening the
    /// parent, which for a worktree like `<root>/<id>/` would surface
    /// the entire sessions root with every sibling listed. The caller
    /// surfaces a toast so the user knows why nothing opened.
    @MainActor
    @discardableResult
    static func revealInFinder(path: String) -> RevealOutcome {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        guard FileManager.default.fileExists(atPath: expanded) else {
            return .missing
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return .opened
    }

    /// Checks whether a sessions-root URL exists as a directory. Used by
    /// the panel to decide whether to enable the Reveal button.
    static func directoryExists(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }
}
