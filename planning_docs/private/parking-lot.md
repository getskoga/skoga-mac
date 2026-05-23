# Skoga: Parking Lot

> Features and ideas that are high-value but consciously deferred. Each entry includes why it's compelling, why we're not building it now, and the specific signal that would prompt revisiting. This list is the counterweight to the roadmap — what we're explicitly NOT building right now, so it doesn't accidentally creep in.

---

## Multi-human collaboration on a single agent conversation

**The idea:** Multiple human teammates can be tagged into an agent's conversation in real-time, contributing input together on what the agent should do. Like Google Docs but for agent supervision. When Astrid gets blocked on a tricky decision, Andrew pulls in Linnéa and Mikael, and the three of them work through it together with Astrid in the room.

**Why it's compelling:**
- It's the moment the management metaphor stops being metaphor and becomes literally true
- Creates serious switching cost for teams (collaborative supervision muscle memory)
- Strong differentiator — nobody else is building this
- Natural endgame for the cockpit positioning

**Why deferred:**
- High engineering complexity (concurrent control, conflict resolution, presence indicators)
- Medium revenue impact in early Team tier
- Legal and security surface area expands significantly (access controls, conversation visibility, audit requirements)
- Better designed after observing real team collaboration patterns
- Team v1 has plenty of value without it

**Revisit signal (any two of):**
- 30%+ of Team customers ask for it unprompted
- Business prospects explicitly say they'd buy if you had it
- 20+ teams have used Team for 6+ months and patterns are visible
- Engineering capacity allows a focused 2-3 month effort without compromising core Team features

**Likely tier when built:** Team (basic), Business (advanced with access control integration)

---

## Cross-platform clients (Linux, Windows native apps)

**The idea:** Native Skoga Mac app equivalents for Linux and Windows users.

**Why it's compelling:**
- Expands addressable market significantly (especially Windows for enterprise)
- Removes friction for cross-platform teams

**Why deferred:**
- Linux power users are well-served by Skoga OSS CLI + tmux
- Windows audience is mostly enterprise; not your early adopter cohort
- Native cross-platform development is expensive and slows core product velocity
- Mac-only is a useful filter for early adopters

**Revisit signal:**
- Paying Team customers ask for it more than 3 times in a month, OR
- 50-100 Team customers have validated the Mac-only tier, OR
- An enterprise prospect says "we'd buy if you supported Windows"

**Likely solution:** Web client first (covers both Linux and Windows in one build), native versions only if explicit demand justifies it.

---

## Web client / cross-platform UI

**The idea:** Browser-based Skoga cockpit that talks to the same control plane as the Mac app.

**Why it's compelling:**
- Covers Linux and Windows in one build
- Better story for cross-platform teams
- Useful for "check status on my phone" use case
- Lower friction for trial adoption (no install)

**Why deferred:**
- Browser UX is harder to make feel as good as native
- Doubles maintenance surface
- Mac app + GitHub mobile already cover most cross-platform needs (status check on phone → GitHub PR view)
- No paying customer demand yet

**Revisit signal:**
- Same as cross-platform clients, OR
- Mobile monitoring becomes a real user request (rare so far)

---

## App Store distribution

**The idea:** Distribute Skoga Solo via the Mac App Store in addition to direct download.

**Why it's compelling:**
- Discoverability — App Store search traffic for "AI agents" / "developer tools"
- Trust signal for users wary of installing apps from websites
- Especially important for vibe coder audience as they grow

**Why deferred (until Phase 3):**
- 15-30% revenue cut to Apple
- App Store review delays shipping cycle (1-7 days unpredictable)
- Sandboxing constraints may force a reduced-feature version
- Owning customer relationship matters early (email, license, refunds)
- Power users prefer direct downloads

**Revisit signal:**
- Solo product is stable enough that review delays aren't crippling, AND
- Audience expansion beyond early adopters is happening (vibe coder cohort meaningfully present)

**Likely approach:** Lite-only App Store version as a second channel; full direct download remains primary.

---

## Usage-based pricing

**The idea:** Charge per agent run, per token, or per compute consumed instead of (or in addition to) per-seat pricing.

**Why it's compelling:**
- Aligns Skoga revenue with customer value extraction
- Captures upside from heavy users who'd otherwise be underpriced
- Could fund a hosted version where Skoga runs agents

**Why deferred:**
- Per-seat pricing is predictable for finance teams
- Usage pricing creates perverse incentives (customers ration usage)
- Pricing simplicity is a feature, not a bug
- Current value prop doesn't require it

