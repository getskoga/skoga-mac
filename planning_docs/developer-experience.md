# Skoga — Developer Experience

> Part of the Skoga planning docs. See [planning.md](planning.md) for the index and high-level overview.

Where [architecture.md](architecture.md) describes what Skoga does internally, this document describes what the developer sees and does. It is the most user-facing part of the spec and should be treated as load-bearing for adoption.

## Install, first-run, and uninstall

Two-step install. Homebrew never triggers admin prompts; `skoga init` is where the real setup happens.

```bash
$ brew install skoga
$ skoga init
```

### Backend selection

`skoga init` defaults to the **heavy path**: creates a `skoga-$USER` system user via `sysadminctl`/`dscl`, sets up the home directory with ACLs, installs the launchd service, loads the `sandbox-exec` profile. Admin password prompt once; never again. This embodies the security-first stance from day one and aligns the OSS install with the commercial security story.

The **light path** (sandbox-exec only) is available via flag for users who can't or won't grant admin:

```bash
$ skoga init --lite           # sandbox-exec only; no system user, no admin
$ skoga init --dry-run        # preview what would be created/modified
```

Chosen backend is persisted to `~/.skoga/config.toml` as `[sandbox] backend = "system_user" | "exec_only"` so `skoga uninstall` and `skoga doctor` know which world they're in.

Switching backends after install: `skoga sandbox upgrade` (light → heavy, admin prompt once, migrates worktrees) and `skoga sandbox downgrade` (heavy → light, requires terminal-state sessions only). Both are rare operations; design for correctness over convenience.

### Verification and repair

`skoga doctor` re-verifies install state — daemon service, ACL grants, sandbox-exec profile, system user (if heavy path), config integrity. `skoga init --repair` re-runs setup steps that fail verification. Both must be safe to run any number of times.

Install and uninstall must be cleanly reversible; orphaned state (especially on the heavy path) is a leading source of recovery pain.

### Uninstall

`skoga uninstall` is the inverse of `init`. It removes Skoga's managed state but does not remove the binary itself (that's `brew uninstall skoga`).

Order of operations:

1. **Refuse by default if work could be lost.** Scan for sessions in non-terminal states and worktrees with uncommitted changes; refuse if any exist. `--force` overrides.
2. **Stop the daemon.** Unload the launchd service.
3. **Kill agent processes.** SIGTERM, grace period, SIGKILL. Verify no processes owned by the sandbox user remain before user removal.
4. **Back up `~/.skoga/`** (config + audit log) to a timestamped path: `~/.skoga.backup-YYYY-MM-DD/`. Never delete the audit log without preserving it — that's potentially weeks of agent activity history.
5. **Remove ACL grants** on dev home subdirs (`~/.claude/`, `~/.config/gh/`, etc.) that referenced the sandbox user. Orphaned UIDs in ACLs are untidy.
6. **Remove the sandbox-exec profile.**
7. **Remove the system user and home directory** via `dscl . -delete /Users/skoga-$USER` and `rm -rf /Users/skoga-$USER`. Admin prompt here (heavy path only).
8. **Remove `~/.skoga/`** (after the backup).

Concrete UX:

```
$ skoga uninstall

This will remove Skoga from your machine.

Will be removed:
  • Daemon service (launchd)
  • Sandbox-exec profile
  • System user `skoga-andrewpierce`
  • All sandbox repo clones and worktrees (3 repos, 4.2 GB)
  • ACL grants on ~/.claude, ~/.config/gh, ~/.aws
  • Local config and audit log at ~/.skoga
    → backed up first to ~/.skoga.backup-2026-05-19/

The brew binary will not be removed. Run `brew uninstall skoga` after this.

⚠ 2 sessions have work that will be lost:
   abc1234   waiting-for-review   "implement signup"    3 commits
   def5678   running              "refactor auth"       uncommitted

   Preserve them first with:
     skoga land abc1234                              # ship it
     skoga export abc1234 > /tmp/abc1234.patch       # save as a patch
     skoga kill --export def5678 > /tmp/def5678.patch

Continue with uninstall? [y/N]
```

`skoga uninstall --dry-run` shows the plan without acting.

### Robustness requirements for uninstall

Each step must be idempotent — re-running `skoga uninstall` after an interrupted run picks up cleanly. If the daemon is already stopped, that step is a no-op. If the user has already been manually deleted, that step is a no-op. Don't error on missing things; the goal is "get to a clean state."

