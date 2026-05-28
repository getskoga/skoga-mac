import SwiftUI

/// Read-only renderer for a session's parsed transcript. Used by the
/// ConversationView when the agent is in a terminal state (the tmux
/// pane has been torn down so the live PTY can't attach). Each
/// `ConversationMessage` variant gets its own row style; the layout
/// mirrors how the same data used to render in the embedded TUI but
/// without any interactive affordances (no composer, no question
/// picker action).
struct ParsedTranscriptView: View {
    @Environment(\.palette) private var p
    let messages: [ConversationMessage]
    /// `true` once `AppCoordinator.loadConversation` has resolved at
    /// least once for the current agent — distinguishes "transcript
    /// hasn't loaded yet" from "transcript loaded and was empty".
    /// Without this we'd flash the empty state for the few-hundred-ms
    /// between view appearance and the first `apply(messages:)`.
    let hasLoaded: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if messages.isEmpty {
                    if hasLoaded { emptyState } else { loadingState }
                } else {
                    ForEach(messages) { message in
                        row(for: message)
                    }
                }
            }
            .padding(.horizontal, Tokens.Pad.viewX)
            .padding(.top, 20)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(p.paper)
        .textSelection(.enabled)
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 80)
            ProgressView()
                .controlSize(.small)
            Text("Loading transcript…")
                .font(SkogaFont.small(11.5))
                .foregroundStyle(p.inkMute)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func row(for message: ConversationMessage) -> some View {
        switch message {
        case .msg(let m):      MsgRow(payload: m)
        case .tool(let t):     ToolRow(payload: t)
        case .write(let w):    WriteRow(payload: w)
        case .question(let q): QuestionRow(payload: q)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 80)
            Image(skoga: .clock).skogaIconSize(20)
                .foregroundStyle(p.inkFaint)
            Text("No transcript on file")
                .font(SkogaFont.bodyMedium(13))
                .foregroundStyle(p.ink2)
            Text("This session ended before Claude recorded a conversation.")
                .font(SkogaFont.small(11.5))
                .foregroundStyle(p.inkMute)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: – Row variants

private struct MsgRow: View {
    @Environment(\.palette) private var p
    let payload: ConversationMessage.MsgPayload

    private var initials: String {
        if let override = payload.initialOverride { return override }
        return String(payload.from.prefix(2))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(payload.from)
                        .font(SkogaFont.bodyMedium(12.5))
                        .foregroundStyle(p.ink)
                    if let runtime = payload.runtimeLabel {
                        Text(runtime)
                            .font(SkogaFont.monoTiny(9.5))
                            .foregroundStyle(p.inkFaint)
                    }
                    Spacer(minLength: 0)
                    Text(payload.when)
                        .font(SkogaFont.monoTiny(9.5))
                        .foregroundStyle(p.inkFaint)
                }
                // Index-keyed because two paragraph lines can repeat
                // verbatim (blank-line stand-ins, identical bullets),
                // and `id: \.self` would warn + collapse rows.
                ForEach(Array(payload.text.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(SkogaFont.body(12.5))
                        .foregroundStyle(p.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var avatar: some View {
        Text(initials)
            .font(SkogaFont.serifName(13))
            .foregroundStyle(p.ink2)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(p.paper3))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.rule, lineWidth: Tokens.Hairline.width))
    }
}

private struct ToolRow: View {
    @Environment(\.palette) private var p
    let payload: ConversationMessage.ToolPayload

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            badge("tool")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(payload.tool)
                        .font(SkogaFont.monoSmall(10.5).weight(.medium))
                        .foregroundStyle(p.amber)
                    if let path = payload.path {
                        Text(path)
                            .font(SkogaFont.monoSmall(10.5))
                            .foregroundStyle(p.ink2)
                    }
                    if let lines = payload.lines {
                        Text(lines)
                            .font(SkogaFont.monoTiny(9.5))
                            .foregroundStyle(p.inkFaint)
                    }
                }
                if let cmd = payload.cmd {
                    Text(cmd)
                        .font(SkogaFont.monoSmall(10.5))
                        .foregroundStyle(p.ink2)
                        .padding(.vertical, 4).padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.Radius.tiny).fill(p.paper3)
                        )
                }
                if let result = payload.result {
                    Text(result)
                        .font(SkogaFont.monoTiny(10))
                        .foregroundStyle(p.inkMute)
                }
            }
        }
    }

    private func badge(_ label: String) -> some View {
        Text(label.uppercased())
            .font(SkogaFont.monoTiny(8.5))
            .tracking(0.6)
            .foregroundStyle(p.amber)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3).stroke(p.amber.opacity(0.6), lineWidth: Tokens.Hairline.width)
            )
            .padding(.top, 1)
    }
}

private struct WriteRow: View {
    @Environment(\.palette) private var p
    let payload: ConversationMessage.WritePayload

    var body: some View {
        HStack(spacing: 10) {
            badge
            Text(payload.path)
                .font(SkogaFont.monoSmall(10.5))
                .foregroundStyle(p.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text("+\(payload.adds)")
                .font(SkogaFont.monoTiny(10))
                .foregroundStyle(p.forest)
            Text("−\(payload.rems)")
                .font(SkogaFont.monoTiny(10))
                .foregroundStyle(p.ember)
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                .fill(p.paper2)
                .hairlineBorder(p.rule, radius: Tokens.Radius.tiny)
        )
    }

    private var badge: some View {
        Text("WRITE")
            .font(SkogaFont.monoTiny(8.5))
            .tracking(0.6)
            .foregroundStyle(p.forest)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3).stroke(p.forest.opacity(0.6), lineWidth: Tokens.Hairline.width)
            )
    }
}

/// Read-only rendering of a pending question — labels + options as a
/// disabled list. No tap targets because the session is closed and any
/// answer would route nowhere.
private struct QuestionRow: View {
    @Environment(\.palette) private var p
    let payload: ConversationMessage.QuestionPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(payload.label)
                .font(SkogaFont.bodyMedium(12.5))
                .foregroundStyle(p.ink)
            ForEach(Array(payload.body.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(SkogaFont.body(12.5))
                    .foregroundStyle(p.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(payload.options.enumerated()), id: \.offset) { _, option in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(skoga: .chevron).skogaIconSize(10)
                            .foregroundStyle(p.inkFaint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.label)
                                .font(SkogaFont.small(11.5))
                                .foregroundStyle(p.ink2)
                            if let description = option.description {
                                Text(description)
                                    .font(SkogaFont.monoTiny(10))
                                    .foregroundStyle(p.inkMute)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                .fill(p.paper2)
                .hairlineBorder(p.rule, radius: Tokens.Radius.tiny)
        )
    }
}
