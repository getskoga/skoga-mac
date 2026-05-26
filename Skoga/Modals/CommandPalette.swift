import SwiftUI

struct CommandPalette: View {
    @Environment(\.palette) private var p
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(RosterState.self) private var roster
    @Environment(ModalState.self) private var modal
    @Environment(\.openSettings) private var openSettings

    @State private var query: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            p.modalScrim
                .ignoresSafeArea()
                .onTapGesture { close() }

            modal
                .padding(.top, 80)
        }
    }

    private var modal: some View {
        VStack(spacing: 0) {
            searchRow
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !filteredCommands.isEmpty {
                        sectionHeader("Commands")
                        ForEach(filteredCommands, id: \.id) { c in
                            commandRow(label: c.label, icon: c.icon) { c.action() }
                        }
                    }
                    if !filteredAgents.isEmpty {
                        sectionHeader("Agents").padding(.top, 4)
                        ForEach(filteredAgents) { a in
                            agentRow(a)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 380)
        }
        .frame(width: 540)
        .background(p.paper)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.modal)
                .stroke(p.ruleHard, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.modal))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 20)
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(skoga: .cmd).skogaIconSize(16).foregroundStyle(p.inkMute)
            TextField("Find agent, task, repo, command…", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
                .font(SkogaFont.body(15))
                .foregroundStyle(p.ink)
                .onSubmit { runFirstMatch() }
            Text("esc")
                .font(SkogaFont.monoTiny(10))
                .foregroundStyle(p.inkFaint)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Hairline() }
        .onAppear { focused = true }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(SkogaFont.monoTiny(9.5))
                .tracking(0.95)
                .foregroundStyle(p.inkFaint)
            Hairline()
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 4)
    }

    @ViewBuilder
    private func commandRow(label: String, icon: SkogaIcon, action: @escaping () -> Void) -> some View {
        HoverRow {
            HStack(spacing: 10) {
                Image(skoga: icon).skogaIconSize(13).foregroundStyle(p.ink2)
                Text(label)
                    .font(SkogaFont.body(13))
                    .foregroundStyle(p.ink)
                Spacer()
            }
        } action: { action(); close() }
    }

    @ViewBuilder
    private func agentRow(_ a: Agent) -> some View {
        HoverRow {
            HStack(spacing: 10) {
                PulseDot(status: a.status)
                Text(a.name)
                    .font(SkogaFont.body(13))
                    .foregroundStyle(p.ink)
                Text(a.task.prefix(50) + (a.task.count > 50 ? "…" : ""))
                    .font(SkogaFont.small(12))
                    .foregroundStyle(p.inkFaint)
                    .lineLimit(1)
                Spacer()
            }
        } action: {
            close()
            coordinator.openConversation(for: a.id)
        }
    }

    // MARK: – Filtering

    struct Command: Identifiable {
        let id: String
        let label: String
        let icon: SkogaIcon
        let action: () -> Void
    }

    private var allCommands: [Command] {
        [
            .init(id: "roster", label: "Go to Roster", icon: .roster) {
                coordinator.navigate(to: .roster)
            },
            .init(id: "dispatch", label: "Dispatch new run", icon: .bolt) {
                coordinator.navigate(to: .dispatch)
            },
            .init(id: "review", label: "Go to Review", icon: .review) {
                coordinator.navigate(to: .review)
            },
            .init(id: "telemetry", label: "Go to Telemetry", icon: .telemetry) {
                coordinator.navigate(to: .telemetry)
            },
            .init(id: "settings", label: "Open Settings", icon: .settings) {
                openSettings()
            },
        ]
    }

    private var filteredCommands: [Command] {
        let q = query.lowercased()
        if q.isEmpty { return allCommands }
        return allCommands.filter { $0.label.lowercased().contains(q) }
    }

    private var filteredAgents: [Agent] {
        let q = query.lowercased()
        let xs = roster.agents
        if q.isEmpty { return Array(xs.prefix(8)) }
        return xs.filter {
            $0.name.lowercased().contains(q) ||
            $0.task.lowercased().contains(q) ||
            $0.repo.lowercased().contains(q)
        }.prefix(8).map { $0 }
    }

    private func runFirstMatch() {
        if let c = filteredCommands.first {
            c.action(); close(); return
        }
        if let a = filteredAgents.first {
            close()
            coordinator.openConversation(for: a.id)
        }
    }

    private func close() {
        modal.commandPaletteOpen = false
        query = ""
    }
}

// MARK: – Hover row

private struct HoverRow<Content: View>: View {
    @Environment(\.palette) private var p
    let content: () -> Content
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering ? p.paper2 : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, 8)
    }
}