What uninstall does NOT touch:
- The dev's normal git config or repos.
- The dev's `~/.claude/` auth state — only the ACLs Skoga added are removed; the credentials themselves stay.
- The brew-installed binary (separate step).

### Install/uninstall testing matrix

Aggressively tested on a clean VM:
- `init` → `uninstall` (both backends) → verify nothing remains.
- `init` → use Skoga normally → `uninstall` → verify nothing remains.
- `init` → `kill -9` the daemon mid-session → `uninstall --force` → verify clean.
- `init` → manually corrupt state → `uninstall` → still completes.
- Repeated install/uninstall cycles → identical end-state each time.

If any of these leaves cruft, that's a recoverable bug pre-launch and a trust-loss bug post-launch.

## Secrets and credentials

Skoga does not run a vault or secret store. Three categories of credential, three approaches:

**1. Agent CLI auth** (Claude Code, Codex, etc.) — accessed via **read-only ACL grant** from the sandbox user to selected developer home subdirectories: `~/.claude/`, `~/.config/gh/`, `~/.aws/`. The sandbox user can read but not write. The developer manages auth normally on their own user; the sandbox sees live state. No copying, no sync drift, no separate logins.

The leak this accepts: the agent process can read API keys during its run, which is exposure within the agent's identity. The defense: that's the agent's identity by design — "this agent acts on my behalf." If you want stronger per-agent credential scoping, that's a commercial-product feature.

**2. Project-level secrets** (`.env` files, AWS profile names, npm tokens) — live in the worktree as files, same as today. The agent sees them because they're in its cwd. Standard pattern.

**3. Env-var passthrough** — explicit allow-list in `~/.skoga/config.toml`:
```toml
[env]
passthrough = [
  "ANTHROPIC_API_KEY",
  "GITHUB_TOKEN",
  "AWS_PROFILE",
  "NODE_VERSION",
]
```
Skoga reads these from the developer's environment when launching the agent and re-exports them in the sandbox user's environment. Explicit allow-list prevents surprise leakage.

Not supported in v1: SSH keys (use HTTPS+tokens), macOS Keychain integration, custom vault. Team-scale credential brokering is commercial.

## The in-session experience

The principle: **starting a session should feel like running the agent directly.** No wrapper UI, no Skoga-specific input syntax, no terminal interception.

```bash
$ skoga start "implement signup flow"
[brief: session abc1234 starting in /Users/skoga-andrewpierce/sessions/abc1234]
[claude UI takes over]
```

Under the hood, the agent runs inside a tmux session named `skoga-abc1234`, and `skoga start` exec's `tmux attach-session` so the developer's terminal foreground experience is indistinguishable from running the agent directly. **Detaching with `Ctrl-b d` does not kill the agent** — it keeps working in the background, and `skoga attach abc1234` (or pressing `a` in the TUI) re-foregrounds it. Closing the terminal, sleeping the laptop, or restarting the daemon also leave the agent running.

The agent does not know it is being run by Skoga. It runs in its cwd with normal stdin/stdout. **Skoga does not parse the agent's stdin/stdout** — there is no `:skoga` command syntax, no slash-command shadowing, no PTY interception of user input. This sidesteps an entire class of paste hazards and integration brittleness, and keeps the per-agent integration surface small. (Skoga *does* capture a passive copy of the PTY stream via tmux's `pipe-pane` for the activity feed, but it never modifies what the agent reads from stdin.)

All Skoga interaction is **out-of-band**:
- A second terminal pane: `skoga list`, `skoga diff`, `skoga land`
- The TUI dashboard: run `skoga` with no args
- Future: IDE plugin

When Skoga has something to say to the developer mid-session (rebase happened, conflict detected, state transition), it writes a single status line in the agent's terminal between agent turns:
```
[Skoga: rebased onto main (12 new commits)]
[Skoga: session marked waiting-for-review]
```
Status lines are informational only — the agent is not asked to act on them; the dashboard holds the real state.

## The CLI

The CLI is one of two first-class surfaces. The Mac app (Skoga Solo) is where most paying users will live; the CLI is the runtime engine, the OSS funnel, and the power-user escape hatch. The Mac app talks to the same `skogad` over the same socket; CLI verbs and Mac app actions converge on the same state.

Verb-by-verb:

