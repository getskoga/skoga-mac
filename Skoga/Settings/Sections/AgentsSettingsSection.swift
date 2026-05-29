import SwiftUI

/// Settings → Agents. Lists the user's permanent agents from
/// `NamedAgentsState` and lets them rename, retire, or rehome each
/// one. Reading is observation-driven (the slice updates on every 5s
/// `agents.list` poll); writes go through `AppCoordinator` so they
/// toast and trigger an immediate refresh.
///
/// When the registry is empty we lean on the section blurb instead of
/// dropping in a separate "empty state" card — there's no action the
/// user can take from this panel to create an agent (creation flows
/// through the conversation-footer prompt), so a dedicated empty card
/// would just be filler.
struct AgentsSettingsSection: View {
    @Environment(\.palette) private var p
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(NamedAgentsState.self) private var namedAgents

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if namedAgents.agents.isEmpty {
                emptyHint
            } else {
                ForEach(namedAgents.agents) { agent in
                    AgentRowCard(agent: agent)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(skoga: SettingsSectionID.agents.icon).skogaIconSize(15)
                    .foregroundStyle(p.ink2)
                Text(SettingsSectionID.agents.title)
                    .font(SkogaFont.serifTitle(24))
                    .foregroundStyle(p.ink)
            }
            Text("Permanent agents you've saved from the conversation footer. Rename, change a default model, or retire one — open sessions keep running on delete.")
                .font(SkogaFont.body(13))
                .foregroundStyle(p.inkMute)
                .lineSpacing(13 * 0.45)
                .frame(maxWidth: 540, alignment: .leading)
        }
    }

    private var emptyHint: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 6) {
                SettingsCardLabel("NO PERMANENT AGENTS YET")
                Text("After a few successful PR-merged runs with the same Skoga-named agent, the conversation footer offers to save that identity here.")
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: – Row card

/// One row in the Settings → Agents list. Renders the agent's name,
/// role, default model + repo, and the run telemetry; tap the body
/// to expand an inline editor for name + role + default model. The
/// editor stays inside the card (no sheet / modal) because the
/// edits are small and a modal here would steal the user out of
/// the at-a-glance settings flow.
private struct AgentRowCard: View {
    @Environment(\.palette) private var p
    @Environment(AppCoordinator.self) private var coordinator
    let agent: NamedAgent

    /// One row is in either "summary" or "editing" mode. Persisting
    /// the choice as `@State` (not `@AppStorage`) is intentional:
    /// reopening the Settings window should start every row collapsed
    /// — leaving one open across launches would surprise the user.
    @State private var editing = false
    @State private var draftName: String = ""
    @State private var draftRole: String = ""
    @State private var draftModel: String = ""
    @State private var draftRepo: String = ""
    @State private var confirmingDelete = false
    @State private var saving = false

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: editing ? 14 : 10) {
                summaryRow
                if editing {
                    editorBody
                } else {
                    metaRow
                }
            }
        }
    }

    /// Header row — avatar tile, name, and the expand/collapse pill.
    /// Stays present in both summary and editing modes so the user
    /// always has a single click to back out.
    private var summaryRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(p.forestSoft)
                Text(agent.initials)
                    .font(SkogaFont.serifName(14))
                    .foregroundStyle(p.ink)
            }
            .frame(width: 32, height: 32)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.forest, lineWidth: Tokens.Hairline.width))

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(SkogaFont.serifName(15))
                    .foregroundStyle(p.ink)
                Text(agent.role.uppercased())
                    .font(SkogaFont.monoTiny(10))
                    .tracking(0.6)
                    .foregroundStyle(p.inkFaint)
            }

            Spacer(minLength: 0)

            Button(editing ? "Done" : "Edit") {
                if editing {
                    editing = false
                } else {
                    draftName = agent.name
                    draftRole = agent.role
                    draftModel = agent.defaultModel ?? ""
                    draftRepo = agent.defaultRepo ?? ""
                    editing = true
                }
            }
            .buttonStyle(.plain)
            .font(SkogaFont.smallMedium(11.5))
            .foregroundStyle(p.ink2)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(p.paper)
                    .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
            )
        }
    }

    /// Collapsed-state meta strip — totals + default repo/model so a
    /// glance over the list answers "where does Astrid usually run,
    /// and how often."
    private var metaRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            kv("Total runs", "\(agent.totalRuns)")
            if let lastUsed = agent.lastUsed {
                kv("Last used", Self.lastUsedFormatter.localizedString(for: lastUsed, relativeTo: Date()))
            }
            if let model = agent.defaultModel, !model.isEmpty {
                kv("Default model", model)
            }
            if let repo = agent.defaultRepo, !repo.isEmpty {
                kv("Default repo", repo)
            }
        }
    }

    /// Expanded editor. Three text fields (name, role, model) +
    /// destructive delete with a confirmation step. The delete is a
    /// two-click affordance rather than a sheet because permanent-agent
    /// destruction is recoverable in spirit (the user can save the
    /// same name again) and the destructive verb is already separated
    /// from the save verb visually.
    private var editorBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            field(label: "NAME", text: $draftName, placeholder: agent.name)
            field(label: "ROLE", text: $draftRole, placeholder: agent.role)
            field(label: "DEFAULT MODEL", text: $draftModel, placeholder: "claude-opus-4-7")
            field(label: "DEFAULT REPO (PATH)", text: $draftRepo, placeholder: "/Users/you/code/your-repo")

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if confirmingDelete {
                    Button("Cancel") { confirmingDelete = false }
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

                    Button("Delete \(agent.name)") {
                        Task { await delete() }
                    }
                    .buttonStyle(.plain)
                    .font(SkogaFont.smallMedium(11.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.ember)
                    )
                } else {
                    Button("Delete") { confirmingDelete = true }
                        .buttonStyle(.plain)
                        .font(SkogaFont.smallMedium(11.5))
                        .foregroundStyle(p.ember)
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
                        HStack(spacing: 5) {
                            if saving {
                                ProgressView().controlSize(.small).progressViewStyle(.circular)
                            }
                            Text(saving ? "Saving…" : "Save changes")
                                .font(SkogaFont.bodyMedium(12))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.forest)
                        )
                        .opacity(saving ? 0.7 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(saving || !hasChanges)
                }
            }
        }
    }

    /// True when at least one editor field differs from the persisted
    /// value in a way the Save action can actually express. The PATCH
    /// shape on `agents.update` treats `nil` as "leave alone", so a
    /// cleared field can't currently clear the daemon-side value —
    /// suppress that case from `hasChanges` so Save stays disabled
    /// rather than firing a confusing no-op write. (To genuinely
    /// clear a default, the user deletes the agent and re-saves.)
    private var hasChanges: Bool {
        let n = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = draftRole.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = draftModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = draftRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        if n != agent.name { return true }
        if r != agent.role { return true }
        if !m.isEmpty && m != (agent.defaultModel ?? "") { return true }
        if !p.isEmpty && p != (agent.defaultRepo ?? "") { return true }
        return false
    }

    private func save() async {
        guard !saving, hasChanges else { return }
        saving = true
        defer { saving = false }
        let trimmedModel = draftModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRepo = draftRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = await coordinator.updatePermanentAgent(
            id: agent.id,
            name: draftName,
            role: draftRole,
            defaultRepo: trimmedRepo.isEmpty ? nil : trimmedRepo,
            defaultModel: trimmedModel.isEmpty ? nil : trimmedModel
        )
        if ok { editing = false }
    }

    private func delete() async {
        await coordinator.deletePermanentAgent(id: agent.id, name: agent.name)
        confirmingDelete = false
        editing = false
    }

    @ViewBuilder
    private func field(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            SettingsCardLabel(label)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(SkogaFont.body(13))
                .foregroundStyle(p.ink)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(p.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.input)
                        .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                )
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.input))
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(k)
                .font(SkogaFont.monoSmall(10.5))
                .foregroundStyle(p.inkFaint)
                .frame(width: 110, alignment: .leading)
            Text(v)
                .font(SkogaFont.small(11.5))
                .foregroundStyle(p.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// Shared between the meta-row "Last used" entries. Locale-aware
    /// since this is a date string the user might recognize from
    /// Finder ("2 hours ago"); the rest of Skoga's per-second labels
    /// are pinned to en_US_POSIX but the relative-date use case here
    /// is different enough that following system locale reads better.
    private static let lastUsedFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}
