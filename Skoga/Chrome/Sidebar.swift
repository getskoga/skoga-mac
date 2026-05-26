import SwiftUI

struct Sidebar: View {
    @Environment(\.palette) private var p
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(RosterState.self) private var roster
    @Environment(ModalState.self) private var modal

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

            NavSection(title: "Guild · \(roster.agents.count)")
            ForEach(roster.agents.prefix(8)) { agent in
                guildRow(agent)
            }
            if roster.agents.count > 8 {
                HStack(spacing: 10) {
                    Color.clear.frame(width: 14, height: 14)
                    Text("+\(roster.agents.count - 8) more")
                        .font(SkogaFont.body(12.5))
                        .foregroundStyle(p.inkFaint)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
            }

            Spacer()
            footer
        }
        .frame(width: Tokens.sidebarWidth, alignment: .leading)
        .background(p.paper2)
        .overlay(alignment: .trailing) { Hairline(axis: .vertical) }
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
                    .frame(maxWidth: 130, alignment: .trailing)
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
