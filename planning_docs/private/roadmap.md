# Skoga: Product Roadmap & Strategic Context

> A reference document for agents and collaborators working on Skoga. This document captures the worldview, product strategy, packaging, architecture, design principles, and phased build plan. When making product or implementation decisions, default to what aligns with this document. When in doubt, ask.

---

## 1. The Worldview

Software engineering is shifting from an IC discipline to a management discipline. Engineers increasingly do less typing of code themselves and more dispatching, supervising, reviewing, and coaching AI coding agents that do the typing. Over the next 1-3 years, this shift will go from "a few power users" to "how most professional software is built."

The tools engineers use today are still optimized for the old model — solo humans writing code linearly in an editor. They have not caught up to the new reality, where the same engineer might have 3-10 agents working in parallel across multiple branches and codebases.

**Skoga exists to be the tool for that new reality.** The tagline is: **Run your agents like a team.**

## 2. The Product Thesis

Three principles drive every design decision:

**Engineers are becoming managers of agents.** Skoga's metaphor is the management cockpit, not the editor. A good manager doesn't sit and watch their reports type. They dispatch work, check in when needed, unblock the stuck, and review what's shipped. Skoga's UI, terminology, and workflows should reinforce this metaphor everywhere.

**Skoga slots between the editor and GitHub; it doesn't replace either.** GitHub already won code review. Editors are still useful as microscopes when an agent gets stuck. Skoga is the missing middle layer: dispatch and supervision. Three surfaces, each doing what it's best at, no overlap.

**Agents should follow your existing engineering process, not get a parallel one.** Code changes go through PRs. Data changes go through reviewed migrations. Production access is brokered. Skoga's job is not to invent new safety systems for agents — it's to route agents through the safety systems that already exist for humans, that the team already trusts.

## 3. The Two Audiences

Skoga serves two distinct populations with overlapping needs. The product itself is the same; the entry points, framing, and marketing surfaces differ.

**Senior engineers running agent teams.** These are the early adopters who already feel the chaos of managing multiple agents. They have an existing engineering mental model (Git, PRs, branching, review) and are adding agent management on top. They find Skoga through the OSS project, conference talks, and technical communities. They convert because Skoga is a better workflow than what they were cobbling together.

**Vibe coders.** People shipping real products via Cursor, Claude Code, Bolt, Lovable, and similar tools without traditional engineering backgrounds. They have product instincts and willingness to ship; they don't yet have the full engineering scaffolding. They find Skoga through Twitter, YouTube, TikTok, and community recommendations. They convert because Skoga gives them the engineering process they didn't know they needed — routing agents through PRs, surfacing what's about to happen, and gradually teaching the habits that scale.

The vibe coder cohort is doubling roughly every six months as the tools democratize. Over time, some grow into traditional engineers; some plateau as product-minded builders who use agents as their engineering team forever. Both are valuable. Both are durable.

The product should not be marketed explicitly as "for vibe coders" — that's polarizing and dates badly. Instead, Skoga should be designed so both audiences feel it was built for them. Different surfaces (OSS readme vs Mac app onboarding vs Twitter copy) speak to different audiences in different language for the same product.

## 4. The Product Line

Four tiers, each with a structural reason to exist beyond just pricing.

### Tier 0: Skoga OSS / CLI (Free)

The runtime, written in Rust. Tmux-based agent runner with worktree isolation. Supports both lite (sandbox-exec) and hardened (second-user) isolation modes. CLI dispatch and agent management. Installable via Homebrew. Everything needed to run agents safely on one machine, alone.

*Licensing:* Deferred decision (see Section 13). Will likely be Apache 2.0 OSS at publish time, but kept private during early development to preserve options.

*Purpose:* Credibility, adoption funnel for senior engineers, OSS gravity that's independent of the company, and the runtime that the Mac app consumes.

*Explicitly NOT included:* The cockpit UI, multi-machine coordination, team features, persistent history beyond what tmux gives you, policy enforcement, audit logs. These are structurally features of a managed product.

### Tier 1: Skoga Solo ($24/month, 30-day free trial, free for non-commercial use)

