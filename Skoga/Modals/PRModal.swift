import SwiftUI

struct PRModal: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var state: AppState
    let agent: Agent

    /// Title and body start empty and get populated once `skoga land
    /// --preview` round-trips. The previous mock template (hardcoded
    /// "## Summary / ## What changed / ## Tests") was at odds with the
    /// CLI's actual default-message logic — pre-filling with what the
    /// CLI would itself produce keeps the modal a true preview rather
    /// than a parallel source of truth.
    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var phase: Phase = .loading
    @State private var didCancelDismiss = false

    /// Lifecycle phases for the modal. Drives the submit button (label /
    /// disabled state), the inline error row, and whether the fields are
    /// editable. `failed` keeps the user's edits — the error is shown
    /// alongside an enabled Retry, not behind a wipe.
    enum Phase: Equatable {
        case loading
        case ready
        case submitting
        case failed(String)
    }

    var body: some View {
        ZStack {
            p.modalScrim
                .ignoresSafeArea()
                .onTapGesture {
                    // Tapping the scrim during an in-flight land would
                    // strand the CLI subprocess — `skoga land` doesn't get
                    // a SIGTERM from us closing the modal. Block dismissal
                    // there until the call resolves.
                    if phase != .submitting { state.prAgentId = nil }
                }

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
        .task { await loadPreview() }
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
                if phase == .loading { draftingIndicator }
                field(label: "Title") {
                    TextField("", text: $title)
                        .textFieldStyle(.plain)
                        .font(SkogaFont.body(13))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(p.paper)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.rule, lineWidth: Tokens.Hairline.width))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .disabled(phase == .loading)
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
                        .disabled(phase == .loading)
                }
                reviewersField
            }
            .padding(.horizontal, 22).padding(.vertical, 18)
        }
    }

    /// Small status row shown while `previewPR` is in flight. The call
    /// shells out to `claude -p` against the session's diff — typically a
    /// 5-30s wait — so without this the modal looks frozen, and users
    /// reflexively dismiss it before the draft lands.
    private var draftingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .progressViewStyle(.circular)
            Text("Drafting commit message with Claude…")
                .font(SkogaFont.monoSmall(11))
                .foregroundStyle(p.inkMute)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(p.paper2)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.chip))
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
        VStack(spacing: 0) {
            if case .failed(let msg) = phase {
                // Cap the error block so a long stderr (e.g. a multi-line
                // git failure) doesn't push the Cancel / Retry buttons
                // off-screen. ScrollView preserves the full message —
                // useful since CLI errors carry the actual diagnostic
                // (e.g. "nothing to commit, working tree clean") that the
                // user needs to act on.
                ScrollView {
                    HStack(alignment: .top, spacing: 6) {
                        Image(skoga: .alert)
                            .skogaIconSize(11)
                            .foregroundStyle(p.ember)
                            .padding(.top, 2)
                        Text(msg)
                            .font(SkogaFont.monoSmall(10.5))
                            .foregroundStyle(p.ember)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 22).padding(.vertical, 10)
                }
                .frame(maxHeight: 120)
                .background(p.emberSoft.opacity(0.35))
                .overlay(alignment: .top) { Hairline() }
            }

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
                .disabled(phase == .submitting)

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 6) {
                        if phase == .submitting {
                            ProgressView()
                                .controlSize(.small)
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(skoga: .github).skogaIconSize(12)
                        }
                        Text(submitLabel).font(SkogaFont.bodyMedium(12))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.forest))
                    .opacity(submitDisabled ? 0.55 : 1)
                }
                .buttonStyle(.plain)
                .disabled(submitDisabled)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(p.paper2)
            .overlay(alignment: .top) { Hairline() }
        }
    }

    private var submitLabel: String {
        switch phase {
        case .submitting: return "Opening PR…"
        case .failed:     return "Retry"
        default:          return "Open PR on GitHub"
        }
    }

    /// Disable Open PR while we don't yet have a real preview to send, or
    /// while a land is in flight. We don't gate on title/body emptiness —
    /// the CLI would reject an empty commit message anyway, and surfacing
    /// the error inline (with the user's text preserved) is better than
    /// silently disabling the button.
    private var submitDisabled: Bool {
        phase == .loading || phase == .submitting
    }

    private func loadPreview() async {
        // Avoid re-fetching when the user retries — `phase` is already
        // `.failed` and we keep their edits intact; only run on the very
        // first appear or after an explicit cancel + reopen.
        guard phase == .loading else { return }
        do {
            let preview = try await state.client.previewPR(for: agent.id)
            title = preview.title
            bodyText = preview.body
            phase = .ready
        } catch {
            // Pre-fill from session.task as a best-effort fallback so the
            // user can still type something into a useful starting state
            // even if `--preview` failed (older CLI, no commits yet, etc.).
            let clean = agent.task.hasSuffix(".") ? String(agent.task.dropLast()) : agent.task
            if title.isEmpty { title = clean }
            phase = .failed(error.localizedDescription)
        }
    }

    private func submit() async {
        phase = .submitting
        do {
            try await state.client.landPR(for: agent.id, title: title, body: bodyText)
            state.prAgentId = nil
            state.showToast("Opened PR for \(agent.name). Routing review back to the agent.")
            await state.refresh()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
