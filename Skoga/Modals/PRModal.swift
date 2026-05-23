import SwiftUI

struct PRModal: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var state: AppState
    let agent: Agent

    @State private var title: String
    @State private var bodyText: String

    init(agent: Agent) {
        self.agent = agent
        let cleanTitle = agent.task.hasSuffix(".") ? String(agent.task.dropLast()) : agent.task
        _title = State(initialValue: cleanTitle)
        _bodyText = State(initialValue: """
        ## Summary
        \(agent.task)

        ## What changed
        - Added `RefreshableScope` wrapper around the Stripe scope cache
        - On 401 from Stripe, transparently re-issues against the current secret and retries once
        - Removed stale 60s scope-token cache (made invalid by rotates)

        ## Tests
        - 11 new tests covering rotate-mid-flight + repeated 401s
        - All `pnpm -w test auth` passing (57/57)

        ## Notes
        Co-authored-by: Skoga / \(agent.name) <\(agent.id)@agents.skoga.dev>
        """)
    }

    var body: some View {
        ZStack {
            p.modalScrim
                .ignoresSafeArea()
                .onTapGesture { state.prAgentId = nil }

            VStack(spacing: 0) {
                head
                modalBody
                foot
            }
            .frame(width: 560)
            .frame(maxHeight: 720)
            .background(p.paper)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.modal)
                    .stroke(p.ruleHard, lineWidth: Tokens.Hairline.width)
            )
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.modal))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 20)
        }
    }

    private var head: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(p.forestSoft)
                Image(skoga: .github).skogaIconSize(18).foregroundStyle(p.forestDeep)
            }
            .frame(width: 36, height: 36)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.forest.opacity(0.4), lineWidth: Tokens.Hairline.width))

            VStack(alignment: .leading, spacing: 2) {
                Text("Open as Pull Request")
                    .font(SkogaFont.serifHeading(21))
                    .foregroundStyle(p.ink)
                Text("\(agent.repo) · \(agent.branch)")
                    .font(SkogaFont.mono(11))
                    .foregroundStyle(p.inkMute)
            }
            Spacer(minLength: 0)
            Button { state.prAgentId = nil } label: {
                Image(skoga: .close).skogaIconSize(12)
                    .foregroundStyle(p.inkMute)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .fill(p.paper2)
                            .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 14)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var modalBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                branchRow
                diffStat
                field(label: "Title") {
                    TextField("", text: $title)
                        .textFieldStyle(.plain)
                        .font(SkogaFont.body(13))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(p.paper)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.rule, lineWidth: Tokens.Hairline.width))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                field(label: "Description") {
                    TextEditor(text: $bodyText)
                        .font(SkogaFont.body(13))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .frame(minHeight: 100, maxHeight: 220)
                        .background(p.paper)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.rule, lineWidth: Tokens.Hairline.width))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                reviewersField
            }
            .padding(.horizontal, 22).padding(.vertical, 18)
        }
    }

    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(SkogaFont.mono(10))
                .tracking(1.0)
                .foregroundStyle(p.inkFaint)
            content()
        }
    }

    private var branchRow: some View {
        HStack(spacing: 10) {
            branchPill(label: "from", text: agent.branch)
            Text("→")
                .font(SkogaFont.mono(13))
                .foregroundStyle(p.inkFaint)
            branchPill(label: "into", text: "main")
        }
    }

    private func branchPill(label: String, text: String) -> some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(SkogaFont.monoTiny(9.5))
                .tracking(0.55)
                .foregroundStyle(p.inkFaint)
            Text(text)
                .font(SkogaFont.mono(11.5))
                .foregroundStyle(p.ink)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.paper2)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.chip))
    }

    private var diffStat: some View {
        HStack(spacing: 18) {
            Text("\(agent.files) files")
                .font(SkogaFont.mono(11))
                .foregroundStyle(p.ink2)
            Text("+\(agent.commits * 18)")
                .font(SkogaFont.mono(11))
                .foregroundStyle(p.forest)
            Text("−\(agent.commits * 4)")
                .font(SkogaFont.mono(11))
                .foregroundStyle(p.ember)
            Spacer()
            HStack(spacing: 2) {
                ForEach(0..<18, id: \.self) { i in
                    Rectangle()
                        .fill(squareColor(i))
                        .frame(width: 7, height: 7)
                        .cornerRadius(1.5)
                }
            }
        }
    }

    private func squareColor(_ i: Int) -> Color {
        if i < 13 { return p.forest }
        if i < 16 { return p.ember }
        return p.paper4
    }

    private var reviewersField: some View {
        HStack {
            Text("REVIEWERS")
                .font(SkogaFont.mono(10))
                .tracking(1.0)
                .foregroundStyle(p.inkFaint)
            Spacer()
            HStack(spacing: 6) {
                pill(text: "@mikael", fill: p.paper2)
                pill(text: "+ add", fill: p.paper)
            }
        }
    }

    private func pill(text: String, fill: Color) -> some View {
        Text(text)
            .font(SkogaFont.mono(11))
            .foregroundStyle(p.ink2)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(p.rule, lineWidth: Tokens.Hairline.width))
    }

    private var foot: some View {
        HStack(spacing: 8) {
            Text("PR feedback will route back to \(agent.name) automatically.")
                .font(SkogaFont.monoSmall(10.5))
                .foregroundStyle(p.inkFaint)
            Spacer()
            Button {
                state.prAgentId = nil
            } label: {
                Text("Cancel")
                    .font(SkogaFont.smallMedium(11.5))
                    .foregroundStyle(p.ink2)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .fill(p.paper)
                            .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                    )
            }
            .buttonStyle(.plain)

            Button {
                state.prAgentId = nil
                state.showToast("Opened PR for \(agent.name). Routing review back to the agent.")
            } label: {
                HStack(spacing: 6) {
                    Image(skoga: .github).skogaIconSize(12)
                    Text("Open PR on GitHub").font(SkogaFont.bodyMedium(12))
                }
                .padding(.horizontal, 14)
                .frame(height: 28)
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.forest))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(p.paper2)
        .overlay(alignment: .top) { Hairline() }
    }
}