Native Mac app (Swift/SwiftUI, closed source). Cockpit view of all agents running on your machine. Configuration-free setup.

Features:
- "Needs attention" indicators and surfacing
- Conversation interface with running agents (decision-card UX for blocked agents)
- One-click PR opening to GitHub
- 1Password/vault integration
- Local history with search
- Ephemeral Norse-named agents and user-defined persistent agents
- Lite isolation by default; one-click upgrade to hardened isolation

*Purpose:* On-ramp for individuals (especially vibe coders), revenue tier in its own right, and the funnel that feeds Team.

*Pricing structure:*
- $24/month monthly billing
- $19/month annual billing ($228/year, saves $60, gets upfront cash)
- 30-day free trial with no credit card required to start
- Free forever for personal/non-commercial use (honor system)

*What people are paying for:*
1. Configuration-free setup. No tmux config, no user account setup, no scripts. Install and go.
2. The cockpit UI. Glanceable status, attention indicators, conversation handoff, one-click PRs.
3. Ongoing currency with the agent ecosystem. New Claude Code features, Cursor CLI changes, MCP evolution — Skoga keeps up so the user doesn't have to.

### Tier 2: Skoga Team ($49 per seat per month)

The bulk of revenue. Aimed at startups (5-30 engineers) and engineering teams within larger companies running agents on shared codebases. Everything in Team is structurally a "more than one human" feature.

Includes everything in Solo, plus:
- **Shared visibility across the team's agents.** See what every team member's agents are doing.
- **Cross-developer coordination to avoid collisions.** Warn when two developers' agents touch overlapping code.
- **Pooled API cost visibility and budgets.** Team-level spend tracking, per-person and per-project, with budget enforcement.
- **Per-repo policies that apply to the whole team.** Lead engineer or admin sets policies that bind all team agents.
- **Audit log that survives any individual.** Organizational memory of what agents did, when, and what was reviewed.
- **Team-shared persistent agents.** Shared agents that everyone can dispatch to — codifies team conventions into reusable team primitives.
- **Centralized credential management.** Team vault with admin control over which agents can access which credentials.
- **Integration with team workflow tools.** Slack, Linear, GitHub, Jira — agent activity flows into team channels and tickets.
- **Onboarding and offboarding workflows.** Manage roster, credentials, dispatch privileges; preserve agent history after departures.
- **Team-level performance analytics.** Aggregate data on which models/agents perform best on what kinds of work.

*Pricing rationale:* Reference points are infrastructure tools (Datadog, Sentry) at $30-80/seat, not consumer dev tools (Linear, Cursor) at $10-20. Skoga is infrastructure the team depends on to ship safely. Anchor at $49/seat with "early customer" lock-in for the first 100 teams.

### Tier 3: Skoga Business ($120 per seat per month, range $100-150)

Aimed at larger orgs (50+ engineers) with compliance and governance needs. Where Team serves engineering teams, Business serves the org. The buyer is a CTO, VP Engineering, or platform/security lead; the buying motion is procurement; the concerns are risk, compliance, governance, and consistency across teams.

