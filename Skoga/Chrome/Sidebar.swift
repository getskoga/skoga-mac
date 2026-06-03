import SwiftUI

struct Sidebar: View {
    @Environment(\.palette) private var p
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(RosterState.self) private var roster
    @Environment(ModalState.self) private var modal
    @Environment(NamedAgentsState.self) private var namedAgents
    @AppStorage(AppearancePrefs.density) private var densityRaw: String = AppearancePrefs.Density.standard.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            wordmark
                .padding(.horizontal, Tokens.Pad.sidebarX)
                .padding(.bottom, 14)
                .padding(.top, 18)

            NavSection(title: "Cockpit")
            NavItem(icon: .roster,    label: "Roster",    count: "\(roster.counts.total)", active: modal.view == .roster) {
                coordinator.navigate(to: .roster)
            }
            NavItem(icon: .dispatch,  label: "Dispatch",  count: nil, active: modal.view == .dispatch) {
                coordinator.navigate(to: .dispatch)
            }
            NavItem(icon: .review,    label: "Review",    count: "\(roster.counts.prOpen)", active: modal.view == .review) {
                coordinator.navigate(to: .review)
            }
            NavItem(icon: .telemetry, label: "Telemetry", count: nil, active: modal.view == .telemetry) {
                coordinator.navigate(to: .telemetry)
            }
            NavItem(icon: .clock,     label: "History",   count: nil, active: modal.view == .history) {
                coordinator.navigate(to: .history)
            }

