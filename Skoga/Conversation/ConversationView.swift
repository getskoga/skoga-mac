import SwiftUI

struct ConversationView: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var state: AppState
    let agent: Agent

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ConvHeader(agent: agent)
                ConvFeed(agent: agent, messages: state.conversation)
                ConvComposer(agent: agent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .trailing) {
                Hairline(axis: .vertical).frame(width: Tokens.Hairline.width)
            }

            ConvSidePanel(agent: agent, timeline: state.timeline)
                .frame(width: Tokens.convAsideWidth)
        }
    }
}

// MARK: – Header

private struct ConvHeader: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var state: AppState
    let agent: Agent

    var body: some View {
        HStack(spacing: 14) {
            Button {
                state.backToRoster()
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

            actionButtons
        }
        .padding(.horizontal, Tokens.Pad.viewX)
        .padding(.top, 16).padding(.bottom, 14)
        .background(p.paper)
        .overlay(alignment: .bottom) { Hairline() }
    }

    @ViewBuilder private var actionButtons: some View {
        HStack(spacing: 8) {
            switch agent.status {
            case .review:
                PrimaryButton(label: "Open as PR", icon: .github, tint: .forest) {
                    state.prAgentId = agent.id
                }
            case .done:
                GhostPillButton(label: "Already open", icon: .github) {}
            default:
                GhostPillButton(label: "Pause", icon: .pause) {}
                GhostPillButton(label: "Stop", icon: .stop, color: p.ember) {}
            }
        }
    }
}

// MARK: – Feed

private struct ConvFeed: View {
    @Environment(\.palette) private var p
    let agent: Agent
    let messages: [ConversationMessage]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(messages) { m in
                        row(m).id(m.id)
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Tokens.Pad.viewX)
                .padding(.vertical, 18)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(p.paper)
    }

    @ViewBuilder
    private func row(_ m: ConversationMessage) -> some View {
        switch m {
        case .msg(let payload):      ConvMessageRow(payload: payload, agent: agent)
        case .tool(let payload):     ConvToolRow(payload: payload)
        case .write(let payload):    ConvWriteRow(payload: payload)
        case .question(let payload): ConvQuestionRow(payload: payload, agentId: agent.id)
        }
    }
}

// MARK: – Message row

private struct ConvMessageRow: View {
    @Environment(\.palette) private var p
    let payload: ConversationMessage.MsgPayload
    let agent: Agent

