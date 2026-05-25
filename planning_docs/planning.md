# Skoga — Planning Document

> Index for Skoga's planning docs. High-level overview, principles, and scope here; detail in the linked documents.

## What is Skoga

Skoga is the management cockpit for engineers running AI coding agents. The tagline: **Run your agents like a team.** Engineers increasingly do less typing of code themselves and more dispatching, supervising, and reviewing AI agents working in parallel on multiple branches and codebases. Skoga slots between the editor (microscope when an agent gets stuck) and GitHub (still wins code review) — the missing middle layer for dispatch and supervision.

Skoga manages running multiple AI coding agents (Claude Code, Codex, Cursor, Gemini, etc.) in parallel on a developer's machine — handling isolation, git worktrees, branch management, rebasing, and review.

Long-term ambition: the obvious answer to "where do I run my agents?" in the same way Linear is the obvious answer to "where does my team track work?"

## Document index

- **[architecture.md](architecture.md)** — Technical architecture: language and crates, durability model, component layout, the local API, sandbox provisioning, worktree orchestration, bidirectional sync layer, agent process lifecycle.
- **[developer-experience.md](developer-experience.md)** — User-facing flows: install/uninstall, secrets, in-session experience, the CLI, the TUI, the review flow, host-sandbox divergence behavior, the `skoga land` flow, first-session UX target.
- **[audit-schema.md](audit-schema.md)** — Stable contract for the audit event stream that drives the activity feed, review, and integrations.
- **[build-plan.md](build-plan.md)** — Phased build plan, testing strategy, and things to be cautious about.

## Positioning principles

These shape every design decision:

1. **Management cockpit, not editor.** Skoga's UI, terminology, and workflows reinforce the manager-of-agents metaphor everywhere. If a design choice makes Skoga feel more like an IDE, push back.
2. **Slot between the editor and GitHub; don't replace either.** GitHub already won code review. Editors are microscopes. Skoga is the missing dispatch-and-supervision layer. No overlap with either.
3. **Route agents through existing engineering processes; don't invent parallel safety systems.** Code changes go through PRs. Data changes go through reviewed migrations. Skoga's job is to route agents through systems the team already trusts.
4. **Workflow first, security second.** Security and isolation are how the workflow works safely. They are not the headline.
5. **Open source forever for individual / single-machine use.** Apache 2.0. Real OSS, not source-available.
6. **Git-native.** Skoga uses git worktrees, real branches, normal commits. A developer can always drop to `git` for power operations. Skoga is convenience on top of standard git, not a replacement.
7. **Runtime emits structured events; consumers are pluggable.** The runtime emits machine-readable events from day one. The CLI and TUI consume them; future integrations (IDE plugins, dashboards) use the same protocol.
8. **Daemon-and-clients architecture.** All state lives in the daemon. The CLI is one client. The TUI is another. Future IDE plugins are also clients. This means a clean local API from day one.
9. **macOS first.** Linux and Windows are not in scope for v1. The architecture should not preclude them.
10. **Human-gated egress.** The agent never pushes, merges, or opens PRs. Operations that affect remotes or shared state — `git push`, PR creation, merges to the base branch — only happen when triggered by an explicit `skoga land` from the developer. Skoga executes those operations in response, using the developer's git credentials. The agent's git permissions inside the sandbox are local-only: commit, branch, rebase within its own worktree. No remote access.

## V1 scope (OSS launch)

The minimum to ship a credible OSS tool that AI-native developers want to install. Detail in [architecture.md](architecture.md) and [developer-experience.md](developer-experience.md).

### Core capabilities

