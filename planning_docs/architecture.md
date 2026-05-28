# Skoga — Architecture

> Part of the Skoga planning docs. See [planning.md](planning.md) for the index and high-level overview.

## Language: Rust

This is infrastructure that manages people's most valuable artifacts (their code and git history). Memory safety, single-binary distribution, mature async ecosystem, brand signal.

Key crates to evaluate:
- **Tokio** for async runtime
- **Ratatui** for the TUI
- **Clap** for CLI parsing
- **Serde** for serialization
- **Git operations** — prefer subprocess to `git` over `gitoxide` for v1. `gitoxide` is promising but immature; shelling out to `git` is what every other tool does and is bulletproof. Reconsider for v2.
- **Local IPC** — Unix domain sockets with JSON-RPC. Simple, well-supported, easy to debug. Don't reach for gRPC for local IPC.

## Durability model

The daemon is a service that operates on persistent state, not the holder of that state. The filesystem and git are the source of truth.

- All session metadata is written to JSON files at `~/.skoga/state/sessions/<id>.json` synchronously on state transitions, with `0o600` mode (see [Security & file permissions](#security--file-permissions)). The daemon never relies on in-memory state surviving longer than a single operation.
- A SQLite database file (`~/.skoga/state.db`) is opened and migrated but **not** the source of truth in v1 — it's a forward-compatible placeholder for when the audit/events table needs indexed querying. The session JSON files are authoritative today.
- Audit events flush to NDJSON at least every few seconds. The daemon's broadcast channel also fans out every event to live `events.subscribe` clients (the Mac app and `skoga logs --follow`).
- Worktrees and git refs in the sandbox are independently authoritative. On daemon restart, scan worktrees, read the session JSON, reconcile.
- Agent processes run inside per-session tmux sessions named `skoga-<id>`. They survive daemon restart, terminal close, and laptop sleep. On daemon restart the daemon does not "reattach" — tmux has been supervising the whole time; the daemon just rebuilds its in-memory map from `tmux list-sessions` and reconciles against the on-disk sessions. No agent PIDs are persisted as primary state.
- On daemon restart, never auto-delete. Orphaned worktrees (no matching session JSON) are surfaced via `skoga prune` for explicit user decision; orphaned tmux sessions are reaped on a grace timer.
- Manual recovery never requires the daemon. A developer can always drop into a worktree (heavy mode: `sudo -u skoga-$USER`) and extract their work with standard git, even if Skoga is permanently broken. `skoga export <id>` (patch by default, `--bundle` for a git bundle) is the escape hatch when the session itself should go away.

## Component layout

```
skoga/
├── skogad/          # The daemon. Owns persistent state, the event bus, and
│                    # background loops (sync, rebase, checkpoint, cleanup,
│                    # queue, conversation reconstruction).
├── skoga-cli/       # The CLI. Thin client of skogad for state lookups +
│                    # subscriptions; runs all *action* verbs (land, push,
│                    # absorb, diff, checkout, …) in-process. The Mac app
│                    # is the second client of the same socket.
├── skoga-tui/       # Minimal ratatui dashboard. Runs as `skoga` (no args)
│                    # and as the top pane inside `skoga cockpit`.
├── skoga-core/      # Shared types, protocol definitions, audit log, paths,
│                    # session/queue/config persistence helpers. Used by
│                    # skogad and skoga-cli alike.
├── skoga-sandbox/   # Lite + heavy sandbox provisioning, launchd plist
│                    # rendering, sudoers drop-in, sandbox-exec profile.
├── skoga-git/       # Git command wrappers (sudo-aware for heavy mode),
│                    # worktree and branch orchestration primitives.
├── skoga-agents/    # `Agent` trait + the Claude Code adapter. The trait
│                    # already supports the capability surface for future
│                    # adapters (exec, Codex, …) — registry is the
│                    # gating piece, not the trait shape.
└── skoga-tmux/      # Thin wrappers around tmux subcommands (new-session,
                     # pipe-pane, send-keys, load-buffer/paste-buffer,
                     # list-sessions, kill-session). The single supervision
                     # substrate for every agent.
```

A separate Swift/SwiftUI Xcode project (`skoga-mac`) consumes the same `skogad` socket via JSON-RPC; it is not a Cargo workspace member. See [the Skoga roadmap](private/roadmap.md#9-repository-and-technology-architecture).

## The local API (daemon ↔ clients)

This is the contract that everything hangs off.

Transport: Unix domain socket at `~/.skoga/sock`, mode `0o600`, peer-uid checked on every accept (same-uid only; root rejected too). Foreign-uid attempts emit a `daemon.rpc.rejected` audit event.

Format: JSON-RPC 2.0 over newline-delimited lines. Why: human-readable, debuggable with `socat`, well-supported in every language (the Mac app implements it directly over Darwin sockets to bypass `NWConnection`'s peer-credential quirks).

### Design principle: daemon holds state, CLI does work

A v1 architectural fact worth stating loudly: **the daemon is a state and event bus, not the orchestrator**. Actions like `skoga land` / `push` / `absorb` / `diff` run inside the CLI process (which inherits the dev's TTY, `gh`, `ssh`, editor) and notify the daemon via narrow state-update RPCs (`session.mark_pr_open`, `session.set_host_worktree`, …). The daemon owns:

- persistent state (session JSON, queue items, config)
- background loops (sync, rebase, checkpoint, cleanup, queue dequeue)
- the audit log writer
- the event broadcast channel that feeds `events.subscribe` consumers

This shape made the Mac app possible without code-sharing pain (it's a second client of the same socket). It also means the Mac app today can `create` / `kill` / `list` / read conversation but cannot yet `land` from the UI — see the open question in [planning.md](planning.md#open-questions-to-revisit-during-build) about whether daemon RPCs should grow real action endpoints.

### RPC methods (request/response)

Session state and orchestration:

- `session.list(include_terminal?)` → `[Session]`
- `session.list_terminal({ limit?, cursor?, since?, until? })` → `{ sessions: [Session], next_cursor?, total_estimate? }`. Paginated, terminal-state-only listing used by the Mac History view (skoga-mac#34). Sort: descending by terminal-transition time, tie-break by id. `cursor` is opaque to the client and stable across daemon restarts. `since`/`until` are RFC3339 timestamps filtering on terminal-transition time. `limit` defaults to 50 and is capped at 200 server-side.
- `session.create(task, agent, base, repo_root, task_auto?, auto_launch?, initial_prompt?)` → `{ session }`. With `auto_launch: true`, the daemon spawns a detached `skoga _dispatch_launch` subprocess that installs the adapter's in-worktree config and starts the agent in tmux. (`skoga start` invokes the launch path itself; the Mac app's Dispatch view sets `auto_launch: true`.)
- `session.conversation(id)` → `{ messages }`. Reconstructs the conversation by parsing the Claude Code transcript jsonl for the session. Stable per-record `id`s so subscribers' lists preserve scroll position across refetches.
- `session.attach(id)` → resolves the tmux session name + (if alive) prepares any pending revise/feedback paste-buffer. The CLI side then exec's `tmux attach-session`; the daemon does not stream PTY.
- `session.revisit(id)` → revive a past session's agent against today's `main` in a fresh worktree.
- `session.kill(id)` → mark `Killing`, async teardown.
- `session.ship(id)` → mark `Shipping`, async teardown after PR merge.
- `session.rename(id, new_task)` → re-label + branch rename.
- `session.record_agent_session`, `session.mark_waiting`, `session.clear_waiting`, `session.mark_idle`, `session.clear_idle`, `session.set_host_worktree`, `session.set_agent_summary`, `session.mark_pr_open`, `session.mark_pr_merged`, `session.mark_done` — narrow state-update calls invoked by CLI verbs and Claude Code hooks.

Audit, queue, config, daemon:

- `audit.emit(session_id?, type, actor, payload, correlation_id?)` — emit one event through the daemon's writer (keeps per-scope `seq` monotonic).
- `queue.add(message, agent, base?, task?)` / `queue.list()` / `queue.remove(id)` — kickoff queue management.
- `config.get(key)` / `config.set(key, value)` / `config.list()` / `config.snapshot()` / `config.unset(key)`.
- `daemon.health()` / `daemon.version()`.

### Subscriptions (server push on the same socket)

A single subscription method that upgrades the connection to a server-push stream:

- `events.subscribe` → `{ "subscribed": true }`, after which the daemon writes `events.event` notifications (JSON-RPC notifications, no `id`) for every event that lands in the audit log. Subscribers debounce + refetch as needed; the Mac app treats any event as a "refetch `session.list`" trigger.

There is no separate `events.sessions` / `events.session(id)` / `events.conflicts` method — one stream, filtered client-side. Lagging subscribers drop oldest events (Tokio broadcast semantics) rather than blocking the daemon.

## State storage

The daemon needs persistent state across restarts:
- **Session metadata** as JSON files under `~/.skoga/state/sessions/<id>.json`, written with `0o600` mode via `paths::write_secure`. The schema lives in `skoga_core::session::Session`.
- **Queue items** under `~/.skoga/state/queue/` as JSON, same mode.
- **Audit events** as append-only NDJSON files at `~/.skoga/audit/sessions/<id>/<YYYY-MM-DD>.ndjson` and `~/.skoga/audit/system/<YYYY-MM-DD>.ndjson` (see [audit-schema.md](audit-schema.md)). Files are `chmod 0o600` after each append for the migration case.
- **Config** as TOML at `~/.skoga/config.toml`, also `0o600`.
- **SQLite** at `~/.skoga/state.db` is opened with WAL but currently unused for primary state. Reserved for the audit/events query workload (`skoga logs --since` over months of data) when that becomes a real need.
- **Sandbox-side repo clones** under `<sandbox_root>/repos/<proj>-<hash>/`.
- **Sandbox-side session worktrees** (where the agent edits) under `<sandbox_root>/sessions/<id>/`.
- **Host-side review worktrees** (opt-in; created by `skoga checkout`) under `~/.skoga/host-worktrees/<id>/`.
- **tmux server socket** — default tmux path in lite mode (daemon, tmux, agent all the dev's UID). Heavy mode routes through `sudo -u skoga-$USER` to a sandbox-owned socket; that path is implemented for the sandbox provisioning steps but tmux-as-sandbox-user is deferred (see the heavy-mode caveat in [planning.md](planning.md#v1-explicit-non-goals)).

`<sandbox_root>` resolves to `/Users/skoga-$USER` in **heavy** mode (separate macOS user) and `~/.skoga/sandbox` in **lite** mode (sandbox-exec only, dev's user). Both modes use two clones; the sync layer runs in both. Lite mode trades the UID-level isolation of heavy mode for ~2× `.git` disk and the file-/network-level restrictions described under [Sandbox provisioning](#sandbox-provisioning) below.

JSON for state, NDJSON for audit. Don't get fancy.

## Security & file permissions

The daemon and its on-disk state are local-only, but Skoga ships under threat models that include (B) colocated unprivileged users on the same machine and (A) prompt-injected agents running inside a worktree. Concrete invariants:

- Unix socket at `~/.skoga/sock` is `chmod 0o600`. Every connection runs through a `getpeereid` (macOS) / `SO_PEERCRED` (Linux) check; only the daemon's own uid is accepted. Foreign uids (including root) are rejected at accept time and the rejection is recorded as a `daemon.rpc.rejected` audit event.
- `~/.skoga/` and every directory created under it are `chmod 0o700` (`paths::ensure_dir_0700`).
- Every state, queue, config, and audit file is `chmod 0o600` at write time. New writes go through `paths::write_secure` (truncate-create-secure) or `paths::chmod_0600_if_exists` (append). Older world-readable files written by a previous version are migrated to `0o600` on next write.
- `--yes` on `skoga land` / `skoga push` is refused when the invocation comes from inside a Skoga-managed agent tmux session (detected via `$TMUX` + `tmux display-message -p '#S'`). Without this guard, a prompt-injected agent running as the dev's UID in lite mode could shell out to `skoga push --yes` against its own worktree and bypass the human-in-the-loop confirmation.
- The git credential helper template for the read-only PAT is interpolated through a POSIX single-quote escaper (`posix_single_quote`) so a `'` in `$SKOGA_HOME` or `$HOME` cannot break out of the quoted `$(cat '…')` slot.

## Sandbox provisioning

### Heavy path

On first run:
1. Check if `skoga-$USER` exists. If not, prompt for admin password and create it (via `dscl` and `sysadminctl`).
2. Set up the home directory with appropriate restrictions.
3. Create the directory structure for repos and sessions under `/Users/skoga-$USER/`.
4. Set up ACLs so the developer user can read but not write the sandbox tree.
5. Install a `sandbox-exec` profile that further restricts agent processes.

This is the riskiest single piece of the codebase. It requires admin and it touches user accounts. Errors here can break the developer's machine. Test the hell out of it; have a `--repair` mode; document recovery procedures. See [developer-experience.md → Install, first-run, and uninstall](developer-experience.md#install-first-run-and-uninstall) for the user-facing flow.

In heavy mode, the agent's UID has no GitHub credentials, no `~/.ssh` access, and no `gh` binary in its accessible paths. Push is architecturally impossible.

### Lite path

`--lite` mode skips the separate user. The sandbox clone and session worktrees live under `~/.skoga/sandbox/` (owned by the dev user). Sync runs the same way as heavy. The sandbox-exec profile carries the isolation:

- File-read denied on `~/.ssh`, `~/.config/gh`, `~/.gitconfig` (which may hold credential helpers / tokens), and the resolved path of the `gh` binary.
- Daemon scrubs `GH_TOKEN`, `GITHUB_TOKEN`, `GH_HOST`, and similar from the agent's env on spawn.
- Object-database isolation by construction: sandbox clone is a separate `.git`, so the agent can't read commits from unrelated branches in the dev's main repo.

Network restrictions for lite mode are deferred to phase 2 implementation — denying outbound to `github.com` etc. breaks workflows that fetch deps from GitHub, so we may rely on credential / binary absence alone. Decision made when we can test real workflows.

Lite mode's push prevention is "functionally impossible via sandboxing" (multiple file/env restrictions, requires breaking all of them). Heavy mode's is "architecturally impossible" (separate UID with no creds). Docs and the install flow should frame the two differently.

## Worktree orchestration mechanics

A session branch (`skoga/<id>`) may have up to three worktrees:

| Worktree | Where | Created | Removed |
|---|---|---|---|
| **Agent worktree** | `<sandbox_root>/sessions/<id>/` in the sandbox clone | at session start, always | at session cleanup |
| **Host-side review worktree** | `~/.skoga/host-worktrees/<id>/` in the host clone | opt-in, on `skoga checkout <id>` | at session cleanup or `skoga checkout --remove` |
| **Rebase sidecar** | transient path in the sandbox clone | start of `skoga land` | end of `skoga land` |

The dev's main worktree is never operated on by Skoga.

Key invariants:
- The agent's worktree is *never* operated on by anything except the agent itself and the sync layer's FF logic.
- Rebases happen opportunistically (at quiescent points, not continuously) in sidecar worktrees, then fast-forward the agent's worktree.
- Bidirectional sync between host clone and sandbox clone is via git remotes. Agent commits surface as `skoga/<session-id>` branches in the host clone, which is the developer's primary git interface.
- Session branches are read-only by convention in the host clone. If a developer wants to make their own commits against an agent's work, they either fork off (`git checkout -b ...`) or run `skoga checkout <id>` and work in the host-side review worktree.
- Branches are real branches with sane names (`skoga/<session-id>`).

## Bidirectional sync layer

The sync layer keeps the session branch (`skoga/<session-id>`) consistent between the sandbox clone and the host clone. It is local-only — never touches `origin` — and is state-aware: rules for who can write to a branch depend on session state.

This layer is **load-bearing for the rest of the system.** Multiple design choices (isolation, recovery, developer review UX) rest on it being rock-solid. Sync bugs mean divergent copies of the user's code and lost work.

### Data model

For each active session, the sync controller tracks three SHAs and one path:

| Name | Where | Meaning |
|---|---|---|
| `sandbox_sha` | sandbox clone's `refs/heads/skoga/<id>` | what the agent sees as the branch tip |
| `host_tracking_sha` | host clone's `refs/remotes/skoga-sandbox/<id>` | what the host clone has fetched from sandbox |
| `host_local_sha` (nullable) | host clone's `refs/heads/skoga/<id>` | only present once `skoga checkout <id>` has materialized a host-side worktree; null otherwise |
| `host_worktree` (nullable) | path of the host-side review worktree, plus dirty-state cache | null until `skoga checkout` runs |

The split between `host_local_sha` and `host_tracking_sha` is critical: **the remote-tracking ref always advances (even on force-push); the local branch only fast-forwards.** That gives a place to record "the sandbox is at X" without ever clobbering the dev's checked-out branch.

The common case during `running` is `host_local_sha = null` — the dev hasn't run `skoga checkout` and only the tracking ref is updated. `skoga diff`, `skoga review`, `skoga show` all read commits via the tracking ref without requiring a host-side worktree.

State is in-memory only. On daemon restart, re-read from the two repos. Git refs are the source of truth; the cache is just for change detection.

### State machine: who can write when

The sync layer keys off the actual session state machine ([`skoga_core::session::State`](../crates/skoga-core/src/session.rs)). The shape:

```
running | agent-exited:
  Authority: sandbox is the writer; host receives updates.
  Allowed:   sandbox → host  (advance remote-tracking ref always;
                              fast-forward host local branch IF it exists
                              and FF is possible; otherwise leave it alone)
             host → sandbox  IF the agent is quiescent (running but idle,
                              or agent-exited) AND host_local_sha is
                              ahead AND FF works
  Detected:  host_local_sha diverging from sandbox_sha
             → emit `sync.divergence_detected`, do not propagate

pr-open | pr-merged:
  Authority: either (agent paused awaiting review; dev may make small fixes).
  Allowed:   sandbox → host  (same as running)
             host → sandbox  IF host_local_sha is ahead AND FF works
  Detected:  true divergence (each side has commits the other doesn't)
             → emit `sync.divergence_detected`, no auto-resolution

conflicted:
  Authority: nobody — most recent opportunistic rebase aborted in a
             sidecar worktree; agent worktree is on the pre-rebase tip.
  Allowed:   no sync writes; next rebase tick retries.
  Recovery:  agent fix-up (`skoga revise` / `skoga attach`) or manual.

sync-broken:
  Authority: nobody — sync layer hit repeated hard faults (disk, ACL,
             repo corruption).
  Allowed:   only `skoga sync --rebuild <id>` (exports the branch as a
             recovery bundle, re-fetches the host side).

shipping | killing:
  Async teardown is in flight. Sync stops; cleanup decides ref fates.

done | killed:
  Terminal. Sync stops. Branches retained per cleanup policy until prune.
```

This state machine is the heart of the sync layer. Everything else is plumbing. (Earlier drafts of this doc described a `waiting-for-review` state and an explicit `suspended` state — those collapsed during implementation into the `pr-open` / `pr-merged` / `agent-exited` trio, which proved a cleaner mapping to "what is git seeing right now.")

### Bootstrap

**First session in a repo.** The sandbox clone doesn't exist yet. Daemon clones the host repo into the sandbox path:

```bash
git clone --local ~/code/proj <sandbox_root>/repos/proj
```

`--local` hardlinks objects (space-efficient) but creates an independent object DB (the sandbox is not dependent on the host clone's index — if the dev later prunes a branch, the sandbox is unaffected).

**Each session create** (regardless of whether the sandbox clone is new or existing):

1. Resolve `base` (default: current `HEAD` of host clone's checked-out branch).
2. Fetch the base ref from host into sandbox so the base commit is reachable there:
   ```bash
   git -C <sandbox_clone> fetch <host_clone> +refs/heads/<base>:refs/remotes/host/<base>
   ```
3. Create `refs/heads/skoga/<id>` in the sandbox clone at the base commit.
4. Add the agent's worktree at `<sandbox_root>/sessions/<id>/` checked out to that branch.
5. Run an initial sandbox → host fetch so the host clone has `refs/remotes/skoga-sandbox/<id>` from the start.

### Per-tick fetch

Both sync directions use plain `git fetch` between local paths — fast (hardlinks for objects on same filesystem), bulletproof, no custom code:

```bash
# sandbox → host (daemon, running as dev user):
git -C ~/code/proj fetch <sandbox_root>/repos/proj.git \
    +refs/heads/skoga/<id>:refs/remotes/skoga-sandbox/<id>

# host → sandbox:
#   heavy mode (via sudo to sandbox user):
sudo -u skoga-$USER git -C <sandbox_root>/repos/proj fetch \
    ~/code/proj \
    +refs/heads/skoga/<id>:refs/heads/skoga/<id>
#   lite mode (same user, no sudo):
git -C <sandbox_root>/repos/proj fetch \
    ~/code/proj \
    +refs/heads/skoga/<id>:refs/heads/skoga/<id>
```

The `+` prefix forces the remote-tracking ref to follow the source (always safe; it's a tracking ref).

### FF mechanics: how local branches advance

The local-branch update is NOT forced — applied only when it's a fast-forward (computed via `git merge-base --is-ancestor`). *How* the branch advances depends on whether a worktree has it checked out:

- **No worktree has the branch checked out** → `git update-ref refs/heads/skoga/<id> <new_sha>` is safe.
- **A worktree has the branch checked out** → git refuses to update the ref directly. Use `git -C <worktree> merge --ff-only <new_sha>` against that worktree instead.

This matters in two places:

- **Sandbox-side FFs (host → sandbox, in `waiting-for-review`)**: the agent's worktree is *always* on the session branch. Sandbox FFs *always* use `merge --ff-only` against the agent's worktree. This requires the agent to be quiescent — already enforced by the state machine (host → sandbox is forbidden during `running`).
- **Host-side FFs (sandbox → host, when `host_local_sha` exists)**: if the dev ran `skoga checkout`, the host-side review worktree has the branch checked out. Use `merge --ff-only` against that worktree. If a worktree has the branch but is dirty, FF is **deferred**, not broken (see Error handling).

### Triggers

Two-layer:
- **Polling tick** every ~2 seconds (configurable). The correctness guarantee.
- **Event-driven** via post-commit hooks in both clones for sub-second latency in the happy case. Best-effort optimization.

For v1, polling-only is acceptable. Add hooks later if latency proves to be an issue. `git fetch` between local repos on the same filesystem is typically sub-100ms; 2-second polling is plenty fast.

### Permissions

The daemon runs as the dev user.

- **Heavy mode**: sandbox-side writes (host → sandbox direction) shell out via `sudo -u skoga-$USER`. `skoga init` configures sudoers to allow `git` invocations as the sandbox user without a password.
- **Lite mode**: daemon, agent, and both clones run as the same user. No `sudo`. Sync layer still runs (it's still two clones with different refs); fetches are just same-user file ops.

### True divergence: the hard case

The only "real conflict" possible:
- Sandbox has commits `H1 → H2 → H3` (agent's work)
- Host has commits `H1 → H2' → H3'` (dev's separate commits on top of an older fork point)

Skoga does not auto-merge. It surfaces and waits:

```
⚠ Session abc1234 has diverged.
   Sandbox is 2 commits ahead since merge-base.
   Host clone is 2 commits ahead since merge-base.

   skoga absorb abc1234 --prefer-host       # sandbox = host; agent loses 2 commits
   skoga absorb abc1234 --prefer-sandbox    # host = sandbox; dev loses 2 commits
   skoga absorb abc1234 --merge             # invoke `git merge` (may conflict)
   skoga shell abc1234                      # I'll fix it manually
```

The `--merge` option pairs naturally with `--resolve-with-agent` (same pattern as `skoga land` conflicts) for the AI-native resolution path.

### Absorb mechanics

How each strategy actually moves SHAs around:

- **`absorb --prefer-sandbox`**: force-set host's local branch to sandbox tip.
  - If no host-side worktree has the branch checked out: `git -C <host_clone> update-ref refs/heads/skoga/<id> <sandbox_sha>`.
  - If the host-side review worktree has it: `git -C <host_worktree> reset --hard <sandbox_sha>`. Confirm prompt if the worktree has uncommitted changes (they'd be dropped). `--force` skips the prompt.
  - If the dev's *main* worktree has the branch checked out (off-script): refuse with a clear message; dev must switch branches first.
- **`absorb --prefer-host`**: force-set sandbox to `host_local_sha`. Requires session to be paused (`suspended` or `waiting-for-review`); refuse otherwise with a hint to `skoga suspend` first. `git -C <agent_worktree> reset --hard <host_local_sha>`. Agent on resume gets a status line noting prior tip is in reflog.
- **`absorb --merge`**: requires a host-side review worktree (create one if needed). `git -C <host_worktree> merge <sandbox_sha>`. Conflicts surface in the host worktree with standard markers; dev resolves there. After commit, next tick's host → sandbox FF pushes the merge commit into the sandbox.

`absorb` never touches the dev's main worktree.

### Error handling

Two failure modes, distinguished because they have different recovery semantics:

- **`sync.deferred`** — the fetch can't apply *this tick* due to dev-side state (host-side worktree is dirty, branch checked out in the dev's main worktree, etc.). Not an error. Audit emits `sync.deferred` with a reason; daemon retries on the next normal tick; status line in the TUI/agent terminal lets the dev know their local view is behind sandbox by N commits. No backoff.
- **`sync.broken`** — system fault: disk full, ACL not set, repo corruption, sandbox clone missing, etc. Mark session as `sync-broken`; surface in TUI; back off exponentially up to `backoff_max`. `skoga doctor` and `skoga sync --debug <id>` are the debugging paths. `skoga sync --rebuild <id>` re-clones the sandbox (after exporting the session branch as a patch to a safe location first).

### Out of scope for sync (v1)

- Tags, notes, reflog entries, stashes — only the session branch ref matters.
- Multi-branch sync — each session has one branch; sync is per-session.
- Partial transfers / streaming — fetch operations are small enough.
- Network operations to `origin` — exclusively `skoga land`'s job.

### Configuration

```toml
[sync]
poll_interval = "2s"          # how often to check for changes
backoff_max = "60s"            # max backoff on errors
event_hooks = false            # enable git hook triggers (v1.5)
```

## Agent process lifecycle

tmux is the agent runtime host. Every agent runs inside a tmux session named `skoga-<id>`. This gives Skoga durable supervision, detachable terminals, and a uniform output stream (via `pipe-pane`) without any custom PTY code. tmux is a hard dependency, checked by `skoga init` and `skoga doctor`.

This choice is agent-agnostic — it's the same substrate for Claude Code, Codex, and the generic `--exec` wrapper. Agent-specific hooks (when available) layer on top of tmux; they are not a parallel runtime.

### Per-session lifecycle

1. Daemon creates the tmux session:
   ```bash
   tmux new-session -d -s skoga-<id> -c <agent_worktree> -- <agent-launch-cmd>
   ```
   In **heavy** mode this is wrapped in `sudo -u skoga-$USER tmux -S <sandbox_root>/run/tmux.sock ...` so the tmux server runs as the sandbox user. The dev-side daemon reads the same socket via ACL. In **lite** mode, daemon, tmux, and agent all run as the dev user; no sudo, default socket.
2. Daemon enables output capture: `tmux pipe-pane -o -t skoga-<id> 'cat >> <audit_dir>/<id>/pty.log'`. This stream is the uniform floor for the activity feed — for agents without structured hooks (Codex, generic `--exec`) it's the primary signal; for agents with hooks (Claude Code) it's a belt-and-suspenders fallback.
3. For agents that support hooks, the daemon additionally configures the hook channel. Hooks remain the primary signal where available.
4. `skoga attach <id>` exec's `tmux attach-session -t skoga-<id>` (heavy mode: via the sandbox-user socket). Detach is the tmux default `Ctrl-b d`. The agent keeps running.
5. `session.input(id, text)` and `skoga revise <id> <feedback>` send keystrokes via `tmux send-keys -t skoga-<id>`. No custom PTY-input plumbing. Multi-line payloads (e.g. `skoga land`'s rebase-conflict fix-up prompt) go through `tmux load-buffer` + `tmux paste-buffer -p` (bracketed paste) instead, so the agent's TUI receives them as a single paste event rather than a stream of submitted lines. When the agent's tmux session isn't alive, the handler falls back to printing the prompt for the dev to copy-paste manually.
6. Daemon monitors the agent via tmux: `session-closed` hook + periodic `tmux list-sessions` reconciliation. On agent exit, tmux tears down the session and Skoga transitions to the appropriate terminal state.
7. On daemon restart, no reattach step is needed. The daemon rebuilds its `session_id → tmux session` map from `tmux list-sessions` and reconciles against SQLite. Any tmux session without a matching SQLite row, or vice versa, surfaces via `skoga recover` for explicit user decision.

### Heavy-mode permissions

The sudoers entry that `skoga init` installs (already allowing `git` as `skoga-$USER`) is extended to allow `tmux`. The dev-side daemon does not need a tmux server of its own; it only talks to the sandbox user's server via `-S <socket>`.

### Why tmux

- Removes a whole class of custom code (PTY plumbing, PID tracking, zombie reaping, reattach-on-restart).
- Battle-tested supervision: 20+ years of edge cases already handled.
- Same model works for every agent CLI, present and future.
- Users running parallel AI agents already use tmux in high overlap; the dependency is not load-bearing on adoption.

## Agent integration layer

Skoga supports any CLI coding agent via a small adapter contract. Built-in adapters for Claude Code, Codex, and a generic `--exec` wrapper ship with v1; additional agents can be declared in config without recompiling.

This layer lives in the `skoga-agents` crate. tmux supervises the process (see [Agent process lifecycle](#agent-process-lifecycle)); the adapter describes *which command to run, how to configure the agent's in-worktree settings, and which optional capabilities to wire up*.

### Adapter contract

Sketch (not final API):

```rust
trait Agent {
    fn id(&self) -> &str;                                       // "claude", "codex", "exec:<name>"
    fn launch_command(&self, ctx: &AgentLaunchCtx) -> Command;  // REQUIRED — the floor

    // Optional — default impls are no-op / unsupported.
    fn install_session_config(&self, worktree: &Path) -> Result<()> { Ok(()) }
    fn capabilities(&self) -> AgentCapabilities { AgentCapabilities::default() }
}

#[derive(Default)]
struct AgentCapabilities {
    structured_hooks: bool,     // can call Skoga's hook endpoints
    waiting_status: bool,       // can report blocked-on-user
    boundary_check: bool,       // can enforce per-edit boundary at PreToolUse equivalent
    session_summary: bool,      // can produce structured end-of-session summary
    attention_indicator: bool,  // tmux pane title carries an attention glyph
}
```

`launch_command` is the floor. Everything else is opt-in. An agent that opts into nothing still works: tmux supervises it, `pipe-pane` feeds the activity log, commits drive the audit signal.

### Hook endpoints

The CLI exposes a small set of agent-agnostic `skoga _<event> <session-id> [...]` subcommands that any agent's hook glue can call:

- `skoga _notification <id>` — sets `waiting_since`.
- `skoga _on_stop_clear_waiting <id>` — clears `waiting_since`.
- `skoga _check_path <session_dir> <id>` — boundary check; exits non-zero if a path is outside the worktree.
- `skoga _on_summary <id> <json>` — capture a structured session summary.

These form the stable contract that agent-side glue (Claude's `.claude/settings.local.json`, Codex's TBD config, future agents) calls into. Adding a new agent does not require adding new endpoints unless it surfaces a fundamentally new signal.

### Built-in adapters and capability matrix

| Adapter | Launch | In-worktree config | Hooks | Waiting | Boundary | Summary |
|---|---|---|---|---|---|---|
| `claude` (Claude Code) | `claude` + flags | `.claude/settings.local.json` | ✅ | ✅ | ✅ | ✅ (lazy via `claude --resume -p`) |
| `exec` (generic wrapper) | user-supplied command | none | ❌ | ❌ | ❌ | ❌ |
| `codex` (Codex CLI) | `codex` + flags | TBD | depends | maybe | ❌ | planned |

**v1 ships `claude` only.** The trait and capability surface are designed for the other two — `exec` is ~50 lines of glue plus the `[agents.<name>]` config-driven registry; `codex` is a real integration effort that depends on Codex's extension API. Both are scoped for v1.1.

Capability gaps are *features*, not blockers. An agent that supports only `launch_command` still gets the full workflow (sandbox isolation, commits, sync, land, audit); the optional layers (attention, waiting, summary) are graceful absences.

### Declaring custom agents

Users can declare agents in `~/.skoga/config.toml`:

```toml
[agents.aider]
binary = "aider"
args = ["--no-auto-commits"]
# optional: env, sandbox profile overrides

[agents.cursor-cli]
binary = "cursor-agent"
args = []
# Capabilities default to "exec only" unless the agent calls Skoga's hook
# endpoints itself.
```

User-declared agents behave exactly like built-ins. `skoga start --agent aider "task"` is enough to use one. v1 ships built-in adapters for Claude, Codex, and `exec`; new agents arrive as a no-code feature.

### Why not a dynamic plugin model

Trait + config registry is the v1 ceiling. Dynamic plugin loading (dylibs, WASM, IPC plugins) raises ABI/trust/distribution questions that aren't worth the complexity until a real user needs a capability outside the static set. The hook endpoints are the extension point: a sufficiently motivated agent author can call them from their own code today.
