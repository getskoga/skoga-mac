import SwiftUI

/// Settings → GitHub. The current scope is narrow on purpose (just `gh`
/// auth + default reviewer); other sections will land here as the daemon
/// grows config knobs. Reads `state.githubStatus` for the current truth
/// and shells back through AppState for both reads (refresh) and the one
/// write (default reviewer).
///
/// Rendered states (in priority order):
/// 1. daemon doesn't speak `github.status` → upgrade-skogad CTA.
/// 2. fetch failed and we have nothing cached → error row with retry.
/// 3. `gh` not installed → install CTA.
/// 4. installed, not authenticated → sign-in CTA that opens a sheet
///    walking the user through `gh auth login --web` and polls until
///    the daemon reports authenticated.
/// 5. authenticated → green "Signed in" row + scopes + default
///    reviewer editor.
struct SettingsView: View {
    @Environment(\.palette) private var p
    @Environment(\.openURL) private var openURL
    @Environment(AppState.self) private var state

    @State private var showingSignIn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                githubSection
                    .padding(.top, 22)
            }
            .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(p.paper)
        .task { await state.refreshGitHubStatus() }
        .sheet(isPresented: $showingSignIn) {
            GitHubSignInSheet { showingSignIn = false }
                .environment(state)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(SkogaFont.serifTitle(26))
                .foregroundStyle(p.ink)
            Text("Manager preferences. These persist to the skogad config so they follow you across machines.")
                .font(SkogaFont.body(13))
                .foregroundStyle(p.inkMute)
                .lineSpacing(13 * 0.5)
                .frame(maxWidth: 540, alignment: .leading)
        }
    }

    // MARK: – GitHub section

    private var githubSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("GitHub", subtitle: "Used by Open as PR to push branches and open pull requests.")
                .padding(.bottom, 14)

            // Priority order matters here: daemon-unsupported wins over a
            // missing status because the latter is a *consequence* of the
            // former. Likewise, a transport error with no cached status
            // wins over the loading spinner — sitting on "Checking gh
            // status…" forever is worse than a clear failure.
            if state.githubDaemonUnsupported {
                daemonUnsupportedRow
            } else if state.githubStatus == nil, let err = state.githubStatusError {
                errorRow(err)
            } else if let s = state.githubStatus {
                if !s.installed {
                    notInstalledRow
                } else if !s.authenticated {
                    notAuthedRow
                } else {
                    authedRow(s)
                    scopesRow(s)
                        .padding(.top, 10)
                    defaultReviewerField(s)
                        .padding(.top, 22)
                }
            } else {
                loadingRow
            }
        }
        .padding(18)
        .background(p.paper2)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(skoga: .github).skogaIconSize(14).foregroundStyle(p.ink2)
                Text(title)
                    .font(SkogaFont.serifHeading(18))
                    .foregroundStyle(p.ink)
            }
            Text(subtitle)
                .font(SkogaFont.body(12))
                .foregroundStyle(p.inkMute)
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Checking gh status…")
                .font(SkogaFont.mono(11.5))
                .foregroundStyle(p.inkMute)
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var daemonUnsupportedRow: some View {
        statusRow(
            dot: p.amber,
            headline: "Skoga daemon is too old",
            detail: "This skogad build doesn't speak `github.status` yet. Upgrade the daemon to enable Settings → GitHub.",
            cta: .init(label: "Re-check", icon: .loop) {
                Task { await state.refreshGitHubStatus() }
            },
            secondary: nil
        )
    }

    private func errorRow(_ message: String) -> some View {
        statusRow(
            dot: p.ember,
            headline: "Couldn't reach the daemon",
            detail: message,
            cta: .init(label: "Retry", icon: .loop) {
                Task { await state.refreshGitHubStatus() }
            },
            secondary: nil
        )
    }

    private var notInstalledRow: some View {
        statusRow(
            dot: p.ember,
            headline: "GitHub CLI not installed",
            detail: "Skoga's Open-as-PR flow shells out to `gh`. Install it to enable PR creation.",
            cta: .init(label: "Install instructions", icon: .doc) {
                if let url = URL(string: "https://cli.github.com/") { openURL(url) }
            },
            secondary: .init(label: "Re-check", icon: .loop) {
                Task { await state.refreshGitHubStatus() }
            }
        )
    }

    private var notAuthedRow: some View {
        statusRow(
            dot: p.amber,
            headline: "Not signed in to GitHub",
            detail: "`gh` is installed but no account is authenticated. Sign in to open PRs from Skoga.",
            cta: .init(label: "Sign in to GitHub", icon: .github) {
                showingSignIn = true
            },
            secondary: .init(label: "Re-check", icon: .loop) {
                Task { await state.refreshGitHubStatus() }
            }
        )
    }

    private func authedRow(_ s: RPCGitHubStatus) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(p.forest)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(p.forest.opacity(0.22), lineWidth: 3))
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Signed in as")
                        .font(SkogaFont.body(13))
                        .foregroundStyle(p.ink2)
                    Text("@\(s.login ?? "—")")
                        .font(SkogaFont.mono(12.5))
                        .foregroundStyle(p.ink)
                }
                Text("Skoga will use this account for Open as PR.")
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                secondaryButton(label: "Sign out…", icon: .close) {
                    copyAndToastSignOutCommand()
                }
                secondaryButton(label: "Re-check", icon: .loop) {
                    Task { await state.refreshGitHubStatus() }
                }
            }
        }
    }

    /// Scopes `gh pr create` needs to function end-to-end. If the live
    /// account is missing any of them, the row flips to an amber warning
    /// chip so the user understands why a future Open-as-PR might fail
    /// despite "Signed in" being green.
    private static let requiredScopes: Set<String> = ["repo", "workflow"]

    private func scopesRow(_ s: RPCGitHubStatus) -> some View {
        // gh's token-based logins sometimes report no scopes at all, which
        // is a real "we don't know" case rather than "we know it's empty".
        // Render the row only when the daemon gave us a non-empty list.
        Group {
            if !s.scopes.isEmpty {
                let granted = Set(s.scopes)
                let missing = Self.requiredScopes.subtracting(granted)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("SCOPES")
                            .font(SkogaFont.mono(10))
                            .tracking(1.0)
                            .foregroundStyle(p.inkFaint)
                        if !missing.isEmpty {
                            Text("MISSING \(missing.sorted().joined(separator: ", ").uppercased())")
                                .font(SkogaFont.monoTiny(9.5))
                                .tracking(0.8)
                                .foregroundStyle(p.amber)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                                        .stroke(p.amber.opacity(0.45), lineWidth: Tokens.Hairline.width)
                                )
                        }
                        Spacer()
                    }
                    HStack(spacing: 6) {
                        ForEach(s.scopes, id: \.self) { scope in
                            Text(scope)
                                .font(SkogaFont.mono(10.5))
                                .foregroundStyle(p.ink2)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(p.paper))
                                .overlay(Capsule().stroke(p.rule, lineWidth: Tokens.Hairline.width))
                        }
                    }
                    if !missing.isEmpty {
                        Text("Re-run `gh auth refresh -s \(missing.sorted().joined(separator: ","))` in your terminal.")
                            .font(SkogaFont.monoSmall(10.5))
                            .foregroundStyle(p.inkMute)
                    }
                }
            }
        }
    }

    private func defaultReviewerField(_ s: RPCGitHubStatus) -> some View {
        // Tie the editor's identity to the signed-in login so switching
        // accounts (sign out → sign in as someone else) remounts the
        // editor with a clean baseline instead of carrying over a stale
        // draft from the previous account.
        DefaultReviewerEditor(initial: s.default_reviewer ?? "")
            .id(s.login ?? "")
    }

    private func copyAndToastSignOutCommand() {
        let command = "gh auth logout --hostname github.com"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        state.showToast("Copied `\(command)` — run it in your terminal.")
    }

    // MARK: – Generic status row

    private struct ActionSpec {
        let label: String
        let icon: SkogaIcon
        let action: () -> Void
    }

    private func statusRow(
        dot: Color,
        headline: String,
        detail: String,
        cta: ActionSpec,
        secondary: ActionSpec?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(dot)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(dot.opacity(0.22), lineWidth: 3))
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(SkogaFont.bodyMedium(13))
                    .foregroundStyle(p.ink)
                Text(detail)
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    primaryButton(label: cta.label, icon: cta.icon, action: cta.action)
                    if let secondary {
                        secondaryButton(label: secondary.label, icon: secondary.icon, action: secondary.action)
                    }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }

    private func primaryButton(label: String, icon: SkogaIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(skoga: icon).skogaIconSize(12)
                Text(label).font(SkogaFont.bodyMedium(12))
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.forest))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(label: String, icon: SkogaIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(skoga: icon).skogaIconSize(12)
                Text(label).font(SkogaFont.bodyMedium(12))
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .foregroundStyle(p.ink2)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(p.paper)
                    .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Default reviewer editor

/// Local editor for the default reviewer so the field can track its own
/// dirty state and surface a Save / Revert pair without firing on every
/// keystroke. Lifting `value` into AppState would round-trip a daemon
/// write on every keypress, which is both wasteful and surprising — the
/// PR modal would update mid-typing.
private struct DefaultReviewerEditor: View {
    @Environment(\.palette) private var p
    @Environment(AppState.self) private var state

    /// Persisted baseline at mount time (or last successful save). The
    /// dirty flag is computed against this — keep it frozen while the
    /// user is mid-edit, otherwise a background refresh would silently
    /// drop the "UNSAVED" chip and make Save a no-op.
    @State private var persisted: String
    @State private var draft: String
    @State private var saving = false

    init(initial: String) {
        _persisted = State(initialValue: initial)
        _draft = State(initialValue: initial)
    }

    private var dirty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines) != persisted }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("DEFAULT REVIEWER")
                    .font(SkogaFont.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(p.inkFaint)
                if dirty {
                    Text("UNSAVED")
                        .font(SkogaFont.monoTiny(9.5))
                        .tracking(0.8)
                        .foregroundStyle(p.amber)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                                .stroke(p.amber.opacity(0.45), lineWidth: Tokens.Hairline.width)
                        )
                }
                Spacer()
            }

            HStack(spacing: 8) {
                TextField("@username or org/team", text: $draft)
                    .textFieldStyle(.plain)
                    .font(SkogaFont.mono(12))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(p.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .disabled(saving)
                    .onSubmit { Task { await save() } }

                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: 6) {
                        if saving {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(skoga: .check).skogaIconSize(11)
                        }
                        Text(saving ? "Saving…" : "Save").font(SkogaFont.bodyMedium(12))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.forest))
                    .opacity((dirty && !saving) ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .disabled(!dirty || saving)

                Button {
                    draft = persisted
                } label: {
                    Text("Revert")
                        .font(SkogaFont.bodyMedium(12))
                        .foregroundStyle(p.ink2)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                                .fill(p.paper)
                                .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                        )
                        .opacity(dirty && !saving ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .disabled(!dirty || saving)
            }

            Text("Pre-fills the reviewer chip in the Open as PR modal. Leave blank to skip.")
                .font(SkogaFont.body(11.5))
                .foregroundStyle(p.inkMute)
        }
        // Only adopt a daemon-side change when the editor is clean.
        // The earlier version unconditionally overwrote `persisted`,
        // which made `dirty` collapse the moment a background refresh
        // landed mid-edit — the UNSAVED chip would disappear and Save
        // would no-op against the new baseline. Hold the baseline
        // frozen until the user finishes (or reverts).
        .onChange(of: state.githubStatus?.default_reviewer) { _, newValue in
            let resolved = newValue ?? ""
            guard !saving, draft == persisted else { return }
            draft = resolved
            persisted = resolved
        }
    }

    private func save() async {
        guard dirty else { return }
        saving = true
        defer { saving = false }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        await state.setDefaultReviewer(trimmed)
        // setDefaultReviewer updates state.githubStatus; mirror it here
        // so the dirty flag clears without waiting for onChange (which
        // fires asynchronously and can leave a stale "UNSAVED" chip up
        // for a frame).
        persisted = state.githubStatus?.default_reviewer ?? ""
        draft = persisted
    }
}

