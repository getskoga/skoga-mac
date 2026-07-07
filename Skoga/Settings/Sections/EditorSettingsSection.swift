import AppKit
import SwiftUI

/// Settings → Editor. Backs the "Drop into editor" quick action in the
/// Conversation side panel (issue #9). One persisted choice — which
/// editor to hand the worktree to — plus an optional command template
/// for the `custom` case so the user can wire up an editor we don't
/// know about (Sublime, Helix-in-kitty, etc.) without a Skoga update.
///
/// Persistence: same `@AppStorage` shape `BudgetPrefs` uses. The
/// daemon doesn't own this preference yet (it's purely a Mac concern —
/// every machine the user signs in from likely has a different editor
/// installed), so there's no plan to migrate to `config.set`.
struct EditorSettingsSection: View {
    @Environment(\.palette) private var p

    @AppStorage(EditorPrefs.selected) private var selectedRaw: String = EditorPrefs.selectedDefault.rawValue
    @AppStorage(EditorPrefs.customCommand) private var customCommand: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            choiceCard
            // The custom-command card drives a `/bin/sh -c` launch that
            // can't run under App Sandbox, so it only appears in the
            // Direct build (where `.custom` is also the only build that
            // offers the choice at all).
            if EditorChoice(rawValue: selectedRaw) == .custom, SkogaBuild.isDirectBuild {
                customCommandCard
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(skoga: SettingsSectionID.editor.icon).skogaIconSize(15)
                    .foregroundStyle(p.ink2)
                Text(SettingsSectionID.editor.title)
                    .font(SkogaFont.serifTitle(24))
                    .foregroundStyle(p.ink)
            }
            Text("Where \"Drop into editor (worktree)\" in the Conversation side panel hands off the agent's checkout.")
                .font(SkogaFont.body(13))
                .foregroundStyle(p.inkMute)
                .lineSpacing(13 * 0.45)
                .frame(maxWidth: 540, alignment: .leading)
        }
    }

    private var choiceCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel("DEFAULT EDITOR")
                    .padding(.bottom, 12)

                VStack(spacing: 6) {
                    ForEach(EditorChoice.availableCases) { choice in
                        EditorChoiceRow(
                            choice: choice,
                            selected: selectedRaw == choice.rawValue
                        ) {
                            selectedRaw = choice.rawValue
                        }
                    }
                }
            }
        }
    }

    private var customCommandCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsCardLabel("CUSTOM COMMAND")
                Text("Run when you click \"Drop into editor\". Use `{path}` for the worktree root and `{files}` for the list of changed files (shell-quoted, space-joined). Without placeholders, the worktree path is appended. The command runs through `/bin/sh -c`.")
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("e.g. subl {path} {files}", text: $customCommand)
                    .textFieldStyle(.plain)
                    .font(SkogaFont.mono(12))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(p.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}

// MARK: – EditorChoice

/// The editors we know how to hand a worktree to. The raw value is the
/// `@AppStorage` token — keep it stable across releases so an upgrade
/// doesn't silently reset a user's pick.
enum EditorChoice: String, CaseIterable, Identifiable, Hashable {
    case vscode
    case cursor
    case zed
    case xcode
    case terminal
    case finder
    case custom

    var id: String { rawValue }

    /// Cases offered in the Settings picker. `.custom` runs an arbitrary
    /// command through `/bin/sh -c`, which App Sandbox forbids — the
    /// choice (and its command card) only appears in the Direct build.
    /// The enum case itself stays so the Direct build round-trips the
    /// persisted raw value unchanged.
    static var availableCases: [EditorChoice] {
        SkogaBuild.isDirectBuild ? allCases : allCases.filter { $0 != .custom }
    }

    var displayName: String {
        switch self {
        case .vscode:   "Visual Studio Code"
        case .cursor:   "Cursor"
        case .zed:      "Zed"
        case .xcode:    "Xcode"
        case .terminal: "Terminal"
        case .finder:   "Finder"
        case .custom:   "Custom command"
        }
    }

