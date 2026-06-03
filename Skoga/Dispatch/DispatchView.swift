import SwiftUI
import AppKit

struct DispatchView: View {
    @Environment(\.palette) private var p
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(RosterState.self) private var roster
    @Environment(DaemonClientHolder.self) private var daemon
    @Environment(NamedAgentsState.self) private var namedAgents

    @State private var template: Template = .feature
    @State private var title: String = ""
    @State private var brief: String = ""
    /// Recently-used host repos loaded from `session.recent_repos`. Empty
    /// on first paint (and on older daemons that don't speak the RPC); the
    /// "Choose folder…" pill at the end of the row is always present so
    /// the user can dispatch even with no history.
    @State private var repos: [RPCRecentRepo] = []
    /// Absolute path of the currently-selected recent repo, or empty when
    /// nothing is selected. Empty means "ask the user via NSOpenPanel on
    /// dispatch"; non-empty bypasses the picker. The path itself (rather
    /// than an index or `RPCRecentRepo`) is the source of truth because
    /// the "Choose folder…" flow injects a transient entry into `repos`
    /// keyed by path, and a refresh from the daemon shouldn't lose the
    /// selection.
    @State private var selectedRepoPath: String = ""
    @State private var assignee: String = "auto"
    /// Initial pick reads from the per-adapter `skoga.defaultModel.<adapter>`
    /// AppStorage key the Settings → Models & keys page writes, so the
    /// Dispatch form opens on the user's last-chosen default instead of a
    /// hardcoded one. We default to the Anthropic adapter's preference;
    /// if it doesn't resolve to a known model (renamed model, stale
    /// pref) we fall back to the first Claude entry, then to the very
    /// first choice — guaranteeing a non-nil initial value.
    ///
    /// Seeded from `DaemonClientHolder.fallbackModelChoices` (the same
    /// list that hydrates `daemon.modelChoices` on cold launch) because
    /// `@State` initializers can't reach the environment. The `.task`
    /// block below re-resolves against the daemon's live list once it
    /// arrives, so a freshly-released model the daemon knows about can
    /// take over without losing the user's pre-fetch selection.
    @State private var selectedModel: RPCModelChoice = {
        let fallback = DaemonClientHolder.fallbackModelChoices
        let preferred = DefaultModelPreference.resolve(adapter: "claude")
        if let match = fallback.first(where: { $0.model == preferred }) {
            return match
        }
        if let claudeDefault = fallback.first(where: { $0.adapter == "claude" }) {
            return claudeDefault
        }
        return fallback[0]
    }()

    enum Template: String, CaseIterable, Identifiable {
        case feature, fix, refactor, test, perf, docs
        var id: String { rawValue }
        var title: String {
            switch self {
            case .feature:  "Feature"
            case .fix:      "Bug fix"
            case .refactor: "Refactor"
            case .test:     "Tests"
            case .perf:     "Perf"
            case .docs:     "Docs"
            }
        }
        var desc: String {
            switch self {
            case .feature:  "Build something new"
            case .fix:      "Reproduce + patch"
            case .refactor: "No behaviour change"
            case .test:     "Cover an area"
            case .perf:     "Profile + speed up"
            case .docs:     "Write + update"
            }
        }
        var icon: SkogaIcon {
            switch self {
            case .feature:  .bolt
            case .fix:      .bug
            case .refactor: .loop
            case .test:     .beaker
            case .perf:     .spark
            case .docs:     .doc
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            mainColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .trailing) {
                    Hairline(axis: .vertical).frame(width: Tokens.Hairline.width)
                }
            asideColumn
                .frame(width: Tokens.dispatchAsideWidth)
                .background(p.paper2)
        }
        .task {
            await loadRecentRepos()
            await daemon.refreshModels()
            // After the live list arrives, re-resolve `selectedModel` so
            // its label matches the daemon's canonical entry (e.g. user's
            // AppStorage default is `claude-opus-4-7` but the daemon
            // ships it under a slightly different label). If the user's
            // stored model isn't in the live list at all (renamed, EOL'd)
            // leave the fallback-seeded selection alone — switching it
            // mid-paint would surprise the user.
            if let match = daemon.modelChoices.first(where: { $0.model == selectedModel.model }) {
                selectedModel = match
            }
        }
    }