Adds:
- **SSO/SAML.** The gating feature — most enterprises won't buy without it.
- **Org-wide policies that override team-level ones.** Security/platform team sets policies that bind all teams.
- **SOC 2 / ISO 27001 / similar compliance reporting.** Often a hard requirement for regulated industries.
- **Long history retention (1-2 years vs Team's 90 days).** For SOX-like audit requirements.
- **Advanced policy engine with conditional rules.** Time-of-day, file-pattern, environment-based rules.
- **Centralized credential broker integration.** Vault, AWS Secrets Manager, Azure Key Vault, Doppler, CyberArk.
- **Detailed cost analytics and chargeback by team/project.** Internal billing support for big organizations.
- **Approval workflows for sensitive agent actions.** Routing to specific approvers with audit logging.
- **Dedicated support channel, response SLA, 99.9% uptime SLA.**
- **Hardened isolation mode required by default for all agents.**

### Tier 4: Skoga Enterprise (Custom, $50K-500K+ ARR per customer)

F500, regulated industries, government, anyone with a 6-month security review. The buyer is paying for predictability, customization, and risk transfer as much as for product capability.

Adds:
- Self-hosted control plane (their VPC or on-prem)
- Custom policy engines and rule integrations
- Bespoke audit/compliance reporting (HIPAA, FedRAMP, etc.)
- Custom integrations with internal tooling
- Named CSM, SLA with teeth, multi-year contracts
- Dedicated implementation support

### Why Enterprise pricing is high

Enterprise prices reflect: (a) value-based pricing — what the customer would pay for a tool that saves them millions in engineering productivity, (b) sales cost amortization — closing F500 deals takes 6-12 months of human effort, (c) customization and operational overhead of self-hosted deployments, (d) contractual risk transfer, (e) procurement signaling — sub-$100K offers don't get taken seriously by enterprise buyers, and (f) the customer paying for vendor stability and predictability as much as for the product itself.

### Things NOT in the product line

Resist building these even when tempting:
- A code editor
- A PR review tool
- An AI model layer or proprietary models
- A marketplace for agents
- A no-code agent builder
- Anything that duplicates what GitHub, the editor, or the model provider already does well

## 5. Pricing Page Framing

Present as three tracks, not a feature matrix:

> **Skoga OSS** — Free. Self-hosted, tmux-based, configure it yourself. For developers who want full control.
>
> **Skoga Solo** — $24/month, free for 30 days. The Mac app cockpit. No configuration, beautiful UI, kept current with the agent ecosystem. For developers who want it to just work.
>
> **Skoga Team** — $49/seat/month. Everything in Solo plus shared visibility, policies, audit logs, and team-wide history. For teams running agents on shared codebases.

OSS isn't a crippled version of Solo, it's a different product for a different person. Both are first-class.

## 6. Isolation Architecture

Skoga has two isolation modes, identical between OSS CLI and Mac app. The difference is configuration friction, not capability.

| Mode | Mechanism | OSS experience | Mac app experience |
|---|---|---|---|
| Lite | `sandbox-exec` profiles | `skoga --lite` flag | Default, automatic |
| Hardened | Second user + worktree isolation | Documented setup | One-click setup with auth prompt |

**Lite mode** uses macOS `sandbox-exec` profiles to restrict spawned agent processes — file system access scoped to the worktree, restricted network egress, no access to system directories or sibling project files. Adequate for the majority of agent work.

**Hardened mode** runs agents under a separate macOS user account, giving OS-level isolation. The Mac app handles `useradd`, sudoers configuration, and file system permission setup automatically on first activation, with a single password prompt and a clear explanation of what's happening. OSS users follow documented manual setup.

The runtime is identical between OSS and Mac app. The Mac app is a great configuration and setup experience for capabilities the OSS runtime already has.

**Default modes:**
- Mac app Solo: lite by default, hardened available as one-click upgrade
- Mac app Team: lite by default; hardened can be required by team policy
- Mac app Business: hardened required by default policy
- OSS: hardened by default; `--lite` available as an escape hatch

**Threat model honesty:** Isolation makes agents safe to walk away from for *sandbox-contained work*. It does NOT make agents safe to ignore when they're doing irreversible real-world actions (prod DB writes, deploys, sending real messages). The UI should communicate which tier of work an agent is doing — green for sandbox, yellow for one-click-cross-boundary, red for "demands attention." A good manager doesn't watch their reports do everything, but they do want to know before someone touches prod.

**Honest marketing language:**

> Skoga runs your agents in isolated worktrees with constrained permissions, so they can do their work without accessing things they shouldn't. For teams with stricter requirements, Skoga can run agents under fully separated user accounts for OS-level isolation.

## 7. Agent Identity Model

Skoga distinguishes between ephemeral agents (one-off tasks) and persistent agents (saved configurations).

**Ephemeral agents (default):**
- Spawned automatically when a task is dispatched without explicit assignment
- Named from a curated pool of ~100-200 hand-picked Norse names (Astrid, Björn, Linnéa, Magnus, etc.)
- Names are recognizably Norse but pronounceable and typeable in English
- No special characters that require keyboard gymnastics
- Names don't repeat within an active session
- Names can repeat across sessions over time
- Dissolve when the task completes

**Persistent agents (user-defined):**
- Created explicitly by the user: name, avatar, optional specialty/role, preferred model, system prompt, tool config, optional default repo
- When a task is dispatched to a persistent agent, Skoga spawns a runtime instance with that configuration
- Persistent agent names are reserved within the user's (or team's) namespace — ephemeral naming will not collide
- Visually distinct from ephemeral agents in the UI
- Track historical performance over time