- **Sandbox provisioning.** Default: create and manage a separate macOS user (`skoga-$USER`) with restricted permissions, plus `sandbox-exec` (Seatbelt) profile. Optional `--lite` mode uses `sandbox-exec` only without a system user.
- **Session management.** A session is the unit of work. It has a task, a worktree, a branch, a base, an agent process, a state, and an optional scope. Sessions persist across terminal sessions and laptop sleep.
- **Worktree orchestration.** Each session gets its own git worktree under the sandbox user's directory. Branches are named `skoga/<session-id>`. The orchestrator owns all worktree lifecycle.
- **Bidirectional host-sandbox sync.** The host clone is the developer's primary git interface; the sandbox is the agent's operating environment. Sync is local-only, state-aware, and never auto-merges divergent histories. See [architecture.md → Bidirectional sync layer](architecture.md#bidirectional-sync-layer).
- **Opportunistic rebase.** Sessions rebase against their base at quiescent points, not continuously. Conflicts pause the session.
- **Auto-checkpoint commits.** Skoga commits a `wip:` checkpoint every N minutes (default 5) if there are uncommitted changes; squashed away at land. Bounds work-loss to a few minutes.
- **Squash-at-land merge policy.** All session commits squashed into one tidy commit when landing.
- **Agent summary at session end.** Structured summary (Goal, Approach, Files, Tests, Open items) produced by the agent and surfaced in review/TUI.
- **Session state machine.** States: `running`, `conflicted`, `agent-exited`, `pr-open`, `pr-merged`, `shipping`, `killing`, `done`, `killed`, `sync-broken`. Transitions are explicit and drive cleanup policy. The shape evolved away from a single `waiting-for-review` toward a GitHub-reconciled pipeline (`pr-open` → `pr-merged` → `shipping` → `done`); `agent-exited` covers "process gone, work intact" without requiring a `suspended`/`stale` distinction; `sync-broken` is a real terminal-ish error state the sync layer can promote a session into.
- **Cleanup policy.** Worktrees removed on terminal transitions; branches retained longer than worktrees; disk pressure warnings.
- **Queue.** Kickoff messages can be enqueued (`skoga queue "<message>"`) when the active-session count is at the cockpit's pane cap; the daemon dequeues and launches a detached agent with the message as its first prompt when capacity opens up.
- **Cockpit.** A single tmux window combining the skoga dashboard with one nested-attach pane per running agent, tiled. The OSS-only feature for "I'm running N agents at once and want to see them all." See [developer-experience.md → The cockpit](developer-experience.md#the-cockpit).
- **Local audit emission.** Structured event stream per [audit-schema.md](audit-schema.md). Local-only in v1; substrate for the eventual commercial control plane.

### V1 surfaces

Two surfaces ship together at v1 launch, each aimed at a different audience and each first-class — the runtime is shared:

- **Skoga Mac app (Skoga Solo).** The primary surface for paying users. Native SwiftUI cockpit talking to `skogad` over the Unix-socket JSON-RPC API. Roster, conversation view, dispatch, review queue, command palette. This is the product surface most real users will live in; design quality and polish are load-bearing. See [Skoga Solo in the roadmap](private/roadmap.md#tier-1-skoga-solo-24month-30-day-free-trial-free-for-non-commercial-use).
- **Skoga OSS CLI (`skoga`).** The runtime engine, the OSS funnel, and the power-user escape hatch. Same daemon, same protocol; without it the Mac app has nothing to talk to. Verbs: `init`, `doctor`, `uninstall`, `start`, `list`, `history`, `show`, `review`, `diff`, `revise`, `checkout`, `absorb`, `attach`, `revisit`, `shell`, `push`, `land`, `ship`, `kill`, `export`, `prune`, `rename`, `cockpit`, `queue`, `sync`, `logs`, `sandbox`, `config`, `daemon`, `audit-schema`. See [developer-experience.md → The CLI](developer-experience.md#the-cli) for details.
  - **`skoga cockpit`** is the OSS-side parallel-agents experience: one tmux window with a dashboard pane on top and one nested-attach pane per running agent. It is the practical answer to "I'm running 5 agents and want to see them all" without the Mac app.
  - **`skoga` with no args** runs a minimal ratatui dashboard for the CLI-only user. The dashboard is also the top pane inside `skoga cockpit`.

### Agent integrations for v1

Every agent runs inside a per-session **tmux session** (named `skoga-<id>`), which is the uniform runtime substrate — process supervision, attach/detach, and a `pipe-pane` output stream are tmux's responsibility, not Skoga's. See [architecture.md → Agent process lifecycle](architecture.md#agent-process-lifecycle).

Above tmux, Skoga ships an `Agent` adapter contract (see [architecture.md → Agent integration layer](architecture.md#agent-integration-layer)). Required: launch command. Optional: in-worktree config installation, hook-driven capabilities (waiting status, boundary check, session summary, attention indicator). Any CLI coding agent can be plugged in as a built-in or user-declared adapter. Capability gaps are graceful — the agent still gets the full Skoga workflow (sandbox, sync, land, audit); it just doesn't get the hook-driven niceties unless its glue calls Skoga's hook endpoints.

**Built-in adapters in v1:**

- **Claude Code** — the v1 reference adapter and the only one shipped. Exercises every optional capability via `.claude/settings.local.json` hooks: structured event audit, waiting-on-user, boundary check (PreToolUse), session summary, attention indicator.

**Deferred to v1.1:**

- **Generic `exec` adapter** — launch-only, no in-worktree config. Cheap to add (~50 lines) and the right move when we're ready to claim "any CLI agent works." The `Agent` trait and capability surface are already shaped for this; the registry just needs the new variant plus a `[agents.<name>]` config-driven loader.
- **Codex CLI** — capability surface depends on Codex's extension API; was scoped for v1 in earlier drafts but pushed because there's no Codex user pulling for it yet.

JetBrains AI, Cursor's agent mode, and other IDE-embedded agents are out of scope because they don't run as standalone CLIs — tmux doesn't help them. The CLI-agent abstraction does not preclude future IDE integrations.

## V1 explicit non-goals

These are NOT in v1. Do not build them. Do not architect around them in a way that makes them harder to add later — but actively resist scope creep.

- **IDE plugins.** v2.
- **Linux or Windows support.** Future. The Mac app is Mac-only by design; OSS CLI is also macOS-first because of `sandbox-exec` and the heavy-mode user-account work, though the CLI's core is portable in principle.
- **Team / multi-machine features.** Commercial product, no daemon-to-daemon communication, no remote state.
- **Web UI.** Not v1, not v2.
- **Cloud sync of any kind.** No phone-home, no telemetry, no accounts. The Mac app's analytics view is local-only.
- **Custom secret storage.** No vault features. Agents inherit env from the developer's shell for now; team-scale credential brokering is commercial.
- **Policy enforcement.** No "agents can't do X" rules. Sandbox isolation is the enforcement primitive in v1; policy distribution is commercial.
- **Multi-repo / monorepo-specific optimizations.** Sparse checkouts, shared node_modules caches, etc. Document limitations, don't solve them yet.
- **Submodule / LFS first-class support.** Acknowledge in docs, defer.
- **Persistent (user-defined) agents in v1.** The deterministic Norse-name display in both the CLI and Mac app is name-only; "save Astrid as a permanent agent" is deferred to v1.1, likely arriving as `[agents.<name>]` config blocks rather than a separate persistence layer.
- **Heavy-mode tmux-as-sandbox-user.** The heavy-mode sandbox provisioning steps exist behind `SKOGA_ENABLE_HEAVY_APPLY` but routing tmux itself through `sudo -u skoga-$USER` is deferred. Lite mode is the v1 default; heavy mode ships when it has been exercised through full install/uninstall matrix testing on clean VMs.

## V2 — IDE integration (post-OSS-launch)

Triggered by: OSS launch is stable, has some adoption, and the daemon API has been exercised enough that we're confident in it.

### V2 surfaces

- **VS Code extension** — first IDE plugin. Works in VS Code and Cursor (which is a VS Code fork).
  - Live session sidebar
  - "Start session on this" from right-click on file/folder/selection
  - Diff review in native VS Code diff viewer
  - Notifications for state changes
  - One-click `land`, `kill`, `attach`

### V2 explicit non-goals

- JetBrains family (v3)
- Zed, Sublime, others (community plugins encouraged)
- Vim / Neovim / Emacs (community plugins encouraged; the CLI is fine for these users)
- Web-based IDEs / Codespaces / Gitpod (Linux dependency)

## Out of scope but worth noting

These are *eventual* concerns that should not be solved in v1 but should be thought about so we don't paint into a corner:

- **Linux support.** Eventual. Sandbox primitives change (user namespaces, bubblewrap, possibly k8s). The architecture should keep sandbox provisioning behind an interface so it can be swapped.
- **Remote daemon / fleet view.** Commercial. The local API protocol should be designed such that it could plausibly be tunneled to a remote control plane.
- **Multi-user macOS.** Multiple developers on one machine. Probably never; this is an edge case.

## Style and conventions

- **Code style:** `rustfmt` defaults, `clippy` clean on every commit.
- **Commit style:** Conventional commits. `feat:`, `fix:`, `chore:`, etc.
- **Documentation:** Every public module has docstrings. Every CLI command has good `--help`. The README is the marketing page; longer docs live in a `/docs` directory.
- **Errors:** Use `thiserror` for library errors, `anyhow` for application errors. Always have actionable error messages — "what failed, why, what to do about it."
- **Logging:** `tracing` everywhere. Structured logs to stderr by default; file logging configurable. The daemon's logs are diagnostic, not for user consumption.

## Open questions to revisit during build

These don't need to be answered now but should be tracked:

- ~~Should `skoga` and `skogad` be separate binaries or one binary with a daemon mode?~~ **Resolved:** separate binaries. `skogad` is the long-running daemon; `skoga` is the CLI client. The Mac app talks directly to `skogad`'s socket. Distribution is "two binaries in one Homebrew formula."
- ~~What's the right default for the sandbox user count — one shared across all sessions, or one per session?~~ **Resolved:** one shared user (`skoga-$USER`) when heavy mode ships; lite mode is the default for v1.
- ~~Should the agent summary at session end be required (a session cannot reach `waiting-for-review` without one)?~~ **Stale question:** there is no `waiting-for-review` state any more. Summary capture is lazy: `agent.summary` is requested via `claude -p` on demand when the user opens `skoga show`/`skoga review` on an inactive session. The session does not block on it.
- ~~Should the polling-only sync trigger model survive into v1.1, or is event-driven (git hooks) worth the added code paths sooner?~~ **Punted:** polling is 2s and has held up. Revisit only if real users complain about commit-to-host-visible latency.
- How aggressive should the opportunistic-rebase loop be? (Tuning problem; start conservative, watch real usage.)
- How do we handle agent CLIs that change their tool-call interfaces between versions? (Probably: pin supported versions, test against them, fail loudly on unknown versions.)
- What happens if the developer manually edits a worktree the agent is working in? (Probably: detect, warn, let them proceed at their own risk. Don't try to prevent.)
- Should `[review] precheck = "<command>"` (auto-run tests before showing the review screen) ship in v1, or wait for v1.5? Leaning: v1.5 — keep v1 review cheap.
- Line-anchored review comments (GitHub-style "comment on line 42 → revise"): v1.5 or later? V1 supports natural-language feedback only.
- Should daemon RPCs grow real action endpoints (`session.land`, `session.absorb`, `session.diff`) so the Mac app can drive operations end-to-end, or should the Mac app shell out to the CLI for those? Today the CLI does all action work and notifies the daemon via narrow state RPCs (`session.mark_pr_open` etc.). The Mac app currently can only `create`, `kill`, `list`, and read conversation/version. Resolving this is the gating decision for what Skoga Solo can actually do.

## Success criteria for v1

V1 ships well if:

- A developer can install Skoga from Homebrew and have a working sandbox set up in under 5 minutes.
- Starting a session with `skoga start "task description"` works without errors on a clean repo.
- Multiple sessions can run in parallel without interfering.
- Sessions persist across closing the terminal.
- The TUI shows accurate live state.
- `skoga land` produces a clean PR (or merged commit) that looks normal in the git log.
- No catastrophic data loss has happened to any beta tester's repos.
- We have at least 100 GitHub stars within a month of public launch. (Vanity metric, but a reasonable signal of "this resonated.")
