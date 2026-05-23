// Skoga — seed data: agents, tasks, conversations
// Plausible-but-clearly-demo content. Nordic given names with model in tow.

const AGENTS_FULL = [
  {
    id: "bjorn", name: "Björn", role: "backend / svc",
    model: "claude-sonnet-4.7",
    status: "running",
    task: "Add OAuth scope refresh to /auth router so PATs survive a Stripe rotate.",
    repo: "skoga/ledger-svc", branch: "bjorn/auth-scope-refresh",
    progress: 0.72, runtime: "1h 24m", tokens: 184_300, cost: 1.47,
    commits: 6, files: 11, attn: false,
  },
  {
    id: "astrid", name: "Astrid", role: "frontend / web",
    model: "claude-sonnet-4.7",
    status: "blocked",
    task: "Migrate cart drawer to xstate v5 — needs decision on stale-data behaviour.",
    repo: "skoga/monolith-web", branch: "astrid/cart-xstate",
    progress: 0.48, runtime: "42m", tokens: 96_200, cost: 0.81,
    commits: 3, files: 7, attn: true,
    attnMessage: "Quick question on resume semantics — see thread",
  },
  {
    id: "linnea", name: "Linnéa", role: "qa / e2e",
    model: "gpt-5-codex",
    status: "review",
    task: "Backfill Playwright coverage for guest-checkout flow (5 specs).",
    repo: "skoga/monolith-web", branch: "linnea/e2e-guest-checkout",
    progress: 1.0, runtime: "2h 11m", tokens: 218_900, cost: 1.94,
    commits: 9, files: 14, attn: false,
    prUrl: "#",
  },
  {
    id: "magnus", name: "Magnus", role: "devops / ci",
    model: "claude-sonnet-4.7",
    status: "running",
    task: "Stabilise integration test image — pin postgres 16.3 + redis 7.4.",
    repo: "skoga/core-runtime", branch: "magnus/ci-image-pin",
    progress: 0.31, runtime: "18m", tokens: 41_700, cost: 0.39,
    commits: 1, files: 3, attn: false,
  },
  {
    id: "sigrid", name: "Sigrid", role: "refactor",
    model: "claude-sonnet-4.7",
    status: "running",
    task: "Split monolithic ledger reducer into per-domain slices.",
    repo: "skoga/ledger-svc", branch: "sigrid/reducer-slices",
    progress: 0.56, runtime: "2h 49m", tokens: 312_400, cost: 2.71,
    commits: 11, files: 22, attn: false,
  },
  {
    id: "henrik", name: "Henrik", role: "docs",
    model: "gpt-5-mini",
    status: "done",
    task: "Rewrite Dispatch API reference for v2 endpoints + add migration notes.",
    repo: "skoga/docs", branch: "henrik/dispatch-v2-ref",
    progress: 1.0, runtime: "1h 02m", tokens: 84_200, cost: 0.18,
    commits: 4, files: 9, attn: false,
    prUrl: "#",
  },
  {
    id: "ingrid", name: "Ingrid", role: "data / migrate",
    model: "claude-sonnet-4.7",
    status: "blocked",
    task: "Backfill `user.region` from `billing_address.country` (1.2M rows).",
    repo: "skoga/ledger-svc", branch: "ingrid/region-backfill",
    progress: 0.83, runtime: "4h 06m", tokens: 421_900, cost: 3.62,
    commits: 7, files: 5, attn: true,
    attnMessage: "Found 184 rows with no billing address — drop or default?",
  },
  {
    id: "olaf", name: "Olaf", role: "debug",
    model: "claude-sonnet-4.7",
    status: "running",
    task: "Track down worker-pool memory leak — heap +220MB/hr in prod.",
    repo: "skoga/core-runtime", branch: "olaf/worker-leak-trace",
    progress: 0.21, runtime: "33m", tokens: 78_900, cost: 0.69,
    commits: 0, files: 0, attn: false,
  },
  {
    id: "freja", name: "Freja", role: "frontend / ui",
    model: "claude-sonnet-4.7",
    status: "running",
    task: "Wire Stripe customer portal callbacks into settings → billing.",
    repo: "skoga/monolith-web", branch: "freja/stripe-portal",
    progress: 0.64, runtime: "1h 11m", tokens: 142_800, cost: 1.20,
    commits: 4, files: 8, attn: false,
  },
  {
    id: "soren", name: "Sören", role: "security",
    model: "claude-sonnet-4.7",
    status: "review",
    task: "Patch CVE-2025-49814 in deps/marked — bump to 14.2.1 + lockfile audit.",
    repo: "skoga/monolith-web", branch: "soren/cve-marked-bump",
    progress: 1.0, runtime: "26m", tokens: 38_400, cost: 0.32,
    commits: 2, files: 4, attn: false,
    prUrl: "#",
  },
  {
    id: "elin", name: "Elin", role: "api / contracts",
    model: "gpt-5-codex",
    status: "running",
    task: "Generate TS clients for /v2/billing/* and replace handwritten wrappers.",
    repo: "skoga/pkg-clients", branch: "elin/v2-billing-gen",
    progress: 0.44, runtime: "57m", tokens: 110_400, cost: 0.96,
    commits: 2, files: 18, attn: false,
  },
  {
    id: "knut", name: "Knut", role: "perf",
    model: "claude-sonnet-4.7",
    status: "idle",
    task: "Idle — last finished: index dashboard query, saved 412ms p95.",
    repo: "skoga/ledger-svc", branch: "knut/dashboard-index",
    progress: 1.0, runtime: "—", tokens: 0, cost: 0,
    commits: 0, files: 0, attn: false,
  },
  {
    id: "thora", name: "Thora", role: "infra",
    model: "claude-sonnet-4.7",
    status: "running",
    task: "Terraform: split staging VPC into per-service subnets.",
    repo: "skoga/infra", branch: "thora/vpc-split",
    progress: 0.39, runtime: "1h 48m", tokens: 167_300, cost: 1.41,
    commits: 3, files: 6, attn: false,
  },
  {
    id: "vidar", name: "Vidar", role: "backend / svc",
    model: "claude-sonnet-4.7",
    status: "running",
    task: "Implement `/v2/billing/refunds` with idempotency keys.",
    repo: "skoga/ledger-svc", branch: "vidar/refunds-v2",
    progress: 0.51, runtime: "2h 03m", tokens: 211_600, cost: 1.79,
    commits: 5, files: 9, attn: false,
  },
  {
    id: "saga", name: "Saga", role: "frontend / a11y",
    model: "claude-sonnet-4.7",
    status: "done",
    task: "Audit + fix focus-trap regressions in modals (12 components).",
    repo: "skoga/monolith-web", branch: "saga/focus-trap",
    progress: 1.0, runtime: "3h 17m", tokens: 287_400, cost: 2.51,
    commits: 14, files: 19, attn: false,
    prUrl: "#",
  },
  {
    id: "rune", name: "Rune", role: "search",
    model: "claude-sonnet-4.7",
    status: "running",
    task: "Swap meili → typesense for product index; preserve facet shape.",
    repo: "skoga/search-svc", branch: "rune/typesense-swap",
    progress: 0.28, runtime: "1h 32m", tokens: 152_900, cost: 1.31,
    commits: 2, files: 7, attn: false,
  },
  {
    id: "halla", name: "Halla", role: "data / etl",
    model: "claude-sonnet-4.7",
    status: "running",
    task: "Hook usage events into warehouse — replace nightly batch with stream.",
    repo: "skoga/etl", branch: "halla/usage-stream",
    progress: 0.62, runtime: "2h 24m", tokens: 198_200, cost: 1.67,
    commits: 6, files: 11, attn: false,
  },
  {
    id: "torsten", name: "Torsten", role: "backend / api",
    model: "gpt-5-codex",
    status: "running",
    task: "Pagination v3 — switch to keyset on /transactions and /events.",
    repo: "skoga/ledger-svc", branch: "torsten/keyset-pagination",
    progress: 0.74, runtime: "1h 19m", tokens: 134_100, cost: 1.18,
    commits: 5, files: 12, attn: false,
  },
  {
    id: "embla", name: "Embla", role: "qa / load",
    model: "claude-sonnet-4.7",
    status: "review",
    task: "k6 scenario for refund storm; baseline + 5× spike + recovery.",
    repo: "skoga/core-runtime", branch: "embla/k6-refund-storm",
    progress: 1.0, runtime: "44m", tokens: 62_300, cost: 0.54,
    commits: 3, files: 4, attn: false,
    prUrl: "#",
  },
  {
    id: "leif", name: "Leif", role: "release",
    model: "claude-sonnet-4.7",
    status: "idle",
    task: "Idle — last finished: cut 2026.05.21 release, rolled out canary.",
    repo: "skoga/infra", branch: "leif/release-2026-05-21",
    progress: 1.0, runtime: "—", tokens: 0, cost: 0,
    commits: 0, files: 0, attn: false,
  },
];

