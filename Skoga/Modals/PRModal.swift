import SwiftUI

struct PRModal: View {
    @Environment(\.palette) private var p
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(ModalState.self) private var modal
    @Environment(DaemonClientHolder.self) private var daemon
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
    /// Real `session.diff_stat` from the daemon. `nil` while the call is
    /// in flight or against a daemon that doesn't expose the RPC; the
    /// diff-stat row stays hidden in both cases rather than showing the
    /// old `commits * 18` fiction or a placeholder em-dash.
    @State private var diff: RPCDiffStat?

    /// Lifecycle phases for the modal. Drives the submit button (label /
    /// disabled state), the inline error row, and whether the fields are
    /// editable. `failed` keeps the user's edits — the error is shown
    /// alongside an enabled Retry, not behind a wipe. There's no
    /// `submitting` case because `submit()` dismisses the modal up front
    /// and runs `landPR` in a detached task — the user sees a toast, not
    /// an in-modal spinner.
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    var body: some View {
        ZStack {
            p.modalScrim
                .ignoresSafeArea()
                .onTapGesture { modal.prAgentId = nil }

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
        // Two .task modifiers run in parallel so the diff-stat header
        // doesn't wait on Claude's 5-30s commit-message draft. They
        // touch independent state (`phase`/`title`/`bodyText` vs `diff`)
        // so there's no race; if a future change needs `loadDiffStat`
        // to gate on `phase`, fold both into one `async let` task.
        .task { await loadPreview() }
        .task { await loadDiffStat() }
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
            Button { modal.prAgentId = nil } label: {
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
                if let diff { diffStat(diff) }
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

    private func diffStat(_ diff: RPCDiffStat) -> some View {
        let split = Self.squareSplit(adds: diff.lines_added, removes: diff.lines_removed)
        return HStack(spacing: 18) {
            Text("\(diff.files_changed) \(diff.files_changed == 1 ? "file" : "files")")
                .font(SkogaFont.mono(11))
                .foregroundStyle(p.ink2)
            Text("+\(diff.lines_added)")
                .font(SkogaFont.mono(11))
                .foregroundStyle(p.forest)
            Text("−\(diff.lines_removed)")
                .font(SkogaFont.mono(11))
                .foregroundStyle(p.ember)
            Spacer()
            HStack(spacing: 2) {
                ForEach(0..<Self.squareCount, id: \.self) { i in
                    Rectangle()
                        .fill(Self.tileColor(i, split: split, palette: p))
                        .frame(width: 7, height: 7)
                        .cornerRadius(1.5)
                }
            }
        }
    }

    /// Total tiles in the diff-stat strip. The old hardcoded view had an
    /// arbitrary 13/3/2 split; this count is preserved so the modal
    /// layout doesn't shift, but the fill is now proportional.
    private static let squareCount = 18

    /// Color the i-th tile of the diff-stat strip given a forest/ember
    /// split. Order is forest, then ember, then muted — strip reads
    /// left-to-right as adds → removes → untouched.
    private static func tileColor(_ i: Int, split: (forest: Int, ember: Int), palette: Theme.Palette) -> Color {
        if i < split.forest { return palette.forest }
        if i < split.forest + split.ember { return palette.ember }
        return palette.paper4
    }

    /// Translate `(adds, removes)` into a `(forest, ember)` tile count
    /// out of `squareCount`. Returns `(0, 0)` for a no-op diff (both
    /// sides zero) so all tiles render muted. Otherwise each non-zero
    /// side gets at least one tile (a 1-line removal among 1000 adds
    /// still shows red), and the remainder splits by ratio.
    private static func squareSplit(adds rawAdds: Int, removes rawRemoves: Int) -> (forest: Int, ember: Int) {
        let adds = max(0, rawAdds)
        let removes = max(0, rawRemoves)
        let total = adds + removes
        guard total > 0 else { return (0, 0) }
        if removes == 0 { return (squareCount, 0) }
        if adds == 0 { return (0, squareCount) }
        let raw = (Double(adds) / Double(total)) * Double(squareCount)
        let forest = max(1, min(squareCount - 1, Int(raw.rounded())))
        return (forest, squareCount - forest)
    }

    private var reviewersField: some View {
        // Reviewer chip pre-fills from Settings → GitHub's persisted
        // `default_reviewer`; the user adds others manually here.
        HStack {
            Text("REVIEWERS")
                .font(SkogaFont.mono(10))
                .tracking(1.0)
                .foregroundStyle(p.inkFaint)
            Spacer()
            HStack(spacing: 6) {
                if let reviewer = daemon.githubStatus?.default_reviewer, !reviewer.isEmpty {
                    pill(text: reviewer, fill: p.paper2)
                }
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
                    modal.prAgentId = nil
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
                    submit()
                } label: {
                    HStack(spacing: 6) {
                        Image(skoga: .github).skogaIconSize(12)
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
        case .failed: return "Retry"
        default:      return "Open PR on GitHub"
        }
    }

    /// Disable Open PR while we don't yet have a real preview to send.
    /// We don't gate on title/body emptiness — the CLI would reject an
    /// empty commit message anyway, and surfacing the error inline (with
    /// the user's text preserved) is better than silently disabling the
    /// button. We also don't gate on an in-flight land, because `submit`
    /// dismisses the modal up front and reports progress via toasts.
    private var submitDisabled: Bool {
        phase == .loading
    }

    /// Fetch real diff numbers in parallel with the Claude-drafted
    /// preview. The modal's primary job is to let the user edit the PR
    /// title/body, so a daemon that can't produce diff stats shouldn't
    /// gate the flow — the row just hides until we have real numbers.
    /// We do/catch (vs `try?`) so the intent is explicit: anything
    /// thrown here is suppressed on purpose, and a real transport
    /// failure will already be surfacing through `loadPreview`'s
    /// `phase = .failed` path on the same modal.
    private func loadDiffStat() async {
        guard diff == nil else { return }
        do {
            diff = try await daemon.client.diffStat(for: agent.id)
        } catch {
            // Leave `diff == nil` so the diff-stat row stays hidden.
        }
    }

    private func loadPreview() async {
        // Avoid re-fetching when the user retries — `phase` is already
        // `.failed` and we keep their edits intact; only run on the very
        // first appear or after an explicit cancel + reopen.
        guard phase == .loading else { return }
        do {
            let preview = try await daemon.client.previewPR(for: agent.id)
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

    /// `skoga land` can take 10-30s — push, squash, then `gh pr create`
    /// round-tripping to GitHub. Blocking the modal on that with a
    /// spinner trained users to assume the app had hung. Instead, dismiss
    /// up front, toast that work is in flight, and surface the outcome
    /// (success or failure) via a follow-up toast when `landPR` resolves.
    /// The `Task` is detached from the view lifecycle so the modal can
    /// disappear without cancelling the in-flight CLI call.
    private func submit() {
        let agentName = agent.name
        let agentId = agent.id
        let prTitle = title
        let prBody = bodyText
        let client = daemon.client
        let coordinator = coordinator
        let modal = modal

        modal.prAgentId = nil
        modal.showToast("Opening PR for \(agentName) on GitHub…")

        Task { @MainActor in
            do {
                try await client.landPR(for: agentId, title: prTitle, body: prBody)
                // `skoga land` can exit 0 even when its internal
                // `gh pr create` step fails (e.g. `gh` missing, token
                // expired) — the push succeeds but no PR is opened.
                // Refresh and check for a real prUrl before claiming
                // success, so the user isn't told a PR exists when none
                // does.
                await coordinator.refresh()
                let updated = coordinator.roster.agents.first(where: { $0.id == agentId })
                if let url = updated?.prUrl, url != "#" {
                    modal.showToast("Opened PR for \(agentName). Routing review back to the agent.")
                } else {
                    modal.showToast("Pushed branch for \(agentName), but GitHub didn't return a PR URL. Check that `gh` is installed and authenticated, then retry.", duration: 8)
                }
            } catch {
                modal.showToast("Failed to open PR for \(agentName): \(error.localizedDescription)", duration: 8)
            }
        }
    }
}