// MARK: – Sign-in sheet

/// Step-by-step prompt for completing `gh auth login --web` in a separate
/// terminal. The GUI can't drive `gh`'s interactive flow directly (it
/// opens a browser + reads from stdin), so we surface the canonical
/// command and poll `github.status` until the user has finished.
///
/// Auto-dismisses when polling detects `authenticated == true`. Also
/// auto-dismisses on `.task` if we open the sheet already-authed (e.g.
/// the user signed in via terminal between tapping "Sign in" and the
/// sheet animating in, or re-tapped Sign in after a successful flow) —
/// `onChange` would not fire in that case because the value didn't
/// change.
private struct GitHubSignInSheet: View {
    @Environment(\.palette) private var p
    @Environment(AppState.self) private var state
    let dismiss: () -> Void

    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            stepsBody
            foot
        }
        .frame(width: 520)
        .background(p.paper)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.modal)
                .stroke(p.ruleHard, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.modal))
        .task {
            // If the sheet opens already-authed, onChange won't fire
            // (no transition). Dismiss immediately so the user doesn't
            // see a confusing "Sign in" sheet over an already-green
            // Settings row.
            if state.githubStatus?.authenticated == true {
                dismiss()
                return
            }
            startPolling()
        }
        .onDisappear { pollTask?.cancel() }
        .onChange(of: state.githubStatus?.authenticated) { _, authed in
            // The daemon's reply landed authenticated — drop the sheet.
            // Toast left to the user's eyes; the Settings row will flip
            // to the green "Signed in" state on the same tick.
            if authed == true {
                state.showToast("Signed in to GitHub as @\(state.githubStatus?.login ?? "—").")
                dismiss()
            }
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
                Text("Sign in to GitHub")
                    .font(SkogaFont.serifHeading(20))
                    .foregroundStyle(p.ink)
                Text("Skoga polls `gh` while you complete the flow in your terminal.")
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
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
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var stepsBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            step(
                number: 1,
                title: "Open Terminal",
                body: "Any terminal app that has `gh` on its PATH. We can launch the default Terminal.app for you.",
                command: nil,
                trailing: AnyView(openTerminalButton)
            )
            step(
                number: 2,
                title: "Run gh auth login",
                body: "Pick GitHub.com → HTTPS → Login with a web browser. gh will open the device-flow page in your browser.",
                command: "gh auth login --web",
                trailing: nil
            )
            step(
                number: 3,
                title: "Finish in the browser",
                body: "Paste the one-time code and grant the scopes gh asks for (repo, read:org, workflow).",
                command: nil,
                trailing: nil
            )

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Watching for auth — should flip within a few seconds of completion.")
                    .font(SkogaFont.monoSmall(11))
                    .foregroundStyle(p.inkMute)
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private var openTerminalButton: some View {
        Button {
            let url = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 4) {
                Image(skoga: .chevron).skogaIconSize(10)
                Text("Open Terminal").font(SkogaFont.monoSmall(10.5))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(p.ink2)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                    .fill(p.paper)
                    .hairlineBorder(p.rule, radius: Tokens.Radius.tiny)
            )
        }
        .buttonStyle(.plain)
    }

    private func step(number: Int, title: String, body: String, command: String?, trailing: AnyView?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(SkogaFont.mono(11.5))
                .foregroundStyle(p.ink2)
                .frame(width: 22, height: 22)
                .background(Circle().fill(p.paper2))
                .overlay(Circle().stroke(p.rule, lineWidth: Tokens.Hairline.width))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(SkogaFont.bodyMedium(12.5))
                        .foregroundStyle(p.ink)
                    Spacer(minLength: 0)
                    if let trailing { trailing }
                }
                Text(body)
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
                if let command {
                    CommandTile(text: command)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var foot: some View {
        HStack(spacing: 8) {
            Spacer()
            Button(action: dismiss) {
                Text("Close")
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
                Task { await checkNow() }
            } label: {
                HStack(spacing: 6) {
                    Image(skoga: .check).skogaIconSize(11)
                    Text("Done — check now").font(SkogaFont.bodyMedium(12))
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.forest))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(p.paper2)
        .overlay(alignment: .top) { Hairline() }
    }

    /// Manual "I finished, check now" tap. Refreshes and — if the user
    /// still isn't authed — toasts negative feedback so the button
    /// doesn't appear to do nothing. (The auth-success path is handled
    /// by the existing `onChange` toast + dismiss.)
    private func checkNow() async {
        await state.refreshGitHubStatus()
        if state.githubStatus?.authenticated != true {
            state.showToast("Still not signed in. Finish `gh auth login` in your terminal.")
        }
    }

    /// Poll every 2s while the sheet is up. Slow enough that a user
    /// finishing the flow sees a sub-3-second flip; fast enough that the
    /// daemon's tiny `gh auth status` shell-out isn't noticeable load.
    /// Stops when the sheet disappears (`onDisappear` cancels the task).
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { break }
                await state.refreshGitHubStatus()
            }
        }
    }
}

/// Selectable monospace tile for the `gh auth login` command. A plain
/// inline-code span would let users select but not copy in one click;
/// the tile carries an explicit Copy button so the canonical step ends
/// with one keystroke worth of friction.
private struct CommandTile: View {
    @Environment(\.palette) private var p
    let text: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(SkogaFont.mono(12))
                .foregroundStyle(p.ink)
                .textSelection(.enabled)
                .padding(.leading, 10)
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    copied = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(skoga: copied ? .check : .doc).skogaIconSize(10)
                    Text(copied ? "Copied" : "Copy")
                        .font(SkogaFont.monoSmall(10.5))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .foregroundStyle(p.ink2)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                        .fill(p.paper)
                        .hairlineBorder(p.rule, radius: Tokens.Radius.tiny)
                )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
        }
        .padding(.vertical, 6)
        .background(p.paper2)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