// ── Astrid's conversation (the blocked one — most interesting demo) ──
const ASTRID_CONVERSATION = [
  {
    kind: "msg", from: "you", initial: "M", name: "you",
    when: "Mon · 2:14p",
    text: [
      "Migrate the cart drawer to xstate v5. Pull the state machine out of the reducer into a separate file. Keep the public hook shape the same so we don't have to touch consumers.",
    ],
  },
  {
    kind: "msg", from: "astrid",
    when: "Mon · 2:14p",
    text: [
      "Got it. I'll work in `skoga/monolith-web` on `astrid/cart-xstate`. Starting by sketching the machine.",
    ],
    runtimeLabel: "claude-sonnet-4.7",
  },
  {
    kind: "tool", tool: "read", path: "app/(shop)/cart/useCart.ts", lines: "1–214",
  },
  {
    kind: "tool", tool: "read", path: "app/(shop)/cart/cartReducer.ts", lines: "1–186",
  },
  {
    kind: "tool", tool: "shell", cmd: "rg -nF 'useCart(' --type=tsx", result: "47 matches across 31 files",
  },
  {
    kind: "msg", from: "astrid",
    when: "Mon · 2:21p",
    text: [
      "Reducer has 6 states (`idle`, `opening`, `open`, `updating`, `checking_out`, `closing`). I'll mirror them in xstate and keep the action names so logs stay readable. New file: `cart.machine.ts`.",
    ],
  },
  {
    kind: "write", path: "app/(shop)/cart/cart.machine.ts", adds: 142, rems: 0,
  },
  {
    kind: "write", path: "app/(shop)/cart/useCart.ts", adds: 38, rems: 71,
  },
  {
    kind: "tool", tool: "shell", cmd: "pnpm -w test cart", result: "3 failed · 22 passed · 1 skipped",
  },
  {
    kind: "msg", from: "astrid",
    when: "Mon · 2:38p",
    text: [
      "3 failing — all related to **resume semantics** when the drawer reopens with stale data. Reducer used to silently re-fetch, but xstate v5 invokers won't auto-cancel a pending fetch on `closing`. I see three options and want to confirm before picking:",
    ],
  },
  {
    kind: "question",
    label: "Decision needed — resume semantics",
    body: [
      "When the user closes the drawer mid-fetch and reopens 8s later:",
      "  ① Cancel + refetch on reopen (matches reducer; 1 extra request)",
      "  ② Let the original fetch resolve, ignore on reopen (cheapest)",
      "  ③ Cache for 30s, reuse if fresh, else cancel + refetch",
    ],
    opts: ["① Cancel + refetch", "② Let it resolve", "③ 30s cache", "Tell me more"],
  },
];

