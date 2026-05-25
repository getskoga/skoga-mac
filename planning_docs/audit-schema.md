# Skoga — Audit Event Schema

> Part of the Skoga planning docs. See [planning.md](planning.md) for the index and high-level overview.

This document specifies the audit event format. The schema is a **stable contract** — adding new optional fields or new event types is backward-compatible; removing or renaming fields, or changing event semantics, bumps the schema version.

## Purpose

The audit event stream serves four consumers, in order of v1 importance:

1. **The TUI activity feed** — what makes the dashboard feel alive. "agent wrote 3 files, ran tests, committed."
2. **The review experience** — `skoga review` surfaces "what did the agent actually do" from the event stream.
3. **Local recovery and debugging** — `skoga logs`, diagnosing weird state, understanding what happened before a crash.
4. **The commercial control plane (future)** — this stream is the substrate. The commercial product is mostly a sanitizing uploader on top of this schema.

Because #4 exists, the audit schema is treated as load-bearing as much as the local API.

## Storage

NDJSON files at `~/.skoga/audit/`. One file per session per day:

```
~/.skoga/audit/
  sessions/
    abc1234/
      2026-05-19.ndjson
      2026-05-20.ndjson
    def5678/
      2026-05-19.ndjson
  system/
    2026-05-19.ndjson      # daemon-level events (no session_id)
```

Per-session-per-day granularity enables easy retention, easy `skoga logs <id>`, and easy archival.

## Event format

```json
{
  "schema_version": 1,
  "ts": "2026-05-19T14:24:01.456Z",
  "session_id": "abc1234",
  "seq": 17,
  "type": "agent.tool_call",
  "actor": "agent",
  "payload": { ... },
  "correlation_id": "tc-xyz",
  "context": { ... }
}
```

| Field | Required | Notes |
|---|---|---|
| `schema_version` | yes | Integer. Per-event for self-description. Bumps only on breaking changes. |
| `ts` | yes | ISO 8601 UTC with millisecond precision. |
| `session_id` | for session events | Denormalized for filtering. Null for system events. |
| `seq` | yes | Monotonic within session. Disambiguates same-timestamp events; detects dropped events. |
| `type` | yes | Dotted namespace, two levels: `<category>.<action>`. |
| `actor` | yes | One of `user`, `agent`, `skoga`. Type usually implies actor, but it's explicit for cases where it doesn't (e.g., `git.commit` may be either agent or skoga). |
| `payload` | yes | Type-specific data. Each event type has a documented payload schema. |
| `correlation_id` | optional | Skoga-assigned. Links related events (e.g., `agent.tool_call` → `agent.tool_result`). |
| `context` | optional | Environment metadata (agent name+version, daemon version). |

### Correlation IDs

**Skoga assigns correlation IDs** — the agent does not provide them. When the wrapping layer emits a `tool_call` event, it generates the ID and reuses it for the matching `tool_result`. Format is opaque to consumers; treat as a string identifier.

## Event categories