    /// Pull recent repos from the daemon once on view appear. Failures
    /// stay silent — the row degrades to just the "Choose folder…" pill,
    /// which is the same fallback the screen had before this RPC existed,
    /// so a transient drop or an old daemon never blocks dispatch.
    private func loadRecentRepos() async {
        guard let fetched = try? await daemon.client.recentRepos() else { return }
        // Don't drop a path the user just chose via the "Choose folder…"
        // pill. If they picked something not yet recorded daemon-side
        // (e.g. first dispatch against that clone), the synthesized entry
        // we appended below would otherwise vanish when this refresh
        // overwrites `repos`. Merge by `repo_root`, daemon entries first.
        let daemonPaths = Set(fetched.map(\.repo_root))
        let kept = repos.filter { !daemonPaths.contains($0.repo_root) }
        repos = fetched + kept
    }

    // MARK: – Main column

    private var mainColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                backButton
                Text("Dispatch a new run")
                    .font(SkogaFont.serifTitle(28))
                    .foregroundStyle(p.ink)
                    .padding(.top, 4)
                Text("Spawn an agent against a fresh worktree. Write it like a ticket — clear acceptance, links to context. You can always drop into the conversation to redirect.")
                    .font(SkogaFont.body(13.5))
                    .foregroundStyle(p.inkMute)
                    .lineSpacing(13.5 * 0.5)
                    .frame(maxWidth: 540, alignment: .leading)
                    .padding(.top, 6)
                    .padding(.bottom, 22)