// ── Björn's conversation (the productive long-runner) ──
const BJORN_CONVERSATION = [
  {
    kind: "msg", from: "you", initial: "M", name: "you",
    when: "Mon · 12:50p",
    text: [
      "When we rotate the Stripe secret, PATs created against the old scope die. Add a `refresh` step that re-issues them transparently.",
    ],
  },
  {
    kind: "msg", from: "bjorn",
    when: "Mon · 12:50p",
    text: ["On it. Will work in `skoga/ledger-svc`."],
    runtimeLabel: "claude-sonnet-4.7",
  },
  {
    kind: "tool", tool: "read", path: "auth/router.ts", lines: "1–340",
  },
  {
    kind: "tool", tool: "read", path: "auth/scope.ts", lines: "1–94",
  },
  {
    kind: "write", path: "auth/scope.ts", adds: 64, rems: 18,
  },
  {
    kind: "write", path: "auth/router.ts", adds: 22, rems: 9,
  },
  {
    kind: "msg", from: "bjorn",
    when: "Mon · 1:34p",
    text: [
      "Added a `RefreshableScope` wrapper. On 401 from Stripe it transparently re-issues against the current secret and retries the request once. Wrote 11 tests covering rotate-mid-flight + repeated 401s. All green.",
    ],
  },
  {
    kind: "tool", tool: "shell", cmd: "pnpm -w test auth", result: "57 passed · 0 failed",
  },
  {
    kind: "msg", from: "bjorn",
    when: "Mon · 2:08p",
    text: [
      "One more thing — there was a stale TODO in `scope.ts` about caching scope tokens for 60s. The new flow makes that cache unnecessary (and slightly wrong, since rotates would invalidate it). Removed it. Diff is 8 lines, no behaviour change in the happy path.",
      "I'll open the PR if you don't object."
    ],
  },
];

const CONVERSATIONS = {
  astrid: ASTRID_CONVERSATION,
  bjorn: BJORN_CONVERSATION,
};

// ── Activity sparkline (last 30 ticks, agent-pulse style) ──
const ACTIVITY = [
  0.18, 0.22, 0.31, 0.24, 0.40, 0.55, 0.62, 0.48, 0.36, 0.42,
  0.58, 0.71, 0.83, 0.66, 0.51, 0.44, 0.58, 0.72, 0.81, 0.94,
  0.78, 0.62, 0.55, 0.68, 0.74, 0.59, 0.46, 0.52, 0.61, 0.55,
];

// Timeline for the conv right panel (Astrid)
const ASTRID_TIMELINE = [
  { kind: "thought", when: "now",      what: "Waiting on resume-semantics decision." },
  { kind: "tool",    when: "2:36p",    what: <>Ran <code>pnpm -w test cart</code> — 3 failed, 22 passed.</> },
  { kind: "commit",  when: "2:34p",    what: <>Commit <code>4f12a9d</code> — useCart consumes xstate hook.</> },
  { kind: "commit",  when: "2:29p",    what: <>Commit <code>0a18c2b</code> — cart.machine.ts: full state shape.</> },
  { kind: "tool",    when: "2:18p",    what: <>Read <code>cartReducer.ts</code> · <code>useCart.ts</code></> },
  { kind: "thought", when: "2:14p",    what: "Plan: mirror reducer states, keep action names." },
  { kind: "commit",  when: "2:14p",    what: <>Branched from <code>main</code> · <code>a91f3d2</code>.</> },
];

Object.assign(window, {
  AGENTS_FULL, CONVERSATIONS, ACTIVITY, ASTRID_TIMELINE,
});