**Discoverability of persistence:**
- After a successful ephemeral run, a subtle "Save [Astrid] as a permanent agent?" prompt appears once
- If ignored, it disappears and doesn't return; not a modal, not a sticky notification
- Users discover persistent agents organically through use

**Team-shared persistent agents (Team tier):**
- Teams can define shared agents that all members can dispatch to
- Codifies "the way our team does X" into a reusable team primitive
- A real differentiator for Team — creates team-level value that justifies team pricing
- Strong retention signal: a team that has built shared agents has built switching cost

**Model versioning policy:**
- Persistent agents pin to a specific model version by default
- When a new model version is released, user is prompted to upgrade the agent (not auto-upgraded)
- Upgrade is one click but explicit

**Why this matters strategically:**
- Day 1: random Norse agents are fun and novel
- Day 7: user saves their first persistent agent
- Day 30: user has a guild of 3-5 defined agents
- Day 90: the user thinks of these agents as "my team"
- Switching tools means rebuilding the guild from scratch — strong retention

## 8. Design Principles

### Prefer honest signals to confident-looking ones

UI elements should convey information the system actually has, not confidence the system doesn't have. Progress bars, time estimates, and AI-generated confidence scores are tempting because they look impressive in mockups, but they erode user trust when they're consistently wrong.

