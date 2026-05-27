import SwiftUI
import AppKit

/// Lightweight in-app bug reporter. Captures the two questions every
/// triage instinctively asks ("what were you trying to do?" / "what
/// happened instead?") and files a labelled issue against
/// `getskoga/skoga-mac` via `gh issue create`. Falls back to opening a
/// pre-filled new-issue URL in the browser when `gh` isn't reachable or
/// the user isn't signed in — the report still lands, just with a
/// second click from the user.
struct BugReportModal: View {
    @Environment(\.palette) private var p
    @Environment(ModalState.self) private var modal

    @State private var intent: String = ""
    @State private var actual: String = ""
    @State private var phase: Phase = .ready

    enum Phase: Equatable {
        case ready
        case submitting
        case failed(String)
        // Success is a transient state — modal dismisses on the same
        // tick, so we don't need a `.success` case here.
    }

    var body: some View {
        ZStack {
            p.modalScrim
                .ignoresSafeArea()
                .onTapGesture {
                    if phase != .submitting { modal.bugReportOpen = false }
                }

            VStack(spacing: 0) {
                head
                modalBody
                foot
            }
            .frame(width: 540)
            .frame(maxHeight: 640)
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
                RoundedRectangle(cornerRadius: 8).fill(p.amberSoft)
                Image(skoga: .bug).skogaIconSize(18).foregroundStyle(p.amber)
            }
            .frame(width: 36, height: 36)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.amber.opacity(0.4), lineWidth: Tokens.Hairline.width))

            VStack(alignment: .leading, spacing: 2) {
                Text("Report a bug")
                    .font(SkogaFont.serifHeading(21))
                    .foregroundStyle(p.ink)
                Text("Files a labelled issue in getskoga/skoga-mac")
                    .font(SkogaFont.mono(11))
                    .foregroundStyle(p.inkMute)
            }
            Spacer(minLength: 0)
            Button {
                if phase != .submitting { modal.bugReportOpen = false }
            } label: {
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
            .disabled(phase == .submitting)
        }
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 14)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var modalBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                field(label: "What were you trying to do?") {
                    editor($intent, placeholder: "e.g. open a PR for the agent I just dispatched")
                }
                field(label: "What happened instead?") {
                    editor($actual, placeholder: "e.g. the modal opened but the title field stayed empty for 30s")
                }
                Text("Skoga attaches the app version and macOS version to the issue.")
                    .font(SkogaFont.body(11.5))
                    .foregroundStyle(p.inkMute)
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

    private func editor(_ text: Binding<String>, placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .font(SkogaFont.body(13))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(minHeight: 80, maxHeight: 160)
                .background(p.paper)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.rule, lineWidth: Tokens.Hairline.width))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .disabled(phase == .submitting)

            // Manual placeholder: SwiftUI's TextEditor doesn't take one,
            // and an empty editor looks indistinguishable from an unfocused
            // disabled field. Hide once the user types anything.
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(SkogaFont.body(13))
                    .foregroundStyle(p.inkFaint)
                    .padding(.horizontal, 13).padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
    }

    private var foot: some View {
        VStack(spacing: 0) {
            if case .failed(let msg) = phase {
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
                .frame(maxHeight: 110)
                .background(p.emberSoft.opacity(0.35))
                .overlay(alignment: .top) { Hairline() }
            }

            HStack(spacing: 8) {
                Spacer()
                Button {
                    if phase != .submitting { modal.bugReportOpen = false }
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
        case .submitting: return "Filing issue…"
        case .failed:     return "Retry"
        default:          return "File issue"
        }
    }

    /// At least one of the two prompts must have content. We don't require
    /// both — a one-liner ("the app crashed on startup") is still a useful
    /// report.
    private var submitDisabled: Bool {
        if phase == .submitting { return true }
        let i = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = actual.trimmingCharacters(in: .whitespacesAndNewlines)
        return i.isEmpty && a.isEmpty
    }

    private func submit() async {
        phase = .submitting
        let title = BugReportFiler.deriveTitle(intent: intent, actual: actual)
        let body = BugReportFiler.composeBody(intent: intent, actual: actual)
        do {
            let url = try await BugReportFiler.fileIssue(title: title, body: body)
            modal.bugReportOpen = false
            modal.showToast("Filed bug report — \(url)")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

// MARK: – Filer

/// Builds the issue payload and shells out to `gh issue create`. Kept as
/// a separate type so the modal stays focused on layout/state and the
/// subprocess + URL-fallback logic is easy to swap (e.g. once the daemon
/// grows an `issue.create` RPC).
enum BugReportFiler {
    static let repo = "getskoga/skoga-mac"
    static let label = "user-bug-report"

    /// Derive a short, scannable issue title. Prefer the "what happened
    /// instead" line since that's the symptom; fall back to the intent.
    /// Clip to ~70 chars on a word boundary so the issue list stays
    /// readable without truncation ellipses.
    static func deriveTitle(intent: String, actual: String) -> String {
        let source = actual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? intent
            : actual
        let firstLine = source
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let raw = firstLine.isEmpty ? "User bug report" : firstLine
        if raw.count <= 70 { return raw }
        let clipped = raw.prefix(70)
        if let lastSpace = clipped.lastIndex(of: " ") {
            return String(clipped[..<lastSpace]) + "…"
        }
        return String(clipped) + "…"
    }

    static func composeBody(intent: String, actual: String) -> String {
        var lines: [String] = []
        let i = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = actual.trimmingCharacters(in: .whitespacesAndNewlines)
        if !i.isEmpty {
            lines.append("**What were you trying to do?**")
            lines.append("")
            lines.append(i)
            lines.append("")
        }
        if !a.isEmpty {
            lines.append("**What happened instead?**")
            lines.append("")
            lines.append(a)
            lines.append("")
        }
        lines.append("---")
        lines.append("")
        lines.append("**Environment**")
        lines.append("")
        lines.append("- Skoga: \(appVersion())")
        lines.append("- macOS: \(macOSVersion())")
        lines.append("")
        lines.append("_Filed from the in-app bug reporter._")
        return lines.joined(separator: "\n")
    }

    /// Try `gh issue create` first. On any failure (binary missing,
    /// not authed, network error) fall back to opening the GitHub
    /// new-issue URL with the body pre-filled — the report still lands,
    /// just with one extra click. Returns the URL of the created issue
    /// (or the prefilled-form URL in the fallback case) so the modal can
    /// surface it in the success toast.
    static func fileIssue(title: String, body: String) async throws -> String {
        do {
            return try await runGhIssueCreate(title: title, body: body)
        } catch let ghError {
            if let fallback = prefilledIssueURL(title: title, body: body) {
                await MainActor.run { NSWorkspace.shared.open(fallback) }
                return fallback.absoluteString
            }
            throw ghError
        }
    }

    private static func runGhIssueCreate(title: String, body: String) async throws -> String {
        guard let gh = resolveGh() else {
            throw BugReportError.ghMissing
        }
        let args = [
            "issue", "create",
            "--repo", repo,
            "--title", title,
            "--body", body,
            "--label", label,
        ]
        let output = try await runProcess(executable: gh, args: args)
        // `gh issue create` prints the new issue URL on its own line
        // when it succeeds. Pull the last https:// line so we don't
        // confuse a "Creating issue in …" preamble for the result.
        let lines = output.components(separatedBy: .newlines).reversed()
        let urlLine = lines.first(where: { $0.hasPrefix("https://") })
        return urlLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "issue filed"
    }

    private static func prefilledIssueURL(title: String, body: String) -> URL? {
        var comps = URLComponents(string: "https://github.com/\(repo)/issues/new")
        comps?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body),
            URLQueryItem(name: "labels", value: label),
        ]
        return comps?.url
    }

    /// Resolve `gh`. A Finder-launched app has a stripped PATH (no
    /// Homebrew), so check the common install locations directly. Mirrors
    /// the search list used elsewhere in the app for `git`/`gh` lookups.
    private static func resolveGh() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func runProcess(executable: URL, args: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) { () -> String in
            let process = Process()
            process.executableURL = executable
            process.arguments = args
            var env = ProcessInfo.processInfo.environment
            let prepend = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            let existing = env["PATH"] ?? "/usr/bin:/bin"
            env["PATH"] = (prepend + [existing]).joined(separator: ":")
            process.environment = env
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                throw BugReportError.spawnFailed(error.localizedDescription)
            }
            process.waitUntilExit()
            let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if process.terminationStatus != 0 {
                let detail = err.trimmingCharacters(in: .whitespacesAndNewlines)
                throw BugReportError.ghFailed(status: process.terminationStatus, stderr: detail.isEmpty ? out : detail)
            }
            return out
        }.value
    }

    private static func appVersion() -> String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private static func macOSVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

enum BugReportError: LocalizedError {
    case ghMissing
    case spawnFailed(String)
    case ghFailed(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .ghMissing:
            return "Couldn't find the `gh` CLI. Install it (`brew install gh`) and authenticate (`gh auth login`), then retry — or we'll open a pre-filled GitHub form in your browser as a fallback."
        case .spawnFailed(let detail):
            return "Couldn't launch `gh`: \(detail)"
        case .ghFailed(let status, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`gh issue create` exited \(status): \(trimmed.isEmpty ? "no stderr" : trimmed)"
        }
    }
}
