import SwiftUI

/// One entry in the Settings sidebar. The order here is the order the
/// sidebar renders — must-ship sections (General, Models & keys,
/// Budgets, GitHub, Notifications) sit near the top so they're the
/// first things a new user lands on; the rest follow in priority order.
enum SettingsSectionID: String, CaseIterable, Hashable, Identifiable {
    case general
    case appearance
    case modelsKeys
    case budgets
    case agents
    case github
    case notifications
    case worktrees
    case editor
    case keyboard
    case privacy
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general:        "General"
        case .appearance:     "Appearance"
        case .modelsKeys:     "Models & keys"
        case .budgets:        "Budgets"
        case .agents:         "Agents"
        case .github:         "GitHub"
        case .notifications:  "Notifications · Mobile"
        case .worktrees:      "Worktrees"
        case .editor:         "Editor"
        case .keyboard:       "Keyboard"
        case .privacy:        "Privacy & data"
        case .about:          "About"
        }
    }

    var icon: SkogaIcon {
        switch self {
        case .general:        .settings
        case .appearance:     .spark
        case .modelsKeys:     .bolt
        case .budgets:        .clock
        case .agents:         .roster
        case .github:         .github
        case .notifications:  .watch
        case .worktrees:      .branch
        case .editor:         .doc
        case .keyboard:       .cmd
        case .privacy:        .shield
        case .about:          .alert
        }
    }

    /// One-liner used as the section subtitle on its panel and as the
    /// search-haystack secondary string. Pairs with `roadmap` for the
    /// placeholder card.
    var blurb: String {
        switch self {
        case .general:        "App-wide preferences — theme, launch at login, and where Skoga opens."
        case .appearance:     "Density, font tuning, and theme overrides beyond the system mode."
        case .modelsKeys:     "Provider API keys and which models each agent is allowed to pick from."
        case .budgets:        "Monthly cost ceilings and per-agent spend limits."
        case .agents:         "Defaults, templates, and shared prompts for new agents."
        case .github:         "Used by Open as PR to push branches and open pull requests."
        case .notifications:  "Desktop banners, quiet hours, and the iPhone bridge for attention-needed pings."
        case .worktrees:      "Where Skoga checks out per-agent worktrees and how it cleans them up."
        case .editor:         "Default editor and how Skoga hands off files for review."
        case .keyboard:       "Customize shortcuts for navigation, dispatch, and review."
        case .privacy:        "Telemetry opt-out, conversation retention, and export."
        case .about:          "Version, build, daemon protocol, and acknowledgements."
        }
    }

    /// Concrete bullet list of what the panel will eventually contain.
    /// Used by `PlaceholderSection` so an unimplemented row still tells
    /// the user *what* is coming, not just that "something" is — per
    /// issue #20's "never a dead-end coming soon" rule.
    ///
    /// Sections with their own dedicated panel keep a roadmap too as a
    /// defensive fallback: `SettingsShell` routes them directly, so
    /// PlaceholderSection is unreachable in practice — but if the
    /// routing ever regresses, a non-empty roadmap means the user
    /// still sees a coherent card instead of a blank header with an
    /// empty bullet list. Bullets reflect what *did* ship so they read
    /// honestly even from the fallback path.
    var roadmap: [String] {
        switch self {
        case .general:        ["Theme (system · light · dark)",
                               "Launch Skoga at login",
                               "Open at (Roster · last view)"]
        case .appearance:     ["UI density (compact · comfortable)",
                               "Font face and serif/mono pairing",
                               "Per-window background tuning"]
        case .modelsKeys:     ["Anthropic / OpenAI / Google API keys",
                               "Default model per agent role",
                               "Allow-list of models each agent may pick"]
        case .budgets:        ["Per-run / daily / monthly spend caps",
                               "Soft-stop vs hard-kill on cap",
                               "Alert-at threshold (50 / 75 / 80 / 100%)"]
        case .agents:         ["Default role and tooling for new agents",
                               "Shared system prompts and templates",
                               "Auto-resume policy after disconnect"]
        case .notifications:  ["What wakes you (blocked · finished · budget)",
                               "Desktop banners + sound on attention only",
                               "Quiet hours with wrap-around support"]
        case .worktrees:      ["Root directory for agent checkouts",
                               "Cleanup policy after merge",
                               "Disk-quota guardrails"]
        case .editor:         ["Default editor (VS Code · Cursor · Zed · …)",
                               "Custom shell command with {path} / {files}",
                               "Used by Conversation → Drop into editor"]
        case .keyboard:       ["Catalog of wired shortcuts",
                               "Grouped Global · Modal",
                               "Rebinding (future)"]
        case .privacy:        ["Telemetry opt-in",
                               "Reset first-run state",
                               "Clear local Skoga state (~/.skoga/)"]
        case .about:          ["App and daemon versions",
                               "Acknowledgements and licenses",
                               "Re-run onboarding"]
        case .github:         ["gh CLI install + sign-in flow",
                               "Default reviewer for new PRs",
                               "Scopes the daemon needs to push"]
        }
    }
}