    var body: some View {
        let isYou = payload.from == "you"
        let displayName = isYou ? "You" : (payload.from == agent.id ? agent.name : payload.from)
        let initial = payload.initialOverride ?? (isYou ? "M" : String(displayName.prefix(2)))

        HStack(alignment: .top, spacing: 12) {
            Text(initial)
                .font(SkogaFont.serifName(12))
                .foregroundStyle(p.ink)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(isYou ? p.forestSoft : p.paper4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                )
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                metaRow(displayName: displayName)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(payload.text.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(SkogaFont.body(13.5))
                            .foregroundStyle(p.ink)
                            .lineSpacing(13.5 * 0.55)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func metaRow(displayName: String) -> some View {
        HStack(spacing: 8) {
            Text(displayName)
                .font(SkogaFont.smallMedium(12))
                .foregroundStyle(p.ink2)
            Text("·").foregroundStyle(p.inkFaint)
            Text(payload.when)
                .font(SkogaFont.monoSmall(10.5))
                .foregroundStyle(p.inkFaint)
            if let label = payload.runtimeLabel {
                Text("·").foregroundStyle(p.inkFaint)
                Text(label)
                    .font(SkogaFont.monoSmall(10.5))
                    .foregroundStyle(p.inkFaint)
            }
        }
    }
}

// MARK: – Tool row

private struct ConvToolRow: View {
    @Environment(\.palette) private var p
    let payload: ConversationMessage.ToolPayload

    var body: some View {
        HStack(spacing: 8) {
            Text(payload.tool.uppercased())
                .font(SkogaFont.monoTiny(9.5))
                .tracking(0.55)
                .foregroundStyle(p.inkFaint)
            if let path = payload.path {
                Text(path)
                    .font(SkogaFont.mono(11))
                    .foregroundStyle(p.ink2)
            }
            if let lines = payload.lines {
                Text("L\(lines)")
                    .font(SkogaFont.mono(11))
                    .foregroundStyle(p.inkFaint)
            }
            if let cmd = payload.cmd {
                Text("$ \(cmd)")
                    .font(SkogaFont.mono(11))
                    .foregroundStyle(p.ink2)
            }
            if let result = payload.result {
                Spacer(minLength: 8)
                Text(result)
                    .font(SkogaFont.mono(11))
                    .foregroundStyle(p.inkFaint)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                .fill(p.paper2)
                .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
        )
        .padding(.leading, 38)  // align with message body
    }
}

// MARK: – Write row

private struct ConvWriteRow: View {
    @Environment(\.palette) private var p
    let payload: ConversationMessage.WritePayload

    var body: some View {
        HStack(spacing: 8) {
            Text("WRITE")
                .font(SkogaFont.monoTiny(9.5))
                .tracking(0.55)
                .foregroundStyle(p.inkFaint)
            Text(payload.path)
                .font(SkogaFont.mono(11))
                .foregroundStyle(p.ink2)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text("+\(payload.adds)")
                    .font(SkogaFont.mono(11))
                    .foregroundStyle(p.forest)
                Text("−\(payload.rems)")
                    .font(SkogaFont.mono(11))
                    .foregroundStyle(p.ember)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                .fill(p.paper2)
                .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
        )
        .padding(.leading, 38)
    }
}

// MARK: – Question row

private struct ConvQuestionRow: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var state: AppState
    let payload: ConversationMessage.QuestionPayload
    let agentId: String?

    /// Tracks toggled options for multi-select; ignored for single-select
    /// (which submits on first click). Indexed by option offset; the set
    /// is reset every time the picker is rerendered.
    @State private var toggled: Set<Int> = []
    @State private var submitting: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("⚠ \(payload.label)".uppercased())
                .font(SkogaFont.monoTiny(9.5))
                .tracking(0.55)
                .foregroundStyle(p.ember)
                .padding(.bottom, 4)

            Text(payload.body.joined(separator: "\n"))
                .font(SkogaFont.mono(11.5))
                .foregroundStyle(p.ink2)
                .lineSpacing(11.5 * 0.6)
                .fixedSize(horizontal: false, vertical: true)

            // Options as wrapped chips. HStack would clip on long option
            // lists, but the design's Decision-needed rows tend to have
            // 2–4 short labels so a single row reads fine. If a future
            // question needs > ~5 options, switch this to a FlowLayout.
            HStack(spacing: 6) {
                ForEach(Array(payload.options.enumerated()), id: \.offset) { idx, opt in
                    optionChip(index: idx, option: opt)
                }
            }
            .padding(.top, 6)

            if payload.multiSelect {
                HStack {
                    Spacer()
                    Button("Submit") {
                        submit(indices: Array(toggled).sorted())
                    }
                    .buttonStyle(.plain)
                    .font(SkogaFont.smallMedium(11.5))
                    .foregroundStyle(toggled.isEmpty ? p.ink2.opacity(0.5) : p.paper2)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .fill(toggled.isEmpty ? p.paper2 : p.ember)
                            .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                    )
                    .disabled(toggled.isEmpty || submitting)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.emberSoft.opacity(0.35))
        .overlay(alignment: .leading) {
            Rectangle().fill(p.ember).frame(width: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.leading, 38)
    }

    @ViewBuilder
    private func optionChip(index: Int, option: ConversationMessage.QuestionOption) -> some View {
        let isSelected = toggled.contains(index)
        Button {
            if payload.multiSelect {
                if isSelected { toggled.remove(index) } else { toggled.insert(index) }
            } else {
                submit(indices: [index])
            }
        } label: {
            HStack(spacing: 4) {
                if payload.multiSelect {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 10))
                }
                Text(option.label)
                if let description = option.description, !description.isEmpty {
                    Text(description)
                        .foregroundStyle(p.ink2.opacity(0.65))
                }
            }
        }
        .buttonStyle(.plain)
        .font(SkogaFont.smallMedium(11.5))
        .foregroundStyle(p.ink2)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                .fill(isSelected ? p.emberSoft : p.paper2)
                .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
        )
        .disabled(submitting || agentId == nil)
    }

    private func submit(indices: [Int]) {
        guard !submitting, !indices.isEmpty, let agentId else { return }
        submitting = true
        Task {
            await state.answerQuestion(to: agentId, selectedIndices: indices)
        }
    }
}

// MARK: – Composer

private struct ConvComposer: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var state: AppState
    let agent: Agent

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if state.pendingReply.isEmpty {
                    Text(placeholder)
                        .font(SkogaFont.body(13.5))
                        .foregroundStyle(p.inkFaint)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                }
                TextEditor(text: $state.pendingReply)
                    .focused($focused)
                    .font(SkogaFont.body(13.5))
                    .foregroundStyle(p.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10).padding(.vertical, 7)
            }
            .frame(minHeight: 60)
            .background(p.paper)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.input)
                    .stroke(focused ? p.ruleHard : p.rule, lineWidth: Tokens.Hairline.width)
            )
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.input))

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("⌘↵")
                        .font(SkogaFont.monoTiny(10))
                        .foregroundStyle(p.inkFaint)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                                .fill(p.paper)
                                .hairlineBorder(p.rule, radius: Tokens.Radius.tiny)
                        )
                    Text("send")
                        .font(SkogaFont.monoSmall(10.5))
                        .foregroundStyle(p.inkFaint)
                }
                Text("·").foregroundStyle(p.inkFaint)
                Text("Attached: \(agent.branch)")
                    .font(SkogaFont.monoSmall(10.5))
                    .foregroundStyle(p.inkFaint)
                Spacer(minLength: 8)
                TextLink(label: "@mention") {}
                TextLink(label: "/ commands") {}
                PrimaryButton(label: "Send", icon: nil, tint: .ink) {
                    sendReply()
                }
                .opacity(state.pendingReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .disabled(state.pendingReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, Tokens.Pad.viewX)
        .padding(.vertical, 14)
        .background(p.paper2)
        .overlay(alignment: .top) { Hairline() }
    }

    private var placeholder: String {
        agent.status == .blocked
            ? "Answer \(agent.name)'s question, or redirect…"
            : "Reply to \(agent.name)…"
    }

    private func sendReply() {
        let trimmed = state.pendingReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let agentId = agent.id
        state.pendingReply = ""
        Task { await state.sendReply(to: agentId, text: trimmed) }
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