### Session lifecycle
- `session.created` — user issued `skoga start` (or the daemon's `session.create` RPC). Payload: `{task, agent, base, cwd}`.
- `session.started` — agent process spawned, worktree ready. Payload: `{worktree, branch, base_sha}`.
- `session.launch_failed` — `auto_launch=true` was requested but the detached `_dispatch_launch` subprocess failed before the agent came up. Payload: `{error}`.
- `session.state_changed` — any state transition. Payload: `{from, to, reason}`. This is the canonical signal for `session.killed` / `session.shipped` / `session.synced_broken` — those don't get their own event types; subscribers project on the `to` field.
- `session.landed` — `skoga land` completed (PR opened). Payload: `{final_sha, branch, pr_url?}`.

There are no `session.suspended` / `session.resumed` events in v1 — the state machine doesn't have a `suspended` state. An agent that has stopped working is either `agent-exited` (process gone) or `running` with `idle_since` / `waiting_since` markers set, both of which surface via the next `session.state_changed` or the `agent.idle` / waiting marker on the session record.

### Agent activity
- `agent.tool_call` — agent invoked a tool (read, edit, write, bash, etc.). Payload: `{tool, args}`. **Metadata only** — file contents are NOT captured; only path, size, line counts.
- `agent.tool_result` — tool completed. Payload: `{tool, result, bytes?, exit_code?}`. Correlated to the matching `tool_call` via `correlation_id`.
- `agent.error` — agent crashed or reported an error. Payload: `{kind, message}`.
- `agent.idle` — agent finished its turn, awaiting input or completion.
- `agent.summary` — the final structured summary at session end. Payload: `{goal, approach, files, tests, open_items}`.

What's NOT captured by default: full chat transcript. Tool calls + summary are sufficient for review and audit. Full transcript is opt-in via `[audit] capture_transcript = true` (v1.5).

### Git operations
- `git.commit` — any commit on the session branch. Actor is `agent` (normal commits) or `skoga` (checkpoints, rebases). Payload: `{sha, message, files, lines_added, lines_removed}`. Diff content is NOT in the event — recoverable from the commit itself via git.
- `git.checkpoint` — Skoga-issued `wip:` auto-checkpoint. Payload: `{sha, files_changed}`.
- `git.rebase` — rebase performed. Payload: `{onto, before_sha, after_sha, result: "clean" | "conflict"}`.
- `git.fetch` — sync fetch operation. Payload: `{from, to, direction, ref}`.
- `git.force_update` — a branch ref moved non-fast-forward. Payload: `{ref, before_sha, after_sha}`.

### Sync operations
- `sync.divergence_detected` — sync controller saw the host and sandbox diverge. Payload: `{ahead_sandbox, ahead_host, merge_base, sandbox_sha, host_local_sha}`. Emitted once per fresh divergence; not on every tick.
- `sync.absorbed` — emitted by `skoga absorb` after a successful FF/reset/merge. Payload: `{strategy, from_sha, to_sha, ref}` with `strategy` one of `ff | prefer-host | prefer-sandbox | merge`.
- `sync.deferred` — soft skip; dev-side state blocked the host-side FF this tick (dirty worktree, missing host worktree, etc.). Payload: `{operation, reason, ref?}`. No backoff, retried on the next normal tick.
- `sync.failed` — hard fault (disk, ACL, missing repo, corruption). Payload: `{operation, error}`. Triggers exponential backoff; the session is promoted to `sync-broken` after the threshold.

### User actions
- `user.start_session` — `skoga start` issued. Payload: `{task, agent, base}`.
- `user.review_opened` — `skoga review` or `skoga show` invoked. Payload: `{session_id, surface}`.
- `user.revise` — `skoga revise` with feedback. Payload: `{feedback}`.
- `user.checkout` — `skoga checkout` invoked.
- `user.land_initiated` — `skoga land` invoked.
- `user.push` — `skoga push` invoked.
- `user.absorb` — `skoga absorb` invoked.
- `user.kill` — `skoga kill` invoked.
- `user.export` — `skoga export` invoked. Payload: `{session_id, format: "patch"|"bundle", output}`.

### System events (no session_id)
- `daemon.started`
- `daemon.stopped`
- `daemon.crashed`
- `daemon.rpc.rejected` — incoming RPC peer's uid didn't match the daemon's. Payload: `{peer_uid, daemon_uid, reason}`. Emitted at accept time before the connection is dropped.
- `doctor.run`
- `doctor.repair`
- `error.*` — system-level errors with categorized subtypes.

## Example session

```ndjson
{"schema_version":1,"ts":"2026-05-19T14:23:45.123Z","session_id":"abc1234","seq":1,"type":"session.created","actor":"user","payload":{"task":"implement signup","agent":"claude-code","base":"main"}}
{"schema_version":1,"ts":"2026-05-19T14:23:45.234Z","session_id":"abc1234","seq":2,"type":"session.started","actor":"skoga","payload":{"worktree":"/Users/skoga-andrew/sessions/abc1234","branch":"skoga/abc1234","base_sha":"e3f8c2a..."}}
{"schema_version":1,"ts":"2026-05-19T14:24:01.456Z","session_id":"abc1234","seq":3,"type":"agent.tool_call","actor":"agent","payload":{"tool":"read","args":{"file":"src/auth/login.rs"}},"correlation_id":"tc-1"}
{"schema_version":1,"ts":"2026-05-19T14:24:01.567Z","session_id":"abc1234","seq":4,"type":"agent.tool_result","actor":"agent","payload":{"tool":"read","result":"ok","bytes":1247},"correlation_id":"tc-1"}
{"schema_version":1,"ts":"2026-05-19T14:24:15.789Z","session_id":"abc1234","seq":5,"type":"agent.tool_call","actor":"agent","payload":{"tool":"write","args":{"file":"src/auth/signup.rs","bytes":2891}}}
{"schema_version":1,"ts":"2026-05-19T14:24:23.012Z","session_id":"abc1234","seq":6,"type":"git.commit","actor":"agent","payload":{"sha":"f2a8c91...","message":"Implement signup endpoint","files":1,"lines_added":89,"lines_removed":0}}
{"schema_version":1,"ts":"2026-05-19T14:30:00.000Z","session_id":"abc1234","seq":24,"type":"git.checkpoint","actor":"skoga","payload":{"sha":"c91f2a8...","files_changed":2}}
{"schema_version":1,"ts":"2026-05-19T14:30:45.123Z","session_id":"abc1234","seq":25,"type":"git.rebase","actor":"skoga","payload":{"onto":"main","before_sha":"f2a8c91...","after_sha":"g3b9d02...","result":"clean"}}
{"schema_version":1,"ts":"2026-05-19T14:35:30.456Z","session_id":"abc1234","seq":38,"type":"agent.summary","actor":"agent","payload":{"goal":"Implement signup","approach":"JWT, reusing /auth conventions","files":3,"tests":"47 passing","open_items":[]}}
{"schema_version":1,"ts":"2026-05-19T14:35:30.567Z","session_id":"abc1234","seq":39,"type":"session.state_changed","actor":"skoga","payload":{"from":"running","to":"waiting-for-review","reason":"agent reported done"}}
{"schema_version":1,"ts":"2026-05-19T14:42:11.789Z","session_id":"abc1234","seq":40,"type":"user.land_initiated","actor":"user","payload":{}}
{"schema_version":1,"ts":"2026-05-19T14:42:12.234Z","session_id":"abc1234","seq":42,"type":"session.landed","actor":"skoga","payload":{"final_sha":"h4c0e13...","branch":"implement-signup-flow","pr_url":"https://github.com/.../pull/47"}}
```

A complete session arc, fully reconstructable from the log.

## Projections

The raw NDJSON is the substrate. Different surfaces project from it:

### TUI activity feed
Human-readable, summarized, time-relative:
```
14:35  agent  wrote 3 files, ran tests (47 passing)
14:33  agent  edited tests/signup_test.rs
14:30  skoga  rebased onto main (clean)
14:24  agent  wrote src/auth/signup.rs
```

The projection layer:
- Combines related events (`tool_call` + `tool_result` → one line).
- Aggregates ("3 file edits in 30s" → "wrote 3 files").
- Hides noisy event types (sync ticks, individual reads).
- Renders timestamps relative.

### `skoga logs <id>`
Closer to raw, with filtering:
```
$ skoga logs abc1234 --since 1h --type git.commit
14:24:23  git.commit  agent  f2a8c91  Implement signup endpoint (+89 -0)
14:30:00  git.checkpoint  skoga  c91f2a8  wip: 2 files changed
14:30:45  git.rebase  skoga  f2a8c91 → g3b9d02  clean
```

`--format json` emits raw NDJSON, no projection.

### Daemon subscriptions
The local API's `events.session(id)` pushes raw events to subscribers (TUI, future IDE plugin). Subscribers project as needed for their context.

## Sensitivity

The audit log will contain potentially sensitive content:
- Agent prompts (may include secrets if the dev pasted them).
- Tool arguments (file paths, occasionally credential-adjacent).
- File diffs are NOT in events (only commit metadata is recorded; the diff lives in git, recoverable from the commit SHA).

For v1, the audit log is purely local — sensitivity is bounded by "what's already on the dev's machine." Document clearly that `~/.skoga/audit/` may contain sensitive data and should not be shared casually. Recommend `.gitignore` entries if the dev's `~` is ever versioned.

For the commercial control plane: each event type will get a sensitivity tag (`public` | `internal` | `sensitive`) so the uploader can filter or redact based on policy. Tag at the schema definition level (not on each event) to keep events compact. **Tag now**, even though v1 doesn't act on the tags, so the schema is forward-compatible.

## Retention

- Active sessions: keep everything.
- Terminal sessions: full retention for N days (default 90), then compress to `.ndjson.zst`, then prune.
- Config knob: `[audit] retention_days = 90`.
- Explicit cleanup: `skoga prune --audit`.

Disk math: a chatty 1-hour session produces ~5MB of events. 100 sessions/year × 5MB = 500MB/year. Compressed: ~50MB/year. Easily tolerable on any modern machine.

## Schema documentation

The schema is documented in two places:
- **Human-readable**: this document, kept current as event types are added.
- **Machine-readable**: a JSON schema embedded in the Skoga binary. Dump via `skoga audit-schema`.

Both must stay in sync; the binary's schema is authoritative when they diverge.

## Decisions captured

- **Tool calls + agent summary, no full transcript** by default. Full transcript is opt-in via `[audit] capture_transcript = true` (v1.5).
- **Metadata only** in tool-call events. File diffs live in git commits, not in events.
- **Skoga assigns correlation IDs**, not the agent.
- **Schema version is per-event** (each line carries `schema_version`), not at file-header level.
- **Sensitivity tagging** is added now as a forward-compatible field on event type definitions, even though v1 doesn't act on it.