**Anti-patterns to avoid:**
- Fake percent-complete bars on agent runs (LLM agents don't know how done they are)
- Tight time/cost estimates with no real data to back them
- Confidence-theater UI that looks intelligent but conveys nothing real

**Honest alternatives:**
- *Current-action displays* — "Running test suite," "Editing useCart.ts," "Waiting on input"
- *Activity counters* — commits, files changed, tokens used, time elapsed
- *Heartbeat indicators* — shows the agent is alive and producing output; shifts visual state if quiet for too long
- *Time elapsed vs estimate* — "42m of ~1h 40m est." (honest about expectation without claiming completion %)

### Calibrated estimates only

When showing time/token/cost estimates on Dispatch, only show them when backed by real historical data. For repos with no history, show "first run in this repo, no estimate yet." For repos with history, show calibrated intervals based on actual variance — including when variance is genuinely large.

As Skoga sees more runs across more repos and users, estimates get better. This is a real network effect — data that makes the product visibly better with use.

### Defaults are pedagogy

Skoga teaches the management metaphor through defaults more than through copy. Naming agents (Astrid, Björn) is more effective than explaining ("Skoga treats agents as members of your team!"). The product should be designed so a user who never reads any documentation absorbs the worldview through interaction.

### Meaningful defaults that users can override

The "fun default with override" pattern (Norse names default, custom names possible) is a powerful general principle. Defaults should have personality — generic defaults are forgettable. But users should always be able to override. This balances opinionated identity with user respect.

### Quality compounds

Native Mac patterns, restrained color, generous whitespace, monospace where it counts, serif headings for weight, sans-serif for body. Skoga should look like a tool made by craftspeople, not a venture-backed startup. The aesthetic is part of the differentiation against the dark-mode-with-purple-gradients sameness of AI tools.

## 9. Repository and Technology Architecture

### Multi-repo structure

```
github.com/skoga/
├── skoga-cli/         Rust, eventually Apache 2.0 OSS (currently private)
│   ├── src/
│   ├── docs/protocol.md   (the IPC contract, owned here)
│   └── LICENSE (added at OSS publish time)
├── skoga-mac/         Swift/SwiftUI, closed source
│   ├── SkogaApp.xcodeproj/
│   ├── resources/skoga-cli (bundled binary, vendored from skoga-cli releases)
│   └── (private repo, no public LICENSE)
└── skoga-docs/        Public docs, marketing site, blog (skoga.dev)
```

### Architectural principles

**CLI is a real product, not just an internal dependency.** The Mac app invokes the CLI binary as a subprocess, the same way a developer typing commands would. The CLI's protocol is its public API.

**Mac app bundles a known CLI version.** Each Mac app release bundles a specific tested CLI binary in `resources/`. Power users can optionally point the app at their system-installed CLI for development, but the default is the bundled version for reliability.

**CLI runs as a long-lived daemon when invoked by the Mac app.** Communication via local Unix socket using JSON-RPC. Bidirectional, structured messages, supports multiple Mac app windows talking to one daemon. Generalizes naturally to remote control plane communication later (Team tier hosted version uses the same protocol over WebSocket).

**The protocol is documented and treated as public API.** Lives in `skoga-cli/docs/protocol.md`. Breaking changes require a major version bump. The Mac app consumes the protocol the same way any third-party client would — no secret internal APIs.

**The OSS runtime emits structured events from day one.** Agent status, attention requests, errors, completions, costs — all machine-readable. The Mac app and the Team control plane consume the same event protocol.

**Build native, not Electron.** Swift/SwiftUI. Menu bar presence. Native keyboard shortcuts. Spotlight-style command palette. System notifications that respect Focus Modes. Proper macOS appearance API support. Custom scrollbars, custom window chrome, and custom font rendering are forbidden — use what Apple ships.

**Direct download distribution first, App Store later.** Direct distribution via Sparkle auto-updates gives faster iteration, no review process, and direct customer relationships. App Store is a deliberate Phase 3 second channel. The App Store version may be a sandboxed subset of the direct version (e.g., lite-only) — this is a known pattern users understand.

**Cross-platform clients are explicitly deferred.** Linux and Windows users are pointed at Skoga OSS CLI + tmux. A web client only gets prioritized when paying Team customers ask for it more than three times in a month, or after 50-100 Team customers have validated the tier.

**The control plane is separable from the client.** Hosted SaaS by default, self-hosted option for Enterprise. Clients (Mac app today, web app eventually) connect to the same control plane API.

### Code hygiene

**Treat the Mac app private repo as if it could become public someday.**
- No hardcoded API keys, signing certificates, or other secrets
- Use environment variables and a proper secrets manager
- Clean commit messages
- Meaningful PR descriptions
- Costs almost nothing now; preserves the option to go source-available later

**Track third-party code provenance.** If you copy code from Stack Overflow or another OSS project, note the source and confirm license compatibility.

**Don't accept code from anyone without a CLA in place.** Even informally. This preserves the option to relicense later. CLA Assistant (clabot.dev) handles the workflow automatically.

**Aggressive integration testing on the CLI.** Use Rust's testing ecosystem (`cargo test`, `insta` for snapshot tests) to pin the CLI's behavior. Every Mac app feature that depends on a specific CLI behavior should have a corresponding test in the CLI repo. Pays off enormously when iterating on the Mac app.

### Billing infrastructure

Use Paddle or Lemon Squeezy for subscription billing — both handle international tax compliance, which Stripe doesn't out of the box. Important for a global developer audience.

## 10. The Phased Build Plan

The phases are sequential in launches but overlapping in development.

### Phase 1: Skoga CLI (now → ~3-6 months)

**Goal:** A polished, reliable Rust CLI that does the runtime work cleanly. Eventually 200-500 power users who genuinely love it (if/when published as OSS).

**Build:**
- Rust-based runtime with worktree isolation
- Both lite (sandbox-exec) and hardened (second-user) isolation modes
- CLI dispatch and basic agent management
- Structured JSON-RPC event protocol over Unix socket
- Daemon mode for Mac app integration
- Plugin/integration boundaries for future tiers
- Comprehensive integration tests
- Documentation including protocol spec

**In parallel:**
- Worldview blog posts at skoga.dev (essay version of "Run your agents like a team")
- Mac app design sketches and Swift project skeleton
- Lock in architectural decisions for Solo and Team
- Trademark filing for "Skoga"
- Reserve GitHub org and empty repo names (skoga-cli, skoga-mac, skoga-docs)

**Trap to avoid:** Staying in Phase 1 too long. Once the CLI is solid enough that the Mac app can build against it, start the Mac app even if the CLI still has rough edges.

### Phase 2: Skoga Solo (months 3-9)

**Goal:** Vibe coders and individual developers fall in love. Skoga becomes a "thing" outside the OSS-power-user bubble. Real subscription revenue ($24/month per user) starts flowing.

**Build:**
- Native Mac app cockpit (Swift/SwiftUI, closed source)
- Bundled CLI binary, JSON-RPC integration
- Lite isolation by default; one-click hardened mode upgrade
- "Needs attention" detection and surfacing
- Conversation interface with running agents (with decision-card UX pattern for blocked agents)
- One-click PR opening to GitHub
- 1Password/vault integration
- Local history with search
- Ephemeral Norse-named agents (curated pool)
- Persistent user-defined agents
- "Save as permanent agent?" discoverability prompt
- 30-day free trial flow with no credit card required
- Subscription billing infrastructure (Paddle or Lemon Squeezy)
- Direct download distribution via Sparkle auto-updates

**First-run experience is critical.** The first 10 minutes after install should result in a running agent and the cockpit working. Trial-to-paid conversion is determined by first-week usage, not email cadence.

**In parallel:**
- Start designing Team based on what Solo users are doing
- Deliberately recruit a few vibe coders into the early user pool, separately from CLI senior engineers
- Talk to engineering leaders at teams where multiple Solo users have organically appeared
- Decide on hosted control plane architecture
- Basic TOS and Privacy Policy (template-based is fine for Solo)
- Make CLI OSS decision and publish if going that direction

**Trap to avoid:** Skipping Solo and going straight to Team. Without Solo as a beloved individual product, Team has no organic adoption mechanism. Also: don't treat Solo as marketing — it's a real product and a real revenue line.

### Phase 3: Skoga Team (months 9-18)

**Goal:** First $1-2M ARR run rate from Team. 200-300 paying teams.

**Build:**
- Hosted control plane for shared team state
- Shared visibility into all agents across the team
- Cross-developer coordination warnings
- Per-repo policies and policy enforcement
- Audit log
- Pooled API cost tracking with budgets
- Team-shared persistent agents
- Centralized team credential management
- Slack / Linear / GitHub / Jira integrations
- Onboarding/offboarding workflows
- Billing, seat management, admin features
- Optional hardened isolation enforcement at team policy level
- DPA template, real Privacy Policy with GDPR awareness, security page
- Begin SOC 2 readiness work
- Get a startup-friendly lawyer involved for legal review

**In parallel:**
- Catalog what enterprise inbound is asking for, but don't chase it yet
- Consider App Store as a second distribution channel for Solo
- Read each integrated agent tool's TOS carefully

**Trap to avoid:** Overbuilding before launch. Ship the narrowest viable Team product — shared visibility + per-repo policies + audit log is probably enough for v1.

### Phase 4: Skoga Business (months 18-24+)

**Goal:** $3-5M total ARR.

**Build:**
- SSO/SAML
- Advanced policy engine with conditional rules
- SOC 2 Type II audit completed
- Long history retention
- Credential broker integrations (Vault, AWS Secrets Manager, etc.)
- Chargeback analytics
- Approval workflows
- Hardened isolation required by default
- Security questionnaire answers prepared
- Consider going source-available for Mac app to satisfy enterprise security review

**Trap to avoid:** Starting this work before Team is solid.

### Phase 5: Enterprise (24-36+ months)

Custom deals, self-hosted control plane, regulated industries. Sold by humans, not self-serve. $50K-500K+ ARR per customer.

## 11. Revenue Math (Aspirational, 18-24 months)

- 2,000 Solo subscribers × $24/month = $48K MRR ($576K ARR)
- 500 Team customers × 8 seats × $50/seat = $200K MRR ($2.4M ARR)
- 30 Business customers × 30 seats × $120/seat = $108K MRR ($1.3M ARR)
- 5 Enterprise × $150K ARR = $750K ARR

**Total: ~$5M ARR**

Solo is ~13% of revenue but does three other jobs: widens the top of the funnel, generates revenue much earlier than Team would (Solo can pay from month 6, Team from month 12+), and validates pricing at smaller scale before Team commits.

## 12. Legal and Compliance Timeline

**Phase 1 (CLI):** Nothing required. If publishing OSS, ship a LICENSE file. CLA from day one if accepting contributions.

**Phase 2 (Solo launch):** Basic ToS, Privacy Policy, DMCA contact info. Template-based is fine. Total cost: ~$500 if you want a lawyer to glance at it.

**Phase 3 (Team launch):** DPA template, real Privacy Policy with GDPR awareness, security page describing your practices, basic SOC 2 readiness work begins. Total cost: a few thousand dollars in legal review. Get a real lawyer involved here.

**Phase 4 (Business / first F500):** SOC 2 Type I audit completed, working on Type II. Security questionnaire answers prepared. DPAs ready to negotiate. Total cost: $20-50K plus significant founder time.

**Key principles throughout:**
- Compute attribution is clean: agents run with user's credentials, charged to user's account
- Defer to existing access controls (GitHub permissions, SSO group memberships) rather than recreating them
- Audit log everything from day one
- "If Cursor is fine, I'm fine" gets the base architecture right but understates ongoing compliance work needed at each tier

## 13. Deferred Decisions

These are decisions consciously postponed, with notes on what would prompt revisiting.

### Licensing of the CLI and Mac app

*Current state:* CLI is private during development. Mac app is closed source.
*Options:* Pure OSS (Apache/MIT), source-available (BSL, FSL), source-available for security review only, fully closed.
*Most likely outcome:* CLI as Apache 2.0 OSS at publish time. Mac app closed source through Phase 3, possibly source-available in Phase 4 for enterprise trust.
*Revisit when:* Ready to publish the CLI repo publicly; Business buyers start asking about source availability for Mac app.
*Operational prep:* Keep both repos as if they could go public — clean code, CLA from day one, no embedded secrets, trademark filed separately.

### Multi-human collaboration on a single agent conversation

*Status:* In the parking lot.
*Why deferred:* High engineering complexity (concurrent control, conflict resolution), medium revenue impact, better designed after observing real team usage patterns. Base Team value prop doesn't depend on it.
*Revisit when:* 30%+ of Team customers ask for it unprompted, OR Business prospects say they'd buy if you had it, OR you've watched 20+ teams use Team for 6+ months, OR engineering capacity allows a focused 2-3 month effort.

### Cross-platform clients (Linux, Windows)

*Status:* Deferred indefinitely.
*Why:* Mac-first lets you serve early adopters precisely. Linux power users are served by the OSS CLI + tmux.
*Revisit when:* Paying Team customers ask for it more than three times in a month, OR 50-100 Team customers have validated the Mac-only Team tier.

### Web client

*Status:* Deferred to Phase 4+.
*Why:* Same as cross-platform — Mac app is enough for early customers.
*Revisit when:* Same conditions as cross-platform clients, OR Team customers with mixed-platform engineers explicitly request it.

### App Store distribution

*Status:* Deferred to Phase 3.
*Why:* Direct download gives faster iteration and better margins. App Store discoverability matters more as audience expands beyond early adopters.
*Revisit when:* Solo is stable enough that App Store review delays aren't crippling, AND vibe coder audience is meaningfully present.

### Usage-based pricing

*Status:* Not in v1.
*Why:* Per-seat pricing is predictable for finance teams and doesn't create perverse incentives.
*Revisit when:* Considering a cloud-hosted version where Skoga runs agents on the customer's behalf (real compute cost to recoup).

### Conference talks at major venues

*Status:* Deferred to 2027 for big stages.
*Why:* Product needs more shipping and the talk needs more reps. Big-stage talks reward arriving ready.
*Revisit when:* Solo has been in real use for 3-6 months and the worldview essay has been published and tested. Start with meetups and smaller venues (AGNTCon is a good first target if open).

## 14. Cross-Cutting Things to Get Right From the Start

**OSS is the funnel forever, not just at the start.** Weekly bug fixes, regular releases, engaged community — permanent line item.

**Pricing and packaging are decided before Solo launches.** The $24/month Solo subscription with 30-day trial and free-for-personal-use needs to be communicated from day one.

**Customer conversations are the primary product input.** Talk to 5-10 users every week. Include both senior engineers AND vibe coders.

**Worldview-staking content is ongoing.** skoga.dev/writing as the home of the worldview. One substantive essay every 3-4 weeks beats high cadence. Quality compounds; volume doesn't. First essay: "Run your agents like a team."

**Resist the cross-platform pull.** Stay disciplined until paying customers force the conversation.

**Trial UX is product UX, not marketing UX.** Light reminders at day 27 and day 30; nothing in between.

**Stay close to the model providers.** Anthropic, OpenAI, and whoever else is shipping frontier coding models are effectively suppliers. Understanding their roadmaps and being early to support new features is a competitive advantage.

**Watch for the next shift, even while building for the current one.** The engineer-as-manager framing is right for 2026-2028. Build the mental habit of asking "what would change my mind about this?" so the next shift isn't a surprise.

**The shovel-seller framing has a trap.** Selling shovels in an AI gold rush is a great place to be commercially, but shovels need to keep adapting as mining techniques change. The companies that win the AI tooling wave will be the ones that read shifts in agent technology fastest and reshape their tools accordingly.

## 15. Decision Heuristics for Agents Working on Skoga

When in doubt about a design or implementation choice, ask these in order:

1. **Does this reinforce the management metaphor?** If it makes Skoga feel more like an editor or an IDE, push back.
2. **Does this duplicate something GitHub or the editor already does well?** If yes, don't build it; integrate instead.
3. **Does this assume agents need parallel safety systems, or does it route them through existing ones?** Prefer the latter.
4. **Is this a structural feature of a tier, or just a price-fence?** If it's just a price-fence, reconsider the packaging.
5. **Does this work for both a senior engineer AND a vibe coder?** If it requires engineering background to use, find a way to make it discoverable for those without.
6. **Does this work for a single solo developer AND scale to a team?** The architecture should support both without rework.
7. **Does this maintain isolation-mode parity between OSS and the Mac app?** The runtime should be identical; only the configuration experience differs.
8. **Is this an honest signal or a confidence-theater signal?** Prefer honest. No fake progress bars, no uncalibrated estimates, no AI-confidence-scores that aren't real.
9. **Would a discerning Mac user notice and approve of how this feels?** Quality compounds; mediocrity also compounds.
10. **Does this earn the right to be in v1, or can it wait?** Most things can wait. Ship narrow, iterate from real usage.
11. **Does this respect the CLI as a real product with a public protocol?** The Mac app should consume the CLI like any other client; no secret internal APIs.
12. **For Mac app code: would this be embarrassing if the repo went public someday?** Maintain code hygiene as if it could.

## 16. What Success Looks Like

**Year 1:** Skoga CLI is solid and (likely) published as OSS with 200-500 active power users. Skoga Solo Mac app is in active use by individual developers and vibe coders, with a few hundred paying subscribers. The worldview ("run your agents like a team") is associated with Skoga's name in technical communities via skoga.dev essays. First few Team customers in beta.

**Year 2:** Skoga Team has 200-300 paying customers and $1-2M ARR. Skoga Solo is the recommended starting point for any developer working with multiple agents. Solo subscribers in the thousands. Enterprise inbound is real but not yet prioritized.

**Year 3:** Skoga Business is live with 30+ customers. Total ARR $3-5M. Skoga is the obvious answer to "where do I run my agents?" in the same way Linear is the obvious answer to "where does my team track work?"

If those milestones land, the strategic fork (bootstrap vs venture-scale) becomes an explicit choice. Until then, the work is the same either way: build the CLI, build the Mac app, build Team, validate every step with real users.

---

*Last updated: May 2026. Treat this document as a living strategic reference, not a fixed spec. Update it as the worldview sharpens, the product validates, and the market responds.*
