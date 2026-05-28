import SwiftUI

/// Step 6 — Ready. Four-card tour (Roster, Dispatch, Review handoff,
/// Mobile bridge) plus the finishing fork: land on the roster or
/// jump straight into Dispatch.
struct StepReady: View {
    @Environment(\.palette) private var p
    let onFinish: () -> Void
    let onDispatchFirst: () -> Void

    private static let cards: [TourCard] = [
        .init(icon: .roster,    title: "Your roster",
              body: "Every running agent — status, blockers, runtime, spend — at a glance. We'll show you a demo guild to start."),
        .init(icon: .dispatch,  title: "Dispatch",
              body: "Write tasks like tickets, not prompts. Skoga assigns to the right model, spawns a fresh worktree."),
        .init(icon: .review,    title: "Review handoff",
              body: "One button to open a run as a PR. Review feedback loops back to the agent so they can push fixes."),
        .init(icon: .watch,     title: "Mobile bridge",
              body: "Push to phone & watch when an agent needs you. Unblock from anywhere."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHead(
                eyebrow: "All set",
                title: "Welcome to your forest.",
                body: AnyView(StepLede("Quick tour of what you can do, then we'll drop you on the roster. You can re-run this from Settings · About."))
            )

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
                ForEach(Self.cards) { card in
                    tourCard(card)
                }
            }

            finishRow
        }
    }

    private func tourCard(_ card: TourCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(p.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                    )
                    .frame(width: 30, height: 30)
                Image(skoga: card.icon).skogaIconSize(16)
                    .foregroundStyle(p.forest)
            }
            .padding(.bottom, 2)
            Text(card.title)
                .font(SkogaFont.serifName(16).weight(.medium))
                .foregroundStyle(p.ink)
            Text(card.body)
                .font(SkogaFont.body(12.5))
                .foregroundStyle(p.inkMute)
                .lineSpacing(12.5 * 0.5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(p.paper2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
    }

    private var finishRow: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Spawn your first agent?")
                    .font(SkogaFont.serifName(17).weight(.medium))
                    .foregroundStyle(p.ink)
                Text("We'll open Dispatch with a template you can edit, or you can just land on the roster.")
                    .font(SkogaFont.body(12.5))
                    .foregroundStyle(p.inkMute)
                    .lineSpacing(12.5 * 0.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                OBGhostButton(label: "Just show the roster", action: onFinish)
                Button(action: onDispatchFirst) {
                    HStack(spacing: 6) {
                        Image(skoga: .bolt).skogaIconSize(13)
                        Text("Dispatch first agent").font(SkogaFont.bodyMedium(13))
                    }
                    .foregroundStyle(Color.oklch(0.97, 0.02, 90))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.forest))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(p.forestSoft.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
    }

    struct TourCard: Identifiable {
        var id: String { title }
        let icon: SkogaIcon
        let title: String
        let body: String
    }
}
