# Skoga — Build Plan

> Part of the Skoga planning docs. See [planning.md](planning.md) for the index and high-level overview.

## Phases

### Phase 0 — Setup (week 1)

- Project skeleton, Cargo workspace, CI for builds and lint.
- Pick logging library (`tracing`).
- Establish testing patterns.
- Apache 2.0 license, CONTRIBUTING.md, basic README.

### Phase 1 — Daemon foundations (weeks 2-4)

- `skogad` runs as a background process.
- Unix socket IPC working with JSON-RPC.
- Health check endpoint.
- SQLite state storage.
- Basic config loading.
- **tmux orchestration primitives** — thin wrappers around `tmux new-session / attach / send-keys / pipe-pane / list-sessions / kill-session`. Load-bearing for everything downstream; build it once here so phases 4, 5, 6 can rely on it.

### Phase 2 — Sandbox provisioning (weeks 4-6)

- Create / detect / repair sandbox user.
- ACL setup.
- `sandbox-exec` profile.
- `--repair` and `--uninstall` commands.
- Document everything thoroughly because this is the dangerous bit.

### Phase 3 — Git orchestration (weeks 6-9)

- Sandbox-side repo cloning from host clone.
- Worktree creation and removal.
- Bidirectional sync via remotes (see [architecture.md → Bidirectional sync layer](architecture.md#bidirectional-sync-layer)).
- Opportunistic rebase loop in sidecar worktrees.
- Conflict detection.

### Phase 4 — Session state machine (weeks 9-11)

- All state transitions implemented.
- Cleanup policy on state changes.
- Suspended / stale / archive behavior.
- Disk pressure warnings.

### Phase 5 — Agent integration layer (weeks 11-13)

Process supervision is already handled by the tmux orchestration primitives from Phase 1. This phase builds the *agent abstraction* on top: any CLI coding agent can be plugged in via a small adapter contract, with optional capability layers for hooks-driven features. See [architecture.md → Agent integration layer](architecture.md#agent-integration-layer).

- `Agent` trait + capability surface in `skoga-agents`. Required: `launch_command`. Optional: `install_session_config`, hook-driven capabilities (waiting status, boundary check, summary, attention indicator).
- Stable, agent-agnostic `skoga _<event>` hook endpoints (`_notification`, `_on_stop_clear_waiting`, `_check_path`, `_on_summary`).
- Port the existing Claude Code integration into the trait. This is the reference adapter: it exercises every optional capability.
- Codex CLI adapter. Capability surface depends on Codex's extension API; at minimum: launch + pipe-pane + commits. Investigate hook/event support during build.
- Generic `--exec` adapter. Degenerate case: launch only, no in-worktree config, all optional capabilities off.
- Config schema for user-declared agents (`[agents.<name>]` block). Document with worked examples.
- Capability matrix in user-facing docs so users know what to expect per agent.
- Agent summary capture for adapters that declare the `session_summary` capability.

(Earlier drafts of this phase listed Claude Code, Codex, and the generic wrapper as three separate integrations. They collapse into one trait + three adapters; lifting the abstraction up front is what makes v1 actually support "any agent.")

### Phase 6 — CLI (weeks 13-15)

- All command verbs implemented.
- Good `--help` for every command.
- Shell completion (bash, zsh, fish).
- Clear error messages — translate git internals into session/task language.

### Phase 7 — TUI (weeks 15-17)

- Session list with state-based sort.
- Detail view.
- Live event subscription and updates.
- Keyboard navigation.
- Diff display.

### Phase 8 — Audit (weeks 17-18)

- Implement event emission per [audit-schema.md](audit-schema.md).
- Local NDJSON storage and rotation.
- `skoga logs` command.
- `skoga audit-schema` to dump the machine-readable schema.

### Phase 9 — Polish + docs (weeks 18-22)

- Landing page.
- Installation via Homebrew tap.
- Documentation site.
- Demo video / GIF for landing page.
- First-pass security review document.

### Phase 10 — Launch (week 22+)

- Soft launch to small audience.
- Iterate based on feedback.
- Public launch (Hacker News Show HN, relevant communities).

Total estimated time: ~5-6 months for v1 by one focused engineer. Probably longer in practice.

## Testing strategy

Three layers:

1. **Unit tests** for pure logic — state machine transitions, config parsing, event serialization. Standard Rust testing.
2. **Integration tests** with a real test repo and real git operations. Spin up a temp dir, run real git, exercise the orchestrator. Slow but essential.
3. **End-to-end tests** with a real (mock) agent. The agent is replaced with a script that makes specific edits and commits. Verify the full session lifecycle.

The sandbox provisioning code is the hardest to test because it requires admin. Have a manual test plan documented and run it on a fresh VM regularly. Don't try to automate this fully; the failure modes are too varied.

The install/uninstall test matrix (from [developer-experience.md → Install/uninstall testing matrix](developer-experience.md#installuninstall-testing-matrix)) must be run on every release candidate.

## Things to be cautious about

- **The sandbox user is shared system state.** If multiple Skoga installs collide, or if a previous failed install left cruft, recovery is painful. Always check for existing state and offer to repair.
- **ACL inheritance on macOS is finicky.** Test that newly-created files inherit the right ACLs. Have a `skoga doctor` command that checks ACL state and reports problems.
- **Git operations can be slow on large repos.** Don't make the daemon synchronously wait on git for long. Run git operations in background tasks; surface progress in the TUI.
- **tmux session leaks.** tmux owns agent process supervision (see [architecture.md → Agent process lifecycle](architecture.md#agent-process-lifecycle)), so direct zombie-reaping isn't on us — but tmux *sessions* themselves can leak if the daemon crashes mid-create or if a `kill-session` is interrupted. Reconcile `tmux list-sessions` against SQLite on every daemon start; surface orphans via `skoga recover`. `skoga uninstall` must `kill-session` every `skoga-*` tmux session before tearing down the sandbox user.
- **The daemon must not crash.** A daemon crash loses session state in memory and orphans agent processes. Use panic handlers, persist state aggressively, have a watchdog. The daemon being reliable is the #1 trust-building feature.
- **The agent cannot push or merge — not "shouldn't," can't.** Pushing, merging, and PR creation are physically denied to the agent process: no network access for git remotes in the sandbox profile, no GitHub credentials accessible to the sandbox user, no `gh` binary in its PATH. Skoga itself is the only thing that performs these operations, and only in response to an explicit `skoga land`. "Don't auto-merge" is a property of the architecture, not a discipline.
- **Bidirectional sync is load-bearing.** Several design choices (isolation backend, recovery model, developer UX) all rest on the sync layer being rock-solid. Sync bugs mean divergent copies of the user's code and lost work. See [architecture.md → Bidirectional sync layer](architecture.md#bidirectional-sync-layer).