**Setup & lifecycle**
- `skoga init` (alias: `skoga secure`) — provision the sandbox backend. Lite (sandbox-exec only) is the v1 default and runs without admin. `--repair` re-applies failed steps; `--dry-run` previews; `--yes` skips the confirm.
- `skoga doctor` — verify install state and report drift.
- `skoga uninstall` (alias: `skoga unsecure`) — tear down lite-mode state. Detects what's installed and prompts for the choices that matter; does not remove the brew binary itself.
- `skoga sandbox <upgrade|downgrade>` — switch backends after install. Hidden in v1 while heavy-mode apply steps stay gated behind `SKOGA_ENABLE_HEAVY_APPLY`.
- `skoga daemon <status|start|stop|restart|paths>` — control `skogad`.
- `skoga config <get|set|list|path|unset>` — read or modify config (`~/.skoga/config.toml`).
- `skoga audit-schema` — dump the machine-readable audit schema embedded in the binary.

**Session lifecycle**
- `skoga start [task]` — create a session, install adapter hooks, exec into the agent. `--agent` defaults to `claude`; `--base` defaults to the current branch.
- `skoga list` — active sessions. `--all` includes terminal.
- `skoga history` — past sessions (done/killed/pr-open/agent-exited), newest first; `--grep` substring filter. Companion to `skoga revisit`.
- `skoga show [query]` — non-interactive details for a session.
- `skoga review [query]` — interactive review screen (composes diff/shell/revise/land).
- `skoga diff [query]` — `git diff base..HEAD` in the worktree (`--stat` for stats only).
- `skoga revise <query> <feedback>` — push a new instruction. If the agent's tmux is alive, the feedback is pasted into the running pane; if it exited, a fresh agent is started with the feedback as initial prompt.
- `skoga attach [query]` — re-attach to a session's agent (relaunches a fresh agent if the prior tmux is gone).
- `skoga revisit [query]` — revive a past session's agent against today's `main` in a fresh worktree.
- `skoga rename [query] [new_task]` — relabel a session (and its branch). `--all` re-runs the auto-labeler against current transcripts for every still-auto-named open session.
- `skoga checkout [query]` — materialize a host-side review worktree under `~/.skoga/host-worktrees/<id>/`; `--remove` tears it down.
- `skoga absorb [query]` — pull dev-side commits into the session. `--prefer-host`, `--prefer-sandbox`, `--merge` resolve true divergence.
- `skoga sync <query> --debug|--rebuild` — inspect or repair the sync layer; `--rebuild` exports a bundle and re-fetches after `sync-broken`.
- `skoga shell [query]` — drop into a shell in the worktree as the dev's user.