    /// Short blurb shown under the name in the picker.
    var blurb: String {
        switch self {
        case .vscode:   "Opens the worktree as a workspace, with the agent's changed files as tabs."
        case .cursor:   "Opens the worktree as a workspace, with the agent's changed files as tabs."
        case .zed:      "Opens the worktree as a workspace, with the agent's changed files as tabs."
        case .xcode:    "Opens the worktree folder in Xcode (handy for `.xcodeproj` roots)."
        case .terminal: "Opens a new Terminal window cd'd into the worktree."
        case .finder:   "Reveals the worktree in Finder. Default fallback."
        case .custom:   "Run an arbitrary shell command with the worktree path (and changed files) substituted in."
        }
    }

    var icon: SkogaIcon {
        switch self {
        case .vscode, .cursor, .zed, .xcode, .custom: .doc
        case .terminal: .cmd
        case .finder:   .doc
        }
    }

    /// Whether passing additional file paths after the workspace folder
    /// makes sense for this editor. VS Code-family editors open the
    /// first path as the workspace and any additional ones as tabs.
    /// Xcode, Terminal, and Finder treat additional paths in confusing
    /// ways (separate windows, dropped arguments) — we keep them
    /// folder-only and ignore the changed-files list.
    var supportsFileTabs: Bool {
        switch self {
        case .vscode, .cursor, .zed, .custom: true
        case .xcode, .terminal, .finder:      false
        }
    }
}

// MARK: – AppStorage keys

/// Same pattern as `BudgetPrefs` — read helpers live alongside the keys
/// so any surface that needs to resolve "what editor did the user pick?"
/// can do so without juggling `UserDefaults` defaults itself.
enum EditorPrefs {
    static let selected      = "skoga.editor.selected"
    static let customCommand = "skoga.editor.customCommand"

    /// Finder is the safest first-launch default: it works on every Mac
    /// regardless of what (if anything) the user has installed.
    static let selectedDefault: EditorChoice = .finder

    static func readSelected() -> EditorChoice {
        let raw = UserDefaults.standard.string(forKey: selected) ?? selectedDefault.rawValue
        let choice = EditorChoice(rawValue: raw) ?? selectedDefault
        // `.custom` shells out through `/bin/sh -c` which the sandboxed
        // build can't do. A user who picked it on a Direct build and then
        // switched channels falls back to Finder rather than hitting a
        // dead action; the stored preference is left intact so switching
        // back restores their command.
        if choice == .custom && !SkogaBuild.isDirectBuild {
            return selectedDefault
        }
        return choice
    }

    static func readCustomCommand() -> String {
        UserDefaults.standard.string(forKey: customCommand) ?? ""
    }
}

// MARK: – Picker row