            NavSection(title: "Guild · \(roster.agents.count)")
            // Permanent agents pin to the top of the guild list, ordered
            // by `lastUsed` desc (same ordering as the daemon's
            // `agents.list` response). Clicking a pin opens the agent's
            // most recent live session if one is running, falls back to
            // a "no live session" hint otherwise — the user can still
            // dispatch a new run from the Dispatch screen.
            ForEach(pinnedNamedAgents) { named in
                permanentPinRow(named)
            }
            if !pinnedNamedAgents.isEmpty && !ephemeralGuildSlice.isEmpty {
                Hairline()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .opacity(0.6)
            }
            ForEach(ephemeralGuildSlice) { agent in
                guildRow(agent)
            }
            // "+N more" counts only ephemeral agents that didn't fit
            // under the cap — not the pinned ones above (which are
            // already shown as their own rows). Computing against
            // `roster.agents.count` would tell the user "+8 more"
            // when in fact 6 of those 8 are already on screen as
            // pins, making the overflow strip read as a phantom set
            // of hidden agents.
            if hiddenEphemeralCount > 0 {
                HStack(spacing: 10) {
                    Color.clear.frame(width: 14, height: 14)
                    Text("+\(hiddenEphemeralCount) more")
                        .font(SkogaFont.body(12.5))
                        .foregroundStyle(p.inkFaint)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
            }

            Spacer()
            footer
        }
        .frame(width: resolvedSidebarWidth, alignment: .leading)
        .background(p.paper2)
        .overlay(alignment: .trailing) { Hairline(axis: .vertical) }
    }

    /// Reads the Appearance density pref (Settings → Appearance) so the
    /// user's "compact" choice actually narrows the main chrome. Falls
    /// back to the standard width when the persisted value is missing or
    /// malformed.
    private var resolvedSidebarWidth: CGFloat {
        resolvedDensity.sidebarWidth
    }

    /// Trailing role/branch label cap. Shrinks in lockstep with the
    /// sidebar width so compact mode doesn't crush the agent name to a
    /// few characters by leaving the right-hand label claim unchanged.
    private var trailingLabelMaxWidth: CGFloat {
        resolvedDensity.sidebarTrailingLabelMaxWidth
    }

    private var resolvedDensity: AppearancePrefs.Density {
        AppearancePrefs.Density(rawValue: densityRaw) ?? .standard
    }

    private var wordmark: some View {
        HStack(spacing: 9) {
            SkogaGlyph(size: 22, color: p.forest)
            Text("Skoga")
                .font(SkogaFont.serifName(19))
                .foregroundStyle(p.ink)
            Text("α 0.7")
                .font(SkogaFont.monoTiny(9.5))
                .tracking(0.55)
                .foregroundStyle(p.inkMute)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.tiny).stroke(p.rule, lineWidth: Tokens.Hairline.width))
                .padding(.leading, 4)
        }
    }

    /// Permanent agents to render pinned at the top of the guild list.
    /// Daemon already orders `agents.list` by `last_used` desc, but the
    /// sidebar is fixed-height so we cap at 6 to leave breathing room
    /// for the ephemeral slice underneath. The cap is intentionally
    /// generous — a manager who has accumulated 10+ permanent agents
    /// is the audience we want to serve here, but the cockpit-strip
    /// "+N more" affordance handles the overflow case the same way it
    /// does for the ephemeral list.
    private var pinnedNamedAgents: [NamedAgent] {
        Array(namedAgents.agents.prefix(6))
    }

    /// Ephemeral agents shown below the permanent pins, capped so the
    /// total visible guild rows stay roughly at the pre-#33 count.
    /// `max(2, 8 - pinned)` keeps a sensible floor for repos with lots
    /// of ephemeral activity even when many permanent agents are pinned.
    ///
    /// Dedup against the pinned slice on two keys: explicit
    /// `namedAgentId` (set by the daemon at `session.create` when the
    /// caller routed through a permanent agent) and a fallback display-
    /// name match (covers sessions persisted before the daemon stamped
    /// the field, plus the coincidental case where an ephemeral
    /// session's deterministic Norse name happens to collide with a
    /// permanent agent's name).
    private var ephemeralGuildSlice: [Agent] {
        Array(nonPinnedRoster.prefix(ephemeralCap))
    }

    /// Roster sessions that don't belong to any pinned permanent agent.
    /// Surfaced as its own computed property so the "+N more" strip can
    /// count its overflow against the same set the visible slice came
    /// from, instead of against the full roster (which would include
    /// the pinned-and-already-shown sessions).
    private var nonPinnedRoster: [Agent] {
        let pinnedIds = Set(pinnedNamedAgents.map(\.id))
        let pinnedNames = Set(pinnedNamedAgents.map { $0.name.lowercased() })
        return roster.agents.filter { agent in
            if let id = agent.namedAgentId, pinnedIds.contains(id) { return false }
            return !pinnedNames.contains(agent.name.lowercased())
        }
    }

    private var ephemeralCap: Int { max(2, 8 - pinnedNamedAgents.count) }

    private var hiddenEphemeralCount: Int {
        max(0, nonPinnedRoster.count - ephemeralCap)
    }

    /// One row for a pinned permanent agent. Renders the same shape as
    /// `guildRow` with two tells: the avatar tile uses a forest accent
    /// (matches the Dispatch grid's permanent card), and the trailing
    /// label shows the saved role rather than a branch slug — there's
    /// no single "branch" for a permanent agent (each new dispatch
    /// gets a fresh worktree), so showing the role gives the eye
    /// something stable to scan for.
    private func permanentPinRow(_ named: NamedAgent) -> some View {
        Button {
            // Open the most recent live session for this permanent
            // agent if one exists — that's the obvious affordance from
            // a manager's perspective ("click Astrid → land in
            // Astrid's open conversation"). When no live session
            // exists, the click is a no-op rather than a navigation
            // to Dispatch, which would lose any in-progress form state
            // the user might have on screen.
            if let liveId = liveSessionId(for: named) {
                coordinator.openConversation(for: liveId)
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(p.forestSoft)
                    Image(skoga: .spark)
                        .skogaIconSize(8)
                        .foregroundStyle(p.forest)
                }
                .frame(width: 14, height: 14)

                Text(named.name)
                    .font(SkogaFont.body(12.5))
                    .foregroundStyle(p.ink2)
                Spacer(minLength: 0)
                Text(named.role.split(separator: " / ").first.map(String.init) ?? named.role)
                    .font(SkogaFont.monoSmall(10.5))
                    .foregroundStyle(p.inkMute)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: trailingLabelMaxWidth, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The session id of the most recent live (non-terminal) session
    /// dispatched against `named`. Prefers the explicit `namedAgentId`
    /// stamped by the daemon at `session.create`; falls back to a
    /// display-name match for sessions persisted by older daemons that
    /// don't carry the field yet, so the pin doesn't go dark during
    /// the rollout. Once the daemon ships the field universally, the
    /// name-fallback branch becomes dead code and can be dropped.
    private func liveSessionId(for named: NamedAgent) -> String? {
        let live = roster.agents.lazy.filter { !$0.status.isTerminal }
        if let match = live.first(where: { $0.namedAgentId == named.id }) {
            return match.id
        }
        return live.first { $0.name.caseInsensitiveCompare(named.name) == .orderedSame }?.id
    }

    private func guildRow(_ a: Agent) -> some View {
        Button {
            coordinator.openConversation(for: a.id)
        } label: {
            HStack(spacing: 10) {
                PulseDot(status: a.status).frame(width: 14, height: 14)
                Text(a.name)
                    .font(SkogaFont.body(12.5))
                    .foregroundStyle(p.ink2)
                Spacer(minLength: 0)
                Text(a.branchSlug)
                    .font(SkogaFont.monoSmall(10.5))
                    .foregroundStyle(p.inkMute)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: trailingLabelMaxWidth, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Text("M")
                .font(SkogaFont.serifName(11.5))
                .frame(width: 22, height: 22)
                .background(Circle().fill(p.paper4))
                .overlay(Circle().stroke(p.rule, lineWidth: Tokens.Hairline.width))
                .foregroundStyle(p.ink)
            VStack(alignment: .leading, spacing: 0) {
                Text("Mikael")
                    .font(SkogaFont.bodyMedium(11.5))
                    .foregroundStyle(p.ink2)
                Text("manager · plan: forge")
                    .font(SkogaFont.monoTiny(9.5))
                    .foregroundStyle(p.inkFaint)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Hairline() }
    }
}

// MARK: – Section header

struct NavSection: View {
    @Environment(\.palette) private var p
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(SkogaFont.monoTiny(10))
                .tracking(0.8)
                .foregroundStyle(p.inkFaint)
            Hairline()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}

// MARK: – Nav item

struct NavItem: View {
    @Environment(\.palette) private var p
    let icon: SkogaIcon
    let label: String
    let count: String?
    let active: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(skoga: icon)
                    .skogaIconSize(14)
                    .foregroundStyle(active ? p.forest : p.inkMute)
                Text(label)
                    .font(SkogaFont.body(12.5).weight(active ? .medium : .regular))
                    .foregroundStyle(active ? p.ink : p.ink2)
                Spacer(minLength: 0)
                if let count {
                    Text(count)
                        .font(SkogaFont.monoSmall(10.5))
                        .foregroundStyle(p.inkMute)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(activeBackground)
            .overlay(alignment: .leading) {
                if active {
                    Rectangle()
                        .fill(p.forest)
                        .frame(width: 2)
                        .padding(.vertical, 6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var activeBackground: some View {
        if active {
            RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.paper4).padding(.horizontal, 8)
        } else if hovering {
            RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.paper3).padding(.horizontal, 8)
        }
    }
}