**Land / push / ship (the PR pipeline)**
- `skoga push [query]` — `git push -u` for a session's branch as-is. No squash, no PR. Use this after an agent revises a PR; use `skoga land` instead if there is no PR yet.
- `skoga land [query]` — squash, rebase, push, open PR via `gh`. Transitions to `pr-open`. `--yes` for non-interactive (refused if invoked from inside the agent's own tmux), `--merge` for no-PR direct merge, `--all` to land every active session in batch.
- `skoga ship [query]` — finalize a `pr-merged` session: terminate the agent, tear down the worktree, transition to `done`. The daemon also reconciles `pr-open` → `pr-merged` automatically by polling `gh`, so `skoga ship` is the explicit "I'm done with this one" verb.
- `skoga pr feedback [query]` — bundle review comments + failing CI from the session's PR into a prompt and inject it into the agent. Pair with `skoga push` once the agent revises.

**Cleanup & escape hatches**
- `skoga kill [query]` — abandon a session and remove its worktree. Confirmation prompt; `--yes` for batch.
- `skoga export [query]` — write the session's committed work as a patch (default; stdout) or a `git bundle` (`--bundle`; defaults to `./skoga-<id>.bundle`). Read-only. Escape hatch for "I want my work but not this session."
- `skoga prune` — sweep stale sessions and orphaned worktrees in one pass. `--age 3d`, `--include-pr-open`, `--audit` (also prune `~/.skoga/audit/`).
- `skoga logs <query>` — dump the audit log for a session (`--since`, `--type`, `--format json`, `--follow`). Reads NDJSON directly so it works even when the daemon is down.

**Cockpit & queue**
- `skoga cockpit` — single tmux window with the dashboard on top and one nested-attach pane per running agent (see [The cockpit](#the-cockpit) below). `skoga cockpit refresh` / `skoga cockpit down` for control.
- `skoga queue "<message>"` — enqueue a kickoff message; the daemon dequeues and launches a detached agent when the active-session count is below the cockpit pane cap. `skoga queue list` / `skoga queue remove <id>` for management.

Shell completion for bash/zsh/fish ships with v1. Every verb has good `--help`.

## The TUI and the cockpit

`skoga` with no args launches a minimal ratatui dashboard — a session table with keyboard nav, attach/shell exec-outs, and a live polling header. It is intentionally small. The Mac app is where the "rich, sorted-by-urgency, attention-feed" experience lives; the TUI is the OSS-CLI baseline so users who never install the Mac app still have a dashboard.

For the parallel-agents case (the OSS power-user story), the real entry point is **`skoga cockpit`** — a single tmux window with three rows: the TUI dashboard on top, one nested-attach pane per running `skoga-*` agent in the middle (tiled, with a configurable pane cap derived from RAM), and a launcher shell at the bottom for typing `skoga start <task>` without leaving the cockpit. A background watcher rebuilds the agent row when sessions appear or disappear.

The TUI as a standalone view:

**Sessions list** (main view) — live, sorted by urgency:
```
┌─ Skoga ─────────────────────────────────────────────── 3 sessions ──┐
│   STATE                TASK                   AGE   AGENT   ID       │
│ ▶ ⚠ waiting-review     implement signup flow  12m   claude  abc1234  │
│   ● running            refactor auth          3m    claude  def5678  │
│   ⏸ suspended          fix CSS bug            2h    codex   ghi9012  │
├──────────────────────────────────────────────────────────────────────┤
│ disk 2.4GB │ daemon ok │ n:new ↵:open l:land k:kill a:attach ?:help q│
└──────────────────────────────────────────────────────────────────────┘
```

Sort order: conflicted → review-needed → running → idle → terminal. State icons + color do most of the work (⚠ yellow, ✗ red, ● blue, ⏸ gray, ✓ green).

**Session detail** (entered with Enter): metadata header, file change summary, live activity feed. The activity feed is the human-readable projection of the audit log — file writes, commits, rebases, tool calls, state transitions, agent reasoning. It is what makes the TUI feel alive vs. just being a list. See [audit-schema.md → Projections](audit-schema.md#projections) for projection details.

Key interactions:
- `j`/`k` or arrows — navigate
- Enter — open detail
- Esc — back out
- `n` — create a new session (opens a text input for the task)
- `a` — attach to the agent's tmux session (Ctrl-b d detaches back to the TUI; the agent keeps running)
- `l` — land (with confirmation)
- `r` — revise (opens a text input for feedback)
- `d` — view diff in `$PAGER`
- `c` — checkout in host clone
- `s` — drop into `skoga shell`
- `k` — kill (with confirmation)
- `?` — keybinding help overlay
- `q` — quit

When a session changes state while the dev is in the TUI (e.g., `running → conflicted`), surface it with a banner + re-sort. Optional macOS notification via config (`[notify] macos_alerts = true`) for state changes when Skoga is not focused.

The TUI is not a terminal multiplexer, a diff viewer, or an editor. It does its core job — session triage — and offloads everything else to existing tools.

## The review flow

`skoga review <id>` is the canonical entry point for evaluating a session and deciding what to do with it. It combines diff summary, agent reasoning, and quick actions on one screen.

```
$ skoga review abc1234

Session abc1234 · implement signup flow                                
─────────────────────────────────────────────────────────────────────  
3 commits · 3 files changed (+127 -8) · rebased onto main 5m ago       
claude · 12m total · idle 4m                                           

Files changed:                                                         
  src/auth/signup.rs       +89 -0                                      
  src/routes.rs            +12 -2                                      
  tests/signup_test.rs     +26 -6                                      

Tests last run (4m ago): ✓ 47 passed, 0 failed                         

Agent summary:                                                         
  Goal:        Implement email signup with verification.               
  Approach:    JWT, reusing /auth/login conventions.                   
  Files:       3 (1 new, 2 modified).                                  
  Tests:       47 passing.                                             
  Open items:  None.                                                   
─────────────────────────────────────────────────────────────────────  
(d)iff  (c)heckout  (s)hell  (r)evise  (l)and  (k)ill  (q)uit          
> 
```

The review experience is built around three verbs that compose:

**Inspect:**
- `(d)iff` — pipes `git diff` to `$PAGER` (auto-detects `delta`/`difftastic` if installed).
- `(c)heckout` — runs `git worktree add` in the host clone so the dev runs the code in their real environment with their tools and env vars.
- `(s)hell` — drops into the sandbox worktree as the dev's user (read-only) for ad-hoc inspection.

**Iterate:**
- `(r)evise` — opens a text input for feedback, resumes the agent with that as the next instruction. Returns immediately; agent works in the background. This is the AI-native differentiator over PR review: "request changes" turns into "fixed in 2 minutes."

**Land:**
- `(l)and` — squash, push, open PR (see "The `skoga land` flow" below).

Test results in the review screen come from the audit log — the agent ran tests during the session, so we already have the result. No need to re-run. Optional config knob `[review] precheck = "npm test"` for explicit pre-review test runs (v1.5).

Line-anchored comments (GitHub-style "comment on line 42") are deferred to v1.5. V1 supports plain-text feedback only; the agent interprets `"src/auth.rs:42 should use bcrypt"` fine.

If the agent summary does not match what the dev sees in the diff, that is a red flag worth catching loudly — Skoga can do a simple heuristic check (does the summary's file list match the actual changed files?) and warn if they diverge.

## Host-sandbox divergence behavior

When the developer checks out a session branch in their host clone (via `skoga checkout` or manually) and makes changes, Skoga's behavior depends on session state. *Who is allowed to write to the branch* is a permission attached to the session state. Architectural details in [architecture.md → Bidirectional sync layer](architecture.md#bidirectional-sync-layer).

**Uncommitted dev edits in host worktree** — invisible to Skoga. No sync, no detection. The dev knows they have local edits; this matches standard git. `skoga review` shows committed state.

**Dev commits while session is `running`** (agent actively working) — not auto-absorbed. Skoga detects the divergence and surfaces it:
```
⚠ Your host clone has 1 commit ahead of the session, but the agent is still
  running. Absorbing now would risk conflicts.

Options:
  skoga absorb abc1234 --prefer-host       # rewind sandbox to host tip
  skoga absorb abc1234 --prefer-sandbox    # rewind host to sandbox tip
  skoga absorb abc1234 --merge             # 3-way merge in the host worktree
  git branch my-take skoga/abc1234         # fork off to your own branch
```

**Dev commits while session is `agent-exited`, `pr-open`, or `pr-merged`** — absorbed cleanly via the sync layer when host is a strict descendant of sandbox; on true divergence the same `skoga absorb` triage applies. The agent is no longer actively writing, so a small fix landing through the host worktree and propagating sandbox-ward is the natural "small fix during review" path.

**Dev commits while session is `conflicted` or `sync-broken`** — neither side moves automatically. Explicit `skoga absorb` (or `skoga sync --rebuild` for `sync-broken`) required.

For substantive dev work (rewriting modules, exploring alternate approaches), the convention remains: **fork off to your own branch.** Skoga is not trying to manage the dev's separate work, only collaboration with the agent on the session branch.

## The land → ship pipeline

The plan's single `skoga land` verb split during implementation into three verbs plus a daemon-side reconciliation step. The split keeps each verb a single deterministic git plumbing op:

```
running/agent-exited
        │
        │  skoga land    (squash → rebase → push → open PR via `gh`)
        ▼
     pr-open
        │
        │  daemon polls `gh pr view` and detects merge automatically
        ▼
     pr-merged
        │
        │  skoga ship    (terminate agent → remove worktree)
        ▼
       done
```

A side branch handles the "PR open, agent revising in response to review" case:

- `skoga push` — `git push -u` for the current branch as-is. Use this to update an already-open PR after an agent revises. No squash, no PR creation; agent commits ride along (the daemon's auto-checkpoint `wip:` commits will be squashed at a future `skoga land`, but `push` is intentionally a no-rewrite verb so the open PR stays stable on the reviewer's side).
- `skoga pr feedback` — bundle review comments + failing CI into a prompt and inject it into the agent. Compose with `skoga push` to ship the response.

Per Positioning Principle #7 ([planning.md](planning.md#positioning-principles)), the agent is not involved in pushing or PR creation. All three verbs run as the dev's UID with the dev's credentials.

### `skoga land` steps

1. Verify session state (branch exists, no in-flight rebase, no fatal divergence with host).
2. Auto-checkpoint any uncommitted agent changes (a final `wip:` commit).
3. **Sync pre-flight**: require `host_local_sha == host_tracking_sha` (sync converged). If the dev's host-side worktree has a fix that hasn't propagated to sandbox yet, run a synchronous host → sandbox tick and verify convergence. Shows a brief "syncing..." line; bounded by one tick interval (~2s). This preserves the invariant that every commit being pushed has existed in the sandbox at some point — relevant for the audit story and for `skoga revise` after land.
4. Opportunistic rebase against current `main` in a sidecar worktree.
5. Squash all session commits (including checkpoints and absorbed dev commits) into one.
6. Rename the branch from `skoga/<session-id>` to a human-readable name (configurable template).
7. Push to the dev's `origin` using the dev's git credentials.
8. Open a PR via `gh` CLI (fallback: print compare URL).
9. Transition the session to `pr-open`. The agent and worktree stay alive so the dev can iterate on review feedback via `skoga pr feedback` + `skoga push`.

### `skoga ship` steps

1. Confirm the session is `pr-open` or `pr-merged`. (`pr-open` re-checks via `gh pr view`; if the PR is merged, the daemon's reconciler will have moved the session to `pr-merged` anyway.)
2. Transition to `shipping` and return immediately — the rest is the daemon's async teardown task.
3. (Async) terminate the agent's tmux session, remove the worktree (heavy mode: through `sudo`), and emit `session.state_changed` → `done`.

**Commit message and PR body** — three sources, default to A:
- **A: Deterministic from session metadata.** Title from task description; body from the list of pre-squash commit messages plus the agent summary.
- **B: `--ai-summary`** — one-shot prompt to the agent before it terminates ("write a PR description for this work"). Costs a small amount of agent time but produces richer descriptions.
- **C: `--edit`** — open `$EDITOR` with A or B pre-filled.

PR description always includes a "Generated by Skoga session <id>" footer linking to the local audit log.

**Branch naming** — config knob:
```toml
[land]
branch_prefix = "skoga/"             # or "" or "feat/"
branch_template = "{slug}"           # or "{date}-{slug}" or "{session_id}-{slug}"
```

**Provider integration** — shell out to `gh` if available. For GitLab/Bitbucket in v1: detect remote, print compare URL, document `gh` as the only first-class provider. `glab` integration in v1.1.

**Conflicts at land time** — rebase against main may fail. Surface options:
```
✗ Rebase failed: conflicts in src/auth.rs, src/db.rs

  skoga land abc1234 --resolve-with-agent   # send agent back in to fix
  skoga shell abc1234                       # drop into sandbox to fix manually
  skoga land abc1234 --skip-rebase          # open PR against older base
  skoga kill abc1234                        # abandon
```

`--resolve-with-agent` is the AI-native option: re-launch the agent in the sandbox with a system message describing the conflict files. A clear Skoga differentiator over plain git tooling.

**No-PR mode** — for solo devs and trunk-based teams:
```
$ skoga land abc1234 --merge
✓ Squashed + rebased
✓ Fast-forwarded main → e3f8c2a
✓ Pushed origin/main
```

**Confirmation** — `skoga land` always prompts unless `--yes`:
```
About to land session abc1234:
  Branch:    skoga/abc1234 → implement-signup-flow
  Target:    origin/main
  Commits:   3 squashed into 1
  PR title:  "Implement signup flow"
Proceed? [Y/n]
```

The push and PR creation are remote- and colleague-visible; the one-prompt friction is worth it.

## First-session UX target

Install through first landed PR should be under 5 minutes on a clean repo:

```bash
$ brew install skoga
$ skoga init
✓ Ready.

$ cd ~/code/some-project
$ skoga start "add a hello world endpoint"
✓ Created session abc1234 on branch skoga/abc1234 from main
✓ You'll see the branch appear in this clone when the agent commits
✓ Launching claude...

[claude works for ~1 minute, commits, says done]

# In another terminal:
$ skoga review abc1234
[review screen with diff, summary, test results]
> l
About to land session abc1234: ...
Proceed? [Y/n] y
✓ Pushed implement-hello-world
✓ PR opened: https://github.com/.../pull/47
```

If this flow is not delightful, nothing else matters.