private struct EditorChoiceRow: View {
    @Environment(\.palette) private var p
    let choice: EditorChoice
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                    Image(skoga: choice.icon).skogaIconSize(13).foregroundStyle(p.ink2)
                }
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.displayName)
                        .font(SkogaFont.bodyMedium(13))
                        .foregroundStyle(p.ink)
                    Text(choice.blurb)
                        .font(SkogaFont.body(12))
                        .foregroundStyle(p.inkMute)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    Circle()
                        .stroke(selected ? p.forest : p.rule, lineWidth: Tokens.Hairline.width)
                        .frame(width: 16, height: 16)
                    if selected {
                        Circle().fill(p.forest).frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 6)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(selected ? p.paper3 : (hovering ? p.paper3 : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .stroke(selected ? p.forest.opacity(0.5) : .clear, lineWidth: Tokens.Hairline.width)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: – Launching the editor

/// Outcomes of `EditorLauncher.open` — the caller decides how to surface
/// each (currently: toast for success/failure, route to Settings for
/// `unconfigured`).
enum EditorLaunchResult: Equatable {
    case opened(EditorChoice)
    /// Worktree path is missing on the Agent — daemon didn't surface
    /// one (older daemon, in-flight create, etc.). Distinct from
    /// `failed` so the UI can explain *why* it can't act.
    case noWorktree
    /// `custom` is selected but the command template is empty.
    case unconfigured
    case failed(String)
}

/// Hands the worktree off to whichever editor the user picked in
/// Settings. Pure side-effects — the caller passes the worktree path,
/// the resolved choice, and any changed files; we don't reach into
/// `UserDefaults` here so the function stays testable.
///
/// For editors that accept multi-arg launches (VS Code / Cursor / Zed),
/// the worktree opens as the workspace and the changed files come in
/// as tabs. Xcode / Terminal / Finder don't have a meaningful "tabs"
/// concept for this flow, so they always get the folder only.
enum EditorLauncher {
    /// Hard cap on how many file paths we hand the editor in one shot.
    /// A 200-file change usually means a worktree-wide refactor —
    /// opening 200 tabs would freeze the editor for several seconds
    /// and bury the file tree. Past this, we fall back to folder-only
    /// and let the user navigate via the editor's source-control view.
    static let maxFileTabs = 20

    @MainActor
    static func open(
        worktree: String?,
        choice: EditorChoice,
        customCommand: String,
        changedFiles: [String] = []
    ) async -> EditorLaunchResult {
        guard let raw = worktree, !raw.isEmpty else { return .noWorktree }
        // Resolve `~` and normalize trailing slashes so `open` doesn't
        // get an empty arg and editors don't choke on `~/.skoga/...`.
        let expanded = (raw as NSString).expandingTildeInPath
        let folder = expanded.hasSuffix("/") && expanded.count > 1
            ? String(expanded.dropLast())
            : expanded

        // Daemon returns each file as a path relative to the worktree
        // root. Promote to absolute before handing them to `open` —
        // `open file.swift` would resolve against the Mac process's
        // cwd, not the worktree. Capped so a refactor doesn't bury
        // the editor in tabs.
        let filePaths = choice.supportsFileTabs
            ? changedFiles.prefix(maxFileTabs).map { absolutePath(worktree: folder, relative: $0) }
            : []

        switch choice {
        case .vscode:
            // VS Code and Cursor register `<scheme>://file/<abs path>` —
            // richer than a plain file-open (no "which window?" prompt,
            // reuses the frontmost workspace) and it works from a
            // sandboxed app because the receiving editor does the file
            // access, not us.
            return openViaURLScheme(scheme: "vscode", appName: "Visual Studio Code",
                                    folder: folder, files: filePaths, choice: .vscode)
        case .cursor:
            return openViaURLScheme(scheme: "cursor", appName: "Cursor",
                                    folder: folder, files: filePaths, choice: .cursor)
        case .zed:
            return await openViaApp(bundleId: "dev.zed.Zed", appName: "Zed",
                                    folder: folder, files: filePaths, choice: .zed)
        case .xcode:
            return await openViaApp(bundleId: "com.apple.dt.Xcode", appName: "Xcode",
                                    folder: folder, files: [], choice: .xcode)
        case .terminal:
            return await openViaApp(bundleId: "com.apple.Terminal", appName: "Terminal",
                                    folder: folder, files: [], choice: .terminal)
        case .finder:
            return openInFinder(path: folder)
        case .custom:
            return runCustom(template: customCommand, folder: folder, files: filePaths)
        }
    }

    // MARK: helpers

    /// Open the worktree (and changed files) via the editor's custom URL
    /// scheme: `vscode://file/<abs path>` / `cursor://file/<abs path>`.
    /// The folder URL opens the workspace; per-file URLs land as tabs.
    /// Fails cleanly when no app claims the scheme (editor not installed).
    @MainActor
    private static func openViaURLScheme(
        scheme: String,
        appName: String,
        folder: String,
        files: [String],
        choice: EditorChoice
    ) -> EditorLaunchResult {
        guard let folderURL = fileSchemeURL(scheme: scheme, path: folder) else {
            return .failed("Couldn't build a \(scheme):// URL for \(folder).")
        }
        guard NSWorkspace.shared.urlForApplication(toOpen: folderURL) != nil else {
            return .failed("\(appName) doesn't appear to be installed (nothing handles \(scheme)://).")
        }
        guard NSWorkspace.shared.open(folderURL) else {
            return .failed("Couldn't hand the worktree to \(appName).")
        }
        for file in files {
            if let fileURL = fileSchemeURL(scheme: scheme, path: file) {
                NSWorkspace.shared.open(fileURL)
            }
        }
        return .opened(choice)
    }

    /// `vscode://file/<path>` with the path percent-encoded per component
    /// (spaces, unicode) while keeping `/` literal.
    private static func fileSchemeURL(scheme: String, path: String) -> URL? {
        let escaped = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "\(scheme)://file\(escaped.hasPrefix("/") ? "" : "/")\(escaped)")
    }

    /// Open the folder (plus any tab files) with a specific app via
    /// `NSWorkspace` — the sandbox-safe equivalent of `open -a <App>`.
    /// The app is resolved by bundle id; a missing editor fails with a
    /// clear "not installed" message instead of a launch error.
    @MainActor
    private static func openViaApp(
        bundleId: String,
        appName: String,
        folder: String,
        files: [String],
        choice: EditorChoice
    ) async -> EditorLaunchResult {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return .failed("\(appName) doesn't appear to be installed.")
        }
        let urls = [URL(fileURLWithPath: folder)] + files.map { URL(fileURLWithPath: $0) }
        // Await the launch instead of firing and forgetting. Resolving
        // the bundle id only proves the app is *installed*; the launch
        // itself can still fail afterwards (corrupt bundle, Gatekeeper
        // or permission denial, an OS-level launch error). The async
        // overload wraps the completion handler NSWorkspace calls once
        // the app has actually launched (or failed), so those cases
        // surface as a toast rather than a false-positive "Opening…".
        do {
            try await NSWorkspace.shared.open(
                urls,
                withApplicationAt: appURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
            return .opened(choice)
        } catch {
            return .failed("Couldn't open \(appName): \(error.localizedDescription)")
        }
    }

    @MainActor
    private static func openInFinder(path: String) -> EditorLaunchResult {
        let url = URL(fileURLWithPath: path)
        if NSWorkspace.shared.open(url) {
            return .opened(.finder)
        }
        return .failed("Couldn't open \(path) in Finder.")
    }

    @MainActor
    private static func runCustom(template: String, folder: String, files: [String]) -> EditorLaunchResult {
        // Custom commands run through `/bin/sh -c`, which App Sandbox
        // forbids — Direct (non-MAS) builds only. The Settings UI hides
        // the `.custom` choice and `EditorPrefs.readSelected()` falls
        // back to Finder in sandboxed builds, so this guard is a
        // belt-and-suspenders backstop rather than a reachable path.
        guard SkogaBuild.isDirectBuild else {
            return .failed("Custom editor commands aren't available in this build.")
        }
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unconfigured }
        // Quote each path before substituting so a worktree like
        // `/Users/me/sandbox sessions/foo` doesn't tokenize on the
        // space when `/bin/sh -c` parses the command. `{path}` is the
        // worktree root; `{files}` expands to a space-joined list of
        // shell-quoted absolute file paths (empty when there are no
        // changed files). Templates without either placeholder fall
        // back to appending the folder, which keeps simple `subl` /
        // `code` style commands working without a template rewrite.
        let folderQuoted = shellQuote(folder)
        let filesJoined = files.map(shellQuote).joined(separator: " ")
        let hasPathPlaceholder = trimmed.contains("{path}")
        let hasFilesPlaceholder = trimmed.contains("{files}")
        let command: String
        if hasPathPlaceholder || hasFilesPlaceholder {
            command = trimmed
                .replacingOccurrences(of: "{path}", with: folderQuoted)
                .replacingOccurrences(of: "{files}", with: filesJoined)
        } else {
            command = "\(trimmed) \(folderQuoted)"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        do {
            try process.run()
            return .opened(.custom)
        } catch {
            return .failed("Couldn't run custom command: \(error.localizedDescription)")
        }
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Promote a worktree-relative path to absolute. `URL` joins
    /// preserve unicode and separator behavior; raw string
    /// concatenation would have to special-case empty / leading-slash
    /// inputs.
    private static func absolutePath(worktree: String, relative: String) -> String {
        URL(fileURLWithPath: worktree, isDirectory: true)
            .appendingPathComponent(relative)
            .path
    }
}