**Revisit signal:**
- Building a cloud-hosted version where Skoga runs agents on customer's behalf (real compute cost to recoup), OR
- Clear evidence that current per-seat pricing leaves significant value on the table for power users

---

## AI-powered features beyond agent orchestration

**The idea:** Use AI to do more than orchestrate agents — e.g., auto-summarize agent runs, AI-suggested dispatch templates, AI-generated PR descriptions, AI policy violation detection.

**Why it's compelling:**
- AI tools should themselves use AI well
- Lots of small UX improvements possible
- Differentiation potential

**Why deferred:**
- Risks expanding scope beyond "cockpit for agent management"
- Each AI feature is a maintenance burden as models change
- "Skoga uses AI" is not a value prop; "Skoga manages your AI work" is
- Premature optimization of a tool whose core surface isn't proven yet

**Revisit signal:**
- Specific user behavior shows a specific feature would help (e.g., "users spend 5+ minutes summarizing what an agent did to share with their team")
- The feature can be added without complicating the core UX

---

## A marketplace for agents or agent templates

**The idea:** Users can publish their persistent agents (or templates) for others to use. Discovery and rating system. Possibly revenue sharing.

**Why it's compelling:**
- Network effects
- Reduces user effort to get started
- Possible revenue stream

**Why deferred:**
- Marketplaces are extremely hard to make work
- Distracts from core product
- Quality control becomes a full-time job
- Most successful marketplaces emerged from products that didn't initially try to be marketplaces

**Revisit signal:**
- Strong evidence of organic agent template sharing happening informally (people posting agent configs on Twitter, in Discord, etc.)
- Skoga has the user base to support marketplace dynamics (5,000+ Solo users at minimum)

---

## No-code agent builder

**The idea:** Visual interface for non-developers to build their own agents without writing prompts or configurations.

**Why it's compelling:**
- Could expand audience beyond developers
- Lots of demand for "AI tools for non-developers"

**Why deferred / probably never:**
- Wrong audience for Skoga — non-developers aren't running agents against codebases
- Builds away from core positioning
- Crowded space already (Zapier, n8n, Make, plus 50 AI-specific ones)

**Revisit signal:**
- Likely never. If "AI tools for non-developers" becomes a strategic pivot, it's a different company.

---

## Mobile app

**The idea:** Native iOS/Android Skoga app for monitoring agents on the go.

**Why it's compelling:**
- "My agent finished, let me approve from my phone" is a real use case
- Notifications on mobile feel right
- Andrew (founder) is a runner who'd want this himself

**Why deferred:**
- GitHub mobile already handles the "review PR on the go" case
- Most users prefer to be at a computer when actually engaging with agent work
- Adding mobile is a real ongoing investment for a relatively narrow use case
- Web app would cover much of this need with one build

**Revisit signal:**
- Web client exists and clear mobile-specific usage patterns emerge
- Explicit Team customer demand

---

## Integration with code editors (VS Code, JetBrains, etc.)

**The idea:** Skoga extensions for popular editors that show agent status, allow dispatch from editor.

**Why it's compelling:**
- Meets developers where they are
- Reduces context-switching

**Why deferred:**
- Conflicts with core positioning ("stop living in the editor")
- Maintenance burden of multiple editor extensions
- Editor companies (Cursor, Zed) might bundle similar features themselves
- "View in editor" link from Skoga is enough for most use cases

**Revisit signal:**
- Strong user demand specifically for "I want to see Skoga inside my editor"
- A specific editor company wants to partner

---

## Self-hosted Skoga for non-Enterprise customers

**The idea:** Let any customer self-host the Skoga control plane in their own infrastructure.

**Why it's compelling:**
- Some customers prefer self-hosting on principle
- Removes dependency on Skoga's uptime

**Why deferred:**
- Operational support for self-hosted is expensive
- Better as an Enterprise-tier feature where pricing supports the overhead
- Hosted SaaS works for almost all use cases

**Revisit signal:**
- Strong Business-tier demand specifically for self-hosting (not just Enterprise)
- Operational tooling matures enough that self-hosted support isn't a major cost

---

## How to use this document

When you're tempted to build something not on the roadmap, check here first. If it's here:
- The "why deferred" reminds you of the reasoning
- The "revisit signal" tells you whether the conditions have actually changed

If it's not here but feels like it should be:
- Add it. Capture the idea, why it's compelling, why now isn't the time, what would change that.
- Better to write it down and not build it than to forget it and quietly start building it.

The parking lot is healthy when it has clear entries with clear revisit signals. It's unhealthy when it becomes a wishlist with vague "we'll get to it" language. Be specific.

---

*Last updated: May 2026.*
