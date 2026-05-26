import SwiftUI

struct AgentCard: View {
    @Environment(\.palette) private var p
    @Environment(AppState.self) private var state
    let agent: Agent
    let onPick: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 10) {
                topRow
                if agent.attn, let message = agent.attnMessage {
                    attentionBanner(message)
                }
                taskBlock
                Spacer(minLength: 0)
                progressRow
                metaRow
            }
            .padding(.horizontal, Tokens.Pad.cardX)
            .padding(.top, Tokens.Pad.cardY)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 200)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                    .stroke(borderColor, lineWidth: Tokens.Hairline.width)
            )
            .shadow(color: hovering ? p.cardShadow : .clear, radius: hovering ? 14 : 0, x: 0, y: hovering ? 4 : 0)
            .offset(y: hovering ? -1 : 0)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Kill session", role: .destructive) {
                Task { await state.kill(agentId: agent.id) }
            }
        }
    }

    // MARK: – Top row

    private var topRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(agent.initials)
                .font(SkogaFont.serifName(14.5))
                .foregroundStyle(p.ink)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.input).fill(p.paper4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.input)
                        .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                )

            VStack(alignment: .leading, spacing: 0) {
                Text(agent.name)
                    .font(SkogaFont.serifName(16))
                    .foregroundStyle(p.ink)
                HStack(spacing: 5) {
                    Image(skoga: iconForRole(agent.role)).skogaIconSize(10)
                    Text(agent.role.uppercased())
                        .font(SkogaFont.monoTiny(10))
                        .tracking(0.4)
                }
                .foregroundStyle(p.inkFaint)
            }

            Spacer(minLength: 0)
            StatusPill(status: agent.status)
        }
    }

    // MARK: – Attention banner

    private func attentionBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(p.ember)
                .frame(width: 5, height: 5)
                .overlay(Circle().stroke(p.ember.opacity(0.18), lineWidth: 3))
            Text(message)
                .font(SkogaFont.monoSmall(10.5))
                .tracking(0.4)
        }
        .foregroundStyle(p.ember)
        .padding(.top, -2)
    }

    // MARK: – Task

    private var taskBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(agent.repo) · \(agent.branch)")
                .font(SkogaFont.monoSmall(10.5))
                .foregroundStyle(p.inkMute)
            Text(agent.task)
                .font(SkogaFont.body(13.5))
                .foregroundStyle(p.ink)
                .lineSpacing(1.45 * 13.5 - 13.5)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: – Progress

    private var progressRow: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(p.paper4).frame(height: 4)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressColor)
                        .frame(width: geo.size.width * agent.progress, height: 4)
                }
                .frame(height: 4)
            }
            Text("\(Int((agent.progress * 100).rounded()))%")
                .font(SkogaFont.mono(10.5))
                .foregroundStyle(p.inkMute)
                .frame(minWidth: 32, alignment: .trailing)
        }
        .padding(.top, 2)
    }

    private var progressColor: Color {
        switch agent.status {
        case .blocked: p.ember
        case .running: p.amber
        default:       p.forest
        }
    }

    // MARK: – Meta row

    private var metaRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Image(skoga: .clock).skogaIconSize(10)
                Text(agent.runtime)
            }
            sep
            Text("\(agent.commits) commits")
            sep
            Text("\(agent.files) files")
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Text(agent.tokens > 0 ? "\(agent.tokens / 1000)k tok" : "—")
                    .foregroundStyle(p.inkMute)
                Text(agent.shortModel)
                    .foregroundStyle(p.inkFaint)
            }
        }
        .font(SkogaFont.mono(10.5))
        .foregroundStyle(p.inkMute)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .strokeBorder(
                    p.rule,
                    style: StrokeStyle(lineWidth: Tokens.Hairline.width, dash: [2, 2])
                )
                .frame(height: Tokens.Hairline.width)
        }
    }

    private var sep: some View {
        Text("·").foregroundStyle(p.ruleHard)
    }

    // MARK: – Background

    @ViewBuilder private var cardBackground: some View {
        if agent.attn {
            ZStack {
                p.paper2
                LinearGradient(
                    colors: [p.emberSoft.opacity(0.5), p.paper2.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        } else {
            RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(p.paper2)
        }
    }

    private var borderColor: Color {
        if agent.attn { return p.ember.opacity(0.7) }
        return hovering ? p.ruleHard : p.rule
    }
}
