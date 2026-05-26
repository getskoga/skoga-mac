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
    /// (`.exited`, `.done`, `.prOpen`) omit them — there's nothing left to
    /// pause and a kill would no-op on a process that's already gone.
    private var hasRunControls: Bool {
        guard agent.prUrl == nil else { return false }
        switch agent.status {
        case .running, .blocked, .idle, .stopping: return true
        case .prOpen, .done, .exited:              return false
        }
    }
}

// MARK: – Actions footer

/// Footer sits below the embedded TUI and hosts the "Open as PR" CTA.
/// The CTA is decoupled from `agent.status` so the manager can always
/// reach for it; the only gating fact is whether a PR already exists for
/// this session (`prUrl != nil`) — when one does we swap the CTA for
/// "View PR on GitHub" so a second click doesn't try to re-land.
private struct ConvActionsFooter: View {
    @Environment(\.palette) private var p
    @Environment(ModalState.self) private var modal
    let agent: Agent

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
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
}

// MARK: – Side panel

private struct ConvSidePanel: View {
    @Environment(\.palette) private var p
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
                kv("base", "main · a91f3d2", mono: true)
                kv("model", agent.model, mono: true)
                kv("runtime", agent.runtime, mono: true)
                kv("spend", String(format: "$%.2f · %dk tok", agent.cost, agent.tokens / 1000), mono: true)
                kv("commits", "\(agent.commits)", mono: true)
                kv("files", "\(agent.files)", mono: true)
            }
        }
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
                quickAction(label: "View commits on GitHub", icon: .github)
                quickAction(label: "Drop into editor (worktree)", icon: .loop)
                quickAction(label: "Ping me when done", icon: .watch)
            }
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

    private func quickAction(label: String, icon: SkogaIcon) -> some View {
        Button {} label: {
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
        }
    }
    private var dotBorder: Color {
        switch entry.kind {
        case .commit:  p.forest
        case .tool:    p.amber
        case .thought: p.ruleHard
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
