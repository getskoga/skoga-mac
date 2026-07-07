import SwiftUI
import AppKit

/// Lightweight in-app bug reporter. Captures the two questions every
/// triage instinctively asks ("what were you trying to do?" / "what
/// happened instead?") and opens a pre-filled new-issue form against
/// `getskoga/skoga-mac` in the user's browser via `NSWorkspace`. A
/// sandboxed daemon client can't shell out to `gh`, so the user submits
/// the pre-filled issue with one click on GitHub.
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
                Text("Opens a pre-filled issue in getskoga/skoga-mac")
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
        case .submitting: return "Opening GitHub…"
        case .failed:     return "Retry"
        default:          return "Open issue on GitHub"
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
            try BugReportFiler.openPrefilledIssue(title: title, body: body)
            modal.bugReportOpen = false
            modal.showToast("Opened a pre-filled GitHub issue — submit it there to file.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

// MARK: – Filer

/// Builds the issue payload and opens GitHub's pre-filled new-issue form
/// in the browser. Kept as a separate type so the modal stays focused on
/// layout/state and the URL-building logic is easy to swap (e.g. once the
/// daemon grows an `issue.create` RPC).
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

    /// Open GitHub's pre-filled new-issue form in the user's browser with
    /// the title, body, and label populated. A sandboxed daemon client
    /// can't shell out to `gh`, so filing is a one-click submit on GitHub.
    /// Throws when the URL can't be built (empty payload) or the browser
    /// hand-off is refused.
    @MainActor
    static func openPrefilledIssue(title: String, body: String) throws {
        guard let url = prefilledIssueURL(title: title, body: body) else {
            throw BugReportError.urlBuildFailed
        }
        guard NSWorkspace.shared.open(url) else {
            throw BugReportError.openFailed
        }
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
    case urlBuildFailed
    case openFailed

    var errorDescription: String? {
        switch self {
        case .urlBuildFailed:
            return "Couldn't build the GitHub issue URL. Add a bit more detail and try again."
        case .openFailed:
            return "Couldn't open your browser to file the issue. Check your default browser and try again."
        }
    }
}
