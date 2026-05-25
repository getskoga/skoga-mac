import SwiftUI
import AppKit

struct DispatchView: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var state: AppState

    @State private var template: Template = .feature
    @State private var title: String = ""
    @State private var brief: String = ""
    @State private var repo: String = ""
    @State private var assignee: String = "auto"
    @State private var model: String = "claude-opus-4.7"

    static let REPOS = [
        "skoga/monolith-web", "skoga/ledger-svc", "skoga/core-runtime",
        "skoga/search-svc", "skoga/etl", "skoga/infra", "skoga/pkg-clients", "skoga/docs",
    ]
    private var REPOS: [String] { Self.REPOS }

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
            state.backToRoster()
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
            ForEach(REPOS, id: \.self) { r in
                let on = repo == r
                Button {
                    repo = r
                } label: {
                    Text(r)
                        .font(SkogaFont.mono(11))
                        .foregroundStyle(on ? .white : p.ink2)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(
                            Capsule().fill(on ? p.forest : p.paper2)
                        )
                        .overlay(
                            Capsule().stroke(on ? p.forest : p.rule, lineWidth: Tokens.Hairline.width)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var assigneeGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            assigneeCard(id: "auto", name: "Auto · best fit", st: "Roster + history", icon: .spark, isAuto: true)
            assigneeCard(id: "spawn", name: "New agent", st: "Fresh runtime", icon: .plus)
            ForEach(idleOrLight) { a in
                assigneeCard(id: a.id, name: a.name, st: "\(a.role.split(separator: " / ").first.map(String.init) ?? a.role) · \(a.status.rawValue)", initials: a.initials)
            }
        }
    }

    private var idleOrLight: [Agent] {
        state.agents.filter { $0.status == .idle || $0.status == .done || $0.status == .exited }.prefix(6).map { $0 }
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
            ForEach(["claude-sonnet-4.7", "claude-opus-4.7", "gpt-5-codex", "gpt-5-mini", "local · qwen3-coder-32b"], id: \.self) { m in
                Button(m) { model = m }
            }
        } label: {
            HStack {
                Text(model).font(SkogaFont.body(13.5))
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
        // The Dispatch UI's repo pills are hints from the original design's
        // canned list — they don't correspond to anything on disk. Always
        // pop a folder picker so the user picks a real host clone before
        // skogad gets a `session.create` it could actually serve.
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose repo"
        panel.message = "Pick the host clone skoga should create a session worktree against."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let agentName = model.split(separator: "-").first.map(String.init) ?? "claude"
        let taskText = title.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await state.dispatch(task: taskText, agent: agentName, base: "main", repoRoot: url)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            Button(action: dispatchTapped) {
                HStack(spacing: 6) {
                    Image(skoga: .bolt).skogaIconSize(13)
                    Text("Dispatch run").font(SkogaFont.bodyMedium(12))
                }
                .padding(.horizontal, 14)
                .frame(height: 28)
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.forest))
            }
            .buttonStyle(.plain)

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
            kvRow("repo", repo, mono: true)
            kvRow("branch", branchName, mono: true)
            kvRow("assignee", assigneeLabel, mono: false)
            kvRow("model", model, mono: true)
        }
        .padding(.top, 8)
    }

    private var branchName: String {
        let base = (assignee == "auto" || assignee == "spawn") ? "agent" : assignee
        let slug = (title.isEmpty ? "untitled" : title)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .prefix(28)
        return "\(base)/\(slug)"
    }

    private var assigneeLabel: String {
        switch assignee {
        case "auto":  "Auto · best fit"
        case "spawn": "New agent · spawn fresh"
        default:      state.agents.first(where: { $0.id == assignee })?.name ?? "—"
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
