# Daemon ticket draft — dispatch-time file attachments

**Where to file:** `getskoga/skoga` (the daemon + CLI repo).
**Companion to:** `getskoga/skoga-mac` PR for "Attach files at dispatch."

---

## Title

`session.create`: accept attachments so dispatch-time files land before the agent boots

## Summary

The Mac app now lets users attach files at dispatch. Today it's implemented client-side: small text files get inlined into `initial_prompt`, and binary / large files are copied into `<worktree>/.skoga/attachments/` by the Mac after `session.create` returns. This works but has a real race against `_dispatch_launch`, requires every client to re-implement path sanitization, and locks the feature to the Mac surface.

This ticket proposes moving attachments into the daemon so files are guaranteed on disk before the agent process starts and every client (Mac, CLI, future web) gets the same primitive.

## Why the client-side approach is fragile

1. **Race against agent boot.** `session.create` returns after skogad persists the row and spawns `skoga _dispatch_launch`. The Mac then copies attachments. `_dispatch_launch` is already racing — for a multi-MB binary on a slow disk, claude may issue its first `Read` against an absent path.
2. **Repeated sanitization.** Each client has to defend against `..` traversal, symlinked attachment dirs, control characters in filenames, and TOCTOU swaps. The Mac does this now; the CLI / web would have to redo it.
3. **No CLI story.** `skoga start` has no attachment UX today. We'd want one if the feature lands long-term.
4. **No server-side size cap.** Today the client decides whether a file fits; a hostile or buggy client could fill the worktree.

## Proposed daemon contract

### Option A (preferred): inline attachments on `session.create`

Extend `SessionCreateParams`:

```rust
pub struct SessionCreateParams {
    // … existing fields …
    /// Files to drop into the new worktree's `.skoga/attachments/` dir
    /// before the agent process is spawned. Names are sanitized; payloads
    /// are base64. Each file is written before `_dispatch_launch` runs,
    /// so the agent's first `Read` always sees them on disk.
    #[serde(default)]
    pub attachments: Vec<Attachment>,
}

pub struct Attachment {
    /// Display name. `/`, `..`, `.`, NUL, and ASCII control chars are
    /// rejected with -32602. Collisions are resolved with a `(2)`,
    /// `(3)`, … suffix; the original name + the on-disk name are echoed
    /// back in the response so the caller can splice the right path
    /// into `initial_prompt` text it builds.
    pub name: String,
    /// Raw bytes, base64-encoded. Capped at `SKOGA_MAX_ATTACHMENT_BYTES`
    /// (default 10 MiB per file, 50 MiB per dispatch).
    pub bytes_b64: String,
    /// Optional SHA-256 of the raw bytes; daemon verifies and rejects
    /// with -32602 on mismatch. Lets a multi-step client (chunked
    /// upload future-proof) detect corruption.
    pub sha256: Option<String>,
}
```

Response gains `attached: Vec<{ original_name: String, written_path: String }>` for caller introspection (e.g. toasts, audit display) — **but the caller does not need to splice these into the prompt itself.** See "Prompt augmentation" below.

### Prompt augmentation (daemon-owned)

Before forking `_dispatch_launch`, the daemon appends a short section to `initial_prompt` describing the attachments:

```
Attached files (in .skoga/attachments/):
- foo.png
- spec.pdf
```

This keeps clients out of the business of predicting the daemon's sanitization / collision-resolution output (otherwise the Mac would have to duplicate the rules and still get the wrong path on every collision). When `initial_prompt` is `null` and `attachments` is non-empty, the daemon uses the file list as the entire prompt.

Pros:
- Atomic with session creation. No race, no follow-up RPC.
- Daemon owns sanitization once, every client benefits.
- Server enforces size caps.

Cons:
- Bigger `session.create` payloads. For 10 MiB total this is fine over the unix socket; for larger files we'd want Option B.

### Option B: separate `session.attach_file` RPC

```
session.attach_file { id, name, bytes_b64, sha256? }
  → { written_path }
```

Called *after* `session.create` but *before* the daemon spawns `_dispatch_launch`. This requires a new "created but not launched" state, or a `auto_launch: false` + `session.launch` split.

Pros:
- Streams large files without inflating one request.
- Same sanitization centralization.

Cons:
- More moving parts; needs a new lifecycle state.

**Recommendation: ship Option A first** (most dispatches will be a handful of small-to-medium files), and add Option B later if anyone hits the size cap.

## Daemon-side requirements

- Write each attachment to `<worktree>/.skoga/attachments/<sanitized-name>` **before** the `_dispatch_launch` fork. This is what closes the race.
- Reject names containing `/`, `..`, `.`, NUL, or ASCII control chars with `-32602`.
- Refuse to write into `.skoga` or `.skoga/attachments` if either resolves through a symlink.
- After write, assert the resolved path is still rooted at `<worktree>/.skoga/attachments`.
- Cap per-file and per-dispatch byte counts. Configurable, defaults TBD.
- Persist nothing on the session record about the attachments (they're just files in the worktree); audit-emit a `session.attachment_added` event per file for traceability.

## Client migration path

Single coordinated rollout: the daemon PR lands first, then the Mac PR. No graceful-degrade fallback — the Mac requires a daemon that speaks the new field.

The Mac:

1. Sends all non-inlined attachments via `session.create.attachments`.
2. Keeps its local "inline small text into `initial_prompt`" optimization — that doesn't need daemon involvement, and inlining is genuinely useful for context-window-friendly briefs.
3. Does not reference attachment paths in its own prompt copy — the daemon's prompt augmentation owns that.

## Acceptance

- [ ] `session.create` accepts the `attachments` field; older clients omitting it keep working.
- [ ] Files are on disk before `_dispatch_launch` is forked. Unit test: assert ordering via a sleep-injected mock launcher.
- [ ] Daemon appends the "Attached files (in .skoga/attachments/): …" section to `initial_prompt` (or uses it as the entire prompt when the brief is empty).
- [ ] Path-traversal / symlink / control-char tests pass.
- [ ] Per-file and per-dispatch size caps enforced.
- [ ] CLI gains a `--attach <path>` (repeatable) flag on `skoga start`.

## Open questions

- Should the daemon echo the written paths in the response, or require the client to derive them by reapplying the same sanitization? (Echoing is friendlier; deriving is one-fewer-allocation in the hot path.)
- Are there cases where we want to skip the sandbox carveout that `.skoga/attachments/` will need? (Likely no — agent already reads its own worktree freely.)
- Audit-emit per file, or once per dispatch with a count?
