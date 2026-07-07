import SwiftUI
import AppKit

/// Step 4 — Plant the forest. Workspace folder picker + a lightweight
/// access check (workspace exists · writeable). The `skogad` daemon is
/// installed separately via `brew install getskoga/tap/skoga` and started
/// with `skoga daemon start` — the `DaemonStatusBanner` in the main window
/// surfaces that hint when it isn't reachable.
struct StepWorkspace: View {
    @Environment(\.palette) private var p
    @Environment(OnboardingState.self) private var state
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHead(
                eyebrow: "Step 4 · Plant the forest",
                title: "Where should the agents live?",
                body: AnyView(StepLede("Each run gets its own git worktree, fully isolated. Pick the folder your repos already live in — Skoga creates a sibling .skoga/worktrees directory inside."))
            )

            workspaceCard
            envCheckCard

            OnboardingActions(onBack: onBack) {
                OBPrimaryButton(label: "Continue", action: onNext)
            }
        }
    }

    private var workspaceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WORKSPACE FOLDER")
                .font(SkogaFont.monoTiny(10))
                .tracking(1.0)
                .foregroundStyle(p.inkFaint)

            HStack(spacing: 8) {
                TextField("~/code", text: Binding(
                    get: { state.data.workspace },
                    set: { newValue in state.update { $0.workspace = newValue } }
                ))
                    .textFieldStyle(.plain)
                    .font(SkogaFont.mono(12.5))
                    .foregroundStyle(p.ink)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(p.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                OBGhostButton(label: "Choose…", action: choose)
            }

            (Text("Where your repos live today. Worktrees go in ").foregroundStyle(p.inkMute) +
             Text(".skoga/worktrees").font(SkogaFont.mono(10.5)).foregroundStyle(p.ink) +
             Text(" inside this folder — each agent gets its own, fully isolated from the others by git.").foregroundStyle(p.inkMute))
                .font(SkogaFont.body(11.5))
                .lineSpacing(11.5 * 0.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(p.paper2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
    }

    /// Only checks the app can genuinely perform are shown here. The old
    /// card fabricated a "git 2.47.0 detected" row — a sandboxed app
    /// can't run `git --version`, and made-up results are exactly what
    /// App Review screens for. Toolchain checks (git, tmux, claude) are
    /// the daemon's concern; `DaemonStatusBanner` reports its
    /// reachability for real once the wizard closes.
    private var envCheckCard: some View {
        VStack(spacing: 6) {
            envRow(
                label: "workspace",
                value: workspaceStatus.message,
                ok: workspaceStatus.ok
            )
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(p.paper2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
    }

    /// Live filesystem probe of the typed/chosen workspace folder —
    /// exists, is a directory, is writeable. Recomputed on every render
    /// (each keystroke in the field); two `stat` calls are trivially
    /// cheap. Under App Sandbox the answers stay honest: a folder chosen
    /// via the panel is granted and reports writeable, while a merely
    /// typed path the sandbox can't reach reports as not accessible.
    private var workspaceStatus: (ok: Bool, message: String) {
        let raw = state.data.workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return (false, "choose a folder to check access")
        }
        let path = (raw as NSString).expandingTildeInPath
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return (false, "not accessible — use Choose… to pick an existing folder")
        }
        guard fm.isWritableFile(atPath: path) else {
            return (false, "not writeable — Skoga can't create worktrees here")
        }
        return (true, "writeable · \(raw)")
    }

    private func envRow(label: String, value: String, ok: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(ok ? p.forest : p.amber)
                    .frame(width: 18, height: 18)
                Image(skoga: ok ? .check : .alert).skogaIconSize(11)
                    .foregroundStyle(Color.oklch(0.97, 0.02, 90))
            }
            .frame(width: 22)
            Text(label)
                .font(SkogaFont.mono(11.5).weight(.medium))
                .foregroundStyle(p.ink2)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(SkogaFont.mono(11.5))
                .foregroundStyle(p.inkMute)
            Spacer(minLength: 0)
        }
    }

    /// Drive a folder picker through NSOpenPanel. The text field is the
    /// source of truth; this just shortcuts the typing for users who'd
    /// rather click. Cancelling leaves whatever was in the field intact.
    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.title = "Workspace folder"
        if panel.runModal() == .OK, let url = panel.url {
            state.update { $0.workspace = url.path }
        }
    }
}