                VStack(alignment: .leading, spacing: 18) {
                    field(label: "Shape of work") { templateGrid }
                    field(label: "Headline") { headlineInput }
                    field(label: "Brief · spec · acceptance") { bodyInput }
                    field(label: "Repository") { repoPills }
                    field(label: "Assign to") { assigneeGrid }
                    field(label: "Model") { modelSelect }
                    actionsRow
                }
                .frame(maxWidth: 720, alignment: .leading)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .background(p.paper)
    }

    private var backButton: some View {
        Button {
            coordinator.navigate(to: .roster)
        } label: {
            HStack(spacing: 6) {
                Image(skoga: .back).skogaIconSize(12)
                Text("Back to roster").font(SkogaFont.smallMedium(11.5))
            }
            .foregroundStyle(p.inkMute)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(p.paper)
                    .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
            )
        }
        .buttonStyle(.plain)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased())
                .font(SkogaFont.mono(10))
                .tracking(1.0)
                .foregroundStyle(p.inkFaint)
            content()
        }
    }

    // MARK: – Template grid

    private var templateGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 168), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(Template.allCases) { t in
                templateCard(t)
            }
        }
    }

    @ViewBuilder
    private func templateCard(_ t: Template) -> some View {
        let on = template == t
        Button {
            template = t
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(skoga: t.icon).skogaIconSize(18)
                    .foregroundStyle(p.forest)
                    .padding(.bottom, 4)
                Text(t.title)
                    .font(SkogaFont.serifName(15))
                    .foregroundStyle(p.ink)
                Text(t.desc)
                    .font(SkogaFont.monoSmall(10.5))
                    .foregroundStyle(p.inkFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.input)
                    .fill(on ? p.paper3 : p.paper2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.input)
                    .stroke(on ? p.forest : p.rule, lineWidth: on ? 1 : Tokens.Hairline.width)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: – Inputs

    private var headlineInput: some View {
        TextField("", text: $title)
            .textFieldStyle(.plain)
            .font(SkogaFont.body(13.5))
            .foregroundStyle(p.ink)
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(p.paper)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.input)
                    .stroke(p.rule, lineWidth: Tokens.Hairline.width)
            )
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.input))
    }

    private var bodyInput: some View {
        TextEditor(text: $brief)
            .font(SkogaFont.body(13.5))
            .foregroundStyle(p.ink)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8).padding(.vertical, 7)
            .frame(minHeight: 140)
            .background(p.paper)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.input)
                    .stroke(p.rule, lineWidth: Tokens.Hairline.width)
            )
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.input))
    }

    private var repoPills: some View {
        FlowLayout(spacing: 6) {
            ForEach(repos) { r in
                repoPill(label: r.display_name, selected: selectedRepoPath == r.repo_root) {
                    selectedRepoPath = r.repo_root
                }
            }
            // Always present. On first run (no recent repos) it's the only
            // way to start a session; afterward it lets the user dispatch
            // against a clone outside the recent list.
            repoPill(label: "Choose folder…", selected: false) {
                chooseFolderTapped()
            }
        }
    }

    @ViewBuilder
    private func repoPill(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(SkogaFont.mono(11))
                .foregroundStyle(selected ? .white : p.ink2)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(
                    Capsule().fill(selected ? p.forest : p.paper2)
                )
                .overlay(
                    Capsule().stroke(selected ? p.forest : p.rule, lineWidth: Tokens.Hairline.width)
                )
        }
        .buttonStyle(.plain)
    }

    /// Pop an `NSOpenPanel` to pick a folder, then add it to the pills
    /// row as a selected entry. We append a synthetic `RPCRecentRepo`
    /// rather than just stashing the URL — that way the chosen folder
    /// renders as a selected pill and the user can see *which* repo
    /// they just picked instead of inferring it from the preview.
    private func chooseFolderTapped() {
        guard let url = openRepoPickerPanel() else { return }
        let path = url.path
        if !repos.contains(where: { $0.repo_root == path }) {
            let synthetic = RPCRecentRepo(
                repo_root: path,
                display_name: url.lastPathComponent,
                last_used: Date(),
                runs_count: 0
            )
            repos.insert(synthetic, at: 0)
        }
        selectedRepoPath = path
    }

    private func openRepoPickerPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose repo"
        panel.message = "Pick the host clone skoga should create a session worktree against."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    private var assigneeGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            assigneeCard(id: "auto", name: "Auto · best fit", st: "Roster + history", icon: .spark, isAuto: true)
            assigneeCard(id: "spawn", name: "New agent", st: "Fresh runtime", icon: .plus)
            ForEach(orderedPermanentAgents) { a in
                permanentAssigneeCard(a)
            }
            ForEach(idleOrLight) { a in
                assigneeCard(id: a.id, name: a.name, st: "\(a.role.split(separator: " / ").first.map(String.init) ?? a.role) · \(a.status.rawValue)", initials: a.initials)
            }
        }
    }

    private var idleOrLight: [Agent] {
        roster.agents.filter { $0.status == .idle || $0.status == .done || $0.status == .exited }.prefix(6).map { $0 }
    }

    /// Permanent agents ordered for the assignee grid. Agents whose
    /// `defaultRepo` matches the currently-selected dispatch repo sort
    /// first (so the user sees Astrid surface as the obvious pick when
    /// they've selected monolith-web); the remainder fall back to
    /// `lastUsed` desc. The id prefix (`named-`) distinguishes them
    /// from ephemeral agent ids at the dispatch handler, so a click
    /// can route to the permanent flow vs. the existing ephemeral
    /// reuse flow.
    private var orderedPermanentAgents: [NamedAgent] {
        let xs = namedAgents.agents
        let selectedRepo = selectedRepoPath
        return xs.sorted { lhs, rhs in
            let lhsMatch = lhs.defaultRepo == selectedRepo
            let rhsMatch = rhs.defaultRepo == selectedRepo
            if lhsMatch != rhsMatch { return lhsMatch }
            return (lhs.lastUsed ?? .distantPast) > (rhs.lastUsed ?? .distantPast)
        }
    }

    /// One row in the permanent-agents section of the assignee grid.
    /// Visually distinct from the idle-ephemeral cards via a thin
    /// "pinned" accent + the saved role/model in the subline so the
    /// user can tell their persisted Astrid apart from a stray
    /// ephemeral session that happens to share the name.
    @ViewBuilder
    private func permanentAssigneeCard(_ a: NamedAgent) -> some View {
        let on = assignee == a.id
        Button {
            assignee = a.id
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(p.forestSoft)
                    Text(a.initials)
                        .font(SkogaFont.serifName(13))
                        .foregroundStyle(p.ink)
                }
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.forest, lineWidth: Tokens.Hairline.width))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(a.name)
                            .font(SkogaFont.serifName(13.5))
                            .foregroundStyle(p.ink)
                            .lineLimit(1)
                        Image(skoga: .spark)
                            .skogaIconSize(9)
                            .foregroundStyle(p.forest)
                    }
                    Text("\(a.role) · permanent".uppercased())
                        .font(SkogaFont.monoTiny(9.5))
                        .tracking(0.4)
                        .foregroundStyle(p.inkFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.input)
                    .fill(on ? p.paper3 : p.paper2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.input)
                    .stroke(on ? p.forest : p.rule, lineWidth: on ? 1 : Tokens.Hairline.width)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func assigneeCard(id: String, name: String, st: String, icon: SkogaIcon? = nil, initials: String? = nil, isAuto: Bool = false) -> some View {
        let on = assignee == id
        Button {
            assignee = id
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isAuto ? p.forestSoft : p.paper4)
                    if let initials {
                        Text(initials)
                            .font(SkogaFont.serifName(13))
                            .foregroundStyle(p.ink)
                    } else if let icon {
                        Image(skoga: icon).skogaIconSize(14).foregroundStyle(p.ink)
                    }
                }
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.rule, lineWidth: Tokens.Hairline.width))

                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(SkogaFont.serifName(13.5))
                        .foregroundStyle(p.ink)
                        .lineLimit(1)
                    Text(st.uppercased())
                        .font(SkogaFont.monoTiny(9.5))
                        .tracking(0.4)
                        .foregroundStyle(p.inkFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.input)
                    .fill(on ? p.paper3 : p.paper2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.input)
                    .stroke(on ? p.forest : p.rule, lineWidth: on ? 1 : Tokens.Hairline.width)
            )
        }
        .buttonStyle(.plain)
    }

    private var modelSelect: some View {
        Menu {
            ForEach(daemon.modelChoices) { choice in
                Button(choice.label) { selectedModel = choice }
            }
        } label: {
            HStack {
                Text(selectedModel.label).font(SkogaFont.body(13.5))
                Spacer()
                Image(skoga: .chevron).skogaIconSize(10)
                    .rotationEffect(.degrees(90))
            }
            .foregroundStyle(p.ink)
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(p.paper)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.input)
                    .stroke(p.rule, lineWidth: Tokens.Hairline.width)
            )
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.input))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dispatchTapped() {
        // Bypass the folder picker when the user already picked a recent-
        // repo pill — that's the whole point of the pills. Without a
        // selection (first run, or `session.recent_repos` returned []) we
        // still pop the picker so dispatch isn't a dead end.
        let url: URL
        if !selectedRepoPath.isEmpty {
            url = URL(fileURLWithPath: selectedRepoPath)
        } else if let picked = openRepoPickerPanel() {
            url = picked
        } else {
            return
        }

        let taskText = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Combine the headline and the brief into a single prompt: title as a
        // one-line header, then the body. The body alone usually has all the
        // context, but the title is often a tighter "what to do" framing — so
        // Claude sees both. If the brief is empty we fall back to just the
        // title; if both are empty we pass nil and the agent boots blank.
        let briefText = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt: String? = {
            switch (taskText.isEmpty, briefText.isEmpty) {
            case (true,  true):  return nil
            case (false, true):  return taskText
            case (true,  false): return briefText
            case (false, false): return "\(taskText)\n\n\(briefText)"
            }
        }()
        // Permanent-agent route: substitute the agent's saved
        // `defaultModel` for whatever the dispatch form's Model picker
        // is showing (the user picked the agent, not the model — they'd
        // be surprised if Astrid suddenly ran on Codex). Adapter is
        // re-derived from the model id by matching against the daemon's
        // live `modelChoices`; when the saved model is no longer in the
        // list (renamed model, stale persistence), fall back to the
        // picker's current adapter — that's whatever the user has
        // already chosen for this dispatch, and is more likely to
        // route correctly than a hardcoded "claude".
        let (agentAdapter, agentModel): (String, String) = {
            if let permanent = selectedPermanentAgent, let saved = permanent.defaultModel {
                if let match = daemon.modelChoices.first(where: { $0.model == saved }) {
                    return (match.adapter, match.model)
                }
                return (selectedModel.adapter, saved)
            }
            return (selectedModel.adapter, selectedModel.model)
        }()
        let namedAgentId = selectedPermanentAgent?.id
        Task {
            await coordinator.dispatch(
                task: taskText,
                agent: agentAdapter,
                model: agentModel,
                base: "main",
                repoRoot: url,
                initialPrompt: prompt,
                namedAgentId: namedAgentId
            )
        }
    }

    /// The currently-selected permanent agent, if `assignee` matches
    /// one in the registry. Used both at dispatch time (to substitute
    /// the saved model) and in the preview KV strip (to render the
    /// permanent agent's name in `assigneeLabel`).
    private var selectedPermanentAgent: NamedAgent? {
        namedAgents.agents.first { $0.id == assignee }
    }

    private var canDispatch: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            // Disabled until the headline is non-empty. The daemon rejects
            // empty tasks with -32602 ("task cannot be empty"), and surfacing
            // that as a toast is a worse UX than just preventing the click.
            Button(action: dispatchTapped) {
                HStack(spacing: 6) {
                    Image(skoga: .bolt).skogaIconSize(13)
                    Text("Dispatch run").font(SkogaFont.bodyMedium(12))
                }
                .padding(.horizontal, 14)
                .frame(height: 28)
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.forest))
                .opacity(canDispatch ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!canDispatch)

            Button {
            } label: {
                Text("Save as template")
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
            .buttonStyle(.plain)

            Spacer()
            Text("⌘↵ to dispatch")
                .font(SkogaFont.monoSmall(10.5))
                .foregroundStyle(p.inkFaint)
        }
        .padding(.top, 6)
    }

    // MARK: – Aside

    private var asideColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Ticket preview")
                previewTicket
                sectionTitle("Estimate")
                estimateBlock
                sectionTitle("Worktree")
                worktreeBlock
            }
            .padding(.horizontal, 22).padding(.vertical, 24)
        }
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(SkogaFont.monoTiny(9.5))
            .tracking(0.95)
            .foregroundStyle(p.inkFaint)
    }

    private var previewTicket: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.isEmpty ? "Untitled run" : title)
                .font(SkogaFont.serifName(16))
                .foregroundStyle(p.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(brief)
                .font(SkogaFont.small(12))
                .foregroundStyle(p.inkMute)
                .lineSpacing(12 * 0.5)
                .frame(maxHeight: 130, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .clipped()
                .mask(
                    LinearGradient(colors: [.black, .black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                )

            previewKV
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
        .background(p.paper)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.input)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.input))
    }

    private var previewKV: some View {
        VStack(alignment: .leading, spacing: 4) {
            kvRow("shape", template.title, mono: false)
            kvRow("repo", selectedRepoLabel, mono: true)
            kvRow("branch", branchName, mono: true)
            kvRow("assignee", assigneeLabel, mono: false)
            kvRow("model", effectiveModelLabel, mono: true)
        }
        .padding(.top, 8)
    }

    /// What the dispatch will actually run with. When the assignee is
    /// a permanent agent with a saved `defaultModel`, that wins over
    /// the picker — same substitution `dispatchTapped` applies — so
    /// the preview row stops lying when the user picks Astrid after
    /// the Model dropdown has drifted to something else.
    private var effectiveModelLabel: String {
        if let permanent = selectedPermanentAgent, let saved = permanent.defaultModel, !saved.isEmpty {
            return saved
        }
        return selectedModel.model
    }

    private var selectedRepoLabel: String {
        repos.first(where: { $0.repo_root == selectedRepoPath })?.display_name ?? ""
    }

    private var branchName: String {
        let base: String = {
            switch assignee {
            case "auto", "spawn": return "agent"
            default:
                // Permanent agent: branch under the saved name slug so
                // the worktree reads "astrid/cart-xstate" the same as
                // it does for the ephemeral identity. Falls back to
                // the raw assignee id (the existing behavior for idle-
                // ephemeral assignees).
                if let permanent = selectedPermanentAgent {
                    return permanent.name.lowercased()
                }
                return assignee
            }
        }()
        let slug = (title.isEmpty ? "untitled" : title)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .prefix(28)
        return "\(base)/\(slug)"
    }

    private var assigneeLabel: String {
        switch assignee {
        case "auto":  return "Auto · best fit"
        case "spawn": return "New agent · spawn fresh"
        default:
            if let permanent = selectedPermanentAgent {
                return "\(permanent.name) · permanent"
            }
            return roster.agents.first(where: { $0.id == assignee })?.name ?? "—"
        }
    }

    private func kvRow(_ k: String, _ v: String, mono: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(k)
                .font(SkogaFont.monoSmall(10.5))
                .foregroundStyle(p.inkFaint)
                .frame(width: 72, alignment: .leading)
            Text(v)
                .font(mono ? SkogaFont.monoSmall(10.5) : SkogaFont.small(11.5))
                .foregroundStyle(p.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var estimateBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            estimateRow("Time", "~1h 40m")
            estimateRow("Tokens", "180k – 240k")
            estimateRow("Cost", "$1.40 – $2.00")
            Text("Based on 24 similar runs in this repo.")
                .font(SkogaFont.monoTiny(10.5))
                .foregroundStyle(p.inkFaint)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(p.paper)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.input)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.input))
    }

    private func estimateRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k)
                .font(SkogaFont.small(11.5))
                .foregroundStyle(p.inkMute)
            Spacer()
            Text(v)
                .font(SkogaFont.monoSmall(11))
                .foregroundStyle(p.ink2)
        }
    }

    private var worktreeBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("$ git worktree add").foregroundStyle(p.ink2)
            Text("  .skoga/worktrees/\(assignee)-abcd")
                .foregroundStyle(p.inkMute)
            Text("  -b \(branchName.prefix(50))")
                .foregroundStyle(p.ink2)
            Text("# isolated · ephemeral")
                .foregroundStyle(p.inkFaint)
        }
        .font(SkogaFont.mono(10.5))
        .lineSpacing(10.5 * 0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(p.paper)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.input)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.input))
    }
}

// MARK: – FlowLayout (for wrapping repo pills)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for size in sizes {
            if x + size.width > width && x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, lineHeight: CGFloat = 0
        for (i, size) in sizes.enumerated() {
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
