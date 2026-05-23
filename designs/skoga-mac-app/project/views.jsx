// Skoga — Roster / Conversation / Dispatch / PR modal views

// ─────────────────────────────────────────────────────────
// Roster view (assembles cockpit + filter + grid/table/list)
// ─────────────────────────────────────────────────────────

function RosterView({ agents, layout, filter, setFilter, query, setQuery, onPick, onDispatch }) {
  const counts = React.useMemo(() => ({
    all: agents.length,
    running: agents.filter((a) => a.status === "running").length,
    blocked: agents.filter((a) => a.status === "blocked").length,
    review:  agents.filter((a) => a.status === "review").length,
    done:    agents.filter((a) => a.status === "done").length,
    idle:    agents.filter((a) => a.status === "idle").length,
  }), [agents]);

  const filtered = React.useMemo(() => {
    let xs = filter === "all" ? agents : agents.filter((a) => a.status === filter);
    if (query) {
      const q = query.toLowerCase();
      xs = xs.filter((a) =>
        a.name.toLowerCase().includes(q) ||
        a.task.toLowerCase().includes(q) ||
        a.repo.toLowerCase().includes(q) ||
        a.role.toLowerCase().includes(q)
      );
    }
    // sort blocked-first, then running, review, done, idle
    const order = { blocked: 0, running: 1, review: 2, done: 3, idle: 4 };
    return [...xs].sort((a, b) => order[a.status] - order[b.status]);
  }, [agents, filter, query]);

  return (
    <>
      <FilterRail
        filter={filter} setFilter={setFilter}
        counts={counts} query={query} setQuery={setQuery}
        onDispatch={onDispatch}
      />
      {layout === "cards" && (
        <div className="roster cards">
          {filtered.map((a) => (
            <AgentCard key={a.id} a={a} onClick={() => onPick(a.id)} />
          ))}
        </div>
      )}
      {layout === "table" && (
        <div className="roster table">
          <AgentTable agents={filtered} onPick={onPick} />
        </div>
      )}
      {layout === "list" && (
        <div className="roster list">
          <AgentList agents={filtered} onPick={onPick} />
        </div>
      )}
    </>
  );
}

// ─────────────────────────────────────────────────────────
// Conversation pane
// ─────────────────────────────────────────────────────────

function ConvMsg({ m, agent }) {
  const isYou = m.from === "you";
  const name = isYou ? "You" : (agent ? agent.name : m.from);
  const initial = isYou ? "M" : (agent ? initials(agent.name) : m.from.slice(0, 2));
  return (
    <div className={"msg " + (isYou ? "you" : "")}>
      <div className="av">{initial}</div>
      <div className="body">
        <div className="meta">
          <b>{name}</b>
          <span>·</span>
          <span>{m.when}</span>
          {m.runtimeLabel && <><span>·</span><span>{m.runtimeLabel}</span></>}
        </div>
        <div className="text">
          {m.text.map((p, i) => <p key={i}>{p}</p>)}
        </div>
      </div>
    </div>
  );
}

function ConvTool({ m }) {
  return (
    <div className="msg-tool">
      <span className="lbl">{m.tool}</span>
      {m.path && <span className="path">{m.path}</span>}
      {m.lines && <span style={{ color: "var(--ink-faint)" }}>L{m.lines}</span>}
      {m.cmd && <span className="path">$ {m.cmd}</span>}
      {m.result && <span style={{ marginLeft: "auto", color: "var(--ink-faint)" }}>{m.result}</span>}
    </div>
  );
}

function ConvWrite({ m }) {
  return (
    <div className="msg-tool">
      <span className="lbl">write</span>
      <span className="path">{m.path}</span>
      <span className="diff">
        <span className="add">+{m.adds}</span>
        <span className="rem">−{m.rems}</span>
      </span>
    </div>
  );
}

function ConvQuestion({ m, onChoose }) {
  return (
    <div className="msg-question">
      <span className="lbl">⚠ {m.label}</span>
      <div style={{ fontFamily: "var(--mono)", fontSize: 11.5, lineHeight: 1.6, color: "var(--ink-2)", whiteSpace: "pre-wrap" }}>
        {m.body.join("\n")}
      </div>
      <div className="opts">
        {m.opts.map((o, i) => (
          <button key={i} className="btn-ghost" onClick={() => onChoose(o)}>{o}</button>
        ))}
      </div>
    </div>
  );
}

function ConversationView({ agent, conversation, onBack, onOpenPR, onChooseOption, pendingReply, setPendingReply, onSendReply }) {
  const feedRef = React.useRef(null);
  React.useEffect(() => {
    if (feedRef.current) feedRef.current.scrollTop = feedRef.current.scrollHeight;
  }, [conversation.length]);

  return (
    <div className="conv-shell">
      <div className="conv-main">
        <div className="conv-header">
          <button className="back" onClick={onBack} title="Back to roster">
            <IconBack size={14} />
          </button>
          <div className="avatar">{initials(agent.name)}</div>
          <div>
            <div className="name">{agent.name}</div>
            <div className="sub">{agent.role} · {agent.model} · {agent.repo}</div>
          </div>
          <div className="conv-header-right">
            {agent.status === "review" && (
              <button className="btn-primary forest" onClick={onOpenPR}>
                <IconGithub size={12} /> Open as PR
              </button>
            )}
            {agent.status !== "review" && agent.status !== "done" && (
              <>
                <button className="btn-ghost"><IconPause size={12} /> Pause</button>
                <button className="btn-ghost" style={{ color: "var(--ember)" }}>
                  <IconStop size={12} /> Stop
                </button>
              </>
            )}
            {agent.status === "review" && (
              <button className="btn-ghost"><IconGithub size={12} /> Already open</button>
            )}
          </div>
        </div>

        <div className="conv-feed" ref={feedRef}>
          {conversation.map((m, i) => {
            if (m.kind === "msg")      return <ConvMsg key={i} m={m} agent={m.from === "you" ? null : agent} />;
            if (m.kind === "tool")     return <ConvTool key={i} m={m} />;
            if (m.kind === "write")    return <ConvWrite key={i} m={m} />;
            if (m.kind === "question") return <ConvQuestion key={i} m={m} onChoose={onChooseOption} />;
            return null;
          })}
        </div>

        <div className="conv-composer">
          <textarea
            placeholder={agent.status === "blocked"
              ? `Answer ${agent.name}'s question, or redirect…`
              : `Reply to ${agent.name}…`}
            value={pendingReply}
            onChange={(e) => setPendingReply(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
                e.preventDefault();
                onSendReply();
              }
            }}
          />
          <div className="composer-foot">
            <span><span className="kbd" style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--ink-faint)", padding: "1px 4px", border: "0.5px solid var(--rule)", borderRadius: 3, background: "var(--paper)" }}>⌘↵</span> &nbsp;send</span>
            <span style={{ color: "var(--ink-faint)" }}>·</span>
            <span>Attached: {agent.branch}</span>
            <div className="grow" />
            <button className="btn-text">@mention</button>
            <button className="btn-text">/ commands</button>
            <button className="btn-primary" onClick={onSendReply} disabled={!pendingReply.trim()}>
              Send
            </button>
          </div>
        </div>
      </div>

      {/* Right side panel — activity timeline + run details */}
      <aside className="conv-side">
        <div className="block">
          <div className="block-title">Run details</div>
          <dl className="kv">
            <dt>repo</dt><dd className="mono">{agent.repo}</dd>
            <dt>branch</dt><dd className="mono">{agent.branch}</dd>
            <dt>base</dt><dd className="mono">main · a91f3d2</dd>
            <dt>model</dt><dd className="mono">{agent.model}</dd>
            <dt>runtime</dt><dd className="mono">{agent.runtime}</dd>
            <dt>spend</dt><dd className="mono">${agent.cost.toFixed(2)} · {(agent.tokens/1000).toFixed(0)}k tok</dd>
            <dt>commits</dt><dd className="mono">{agent.commits}</dd>
            <dt>files</dt><dd className="mono">{agent.files}</dd>
          </dl>
        </div>

        <div className="block">
          <div className="block-title">Activity</div>
          <div className="timeline-rail">
            {(agent.id === "astrid" ? ASTRID_TIMELINE : ASTRID_TIMELINE).map((t, i) => (
              <div key={i} className={"timeline-item " + t.kind}>
                <div className="dot" />
                <div>
                  <div className="when">{t.when}</div>
                  <div className="what">{t.what}</div>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="block">
          <div className="block-title">Quick actions</div>
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <button className="btn-ghost" style={{ justifyContent: "flex-start", height: 32 }}>
              <IconGithub size={12} /> View commits on GitHub
            </button>
            <button className="btn-ghost" style={{ justifyContent: "flex-start", height: 32 }}>
              <IconLoop size={12} /> Drop into editor (worktree)
            </button>
            <button className="btn-ghost" style={{ justifyContent: "flex-start", height: 32 }}>
              <IconWatch size={12} /> Ping me when done
            </button>
          </div>
        </div>
      </aside>
    </div>
  );
}

// ─────────────────────────────────────────────────────────
// Dispatch view
// ─────────────────────────────────────────────────────────

const TEMPLATES = [
  { id: "feature", glyph: IconBolt,   title: "Feature",   desc: "Build something new" },
  { id: "fix",     glyph: IconBug,    title: "Bug fix",   desc: "Reproduce + patch" },
  { id: "refactor",glyph: IconLoop,   title: "Refactor",  desc: "No behaviour change" },
  { id: "test",    glyph: IconBeaker, title: "Tests",     desc: "Cover an area" },
  { id: "perf",    glyph: IconSpark,  title: "Perf",      desc: "Profile + speed up" },
  { id: "docs",    glyph: IconDoc,    title: "Docs",      desc: "Write + update" },
];

const REPOS = [
  "skoga/monolith-web", "skoga/ledger-svc", "skoga/core-runtime",
  "skoga/search-svc", "skoga/etl", "skoga/infra", "skoga/pkg-clients", "skoga/docs",
];

function DispatchView({ agents, onSubmit, onBack }) {
  const [tmpl, setTmpl] = React.useState("feature");
  const [title, setTitle] = React.useState("Wire Stripe customer portal callbacks into settings → billing");
  const [body, setBody] = React.useState(
    "Hook the Stripe customer-portal redirect into Settings → Billing.\n\n" +
    "When the user clicks Manage subscription:\n" +
    "  1. Hit /v2/billing/portal-session to mint a session URL\n" +
    "  2. Redirect with return_url back to /settings/billing?from=portal\n" +
    "  3. On return, fetch fresh /v2/billing/subscription and update the cache\n\n" +
    "Edge cases: handle the case where the session is expired, and ensure the UI shows a sensible 'Refreshing…' state on return."
  );
  const [repo, setRepo] = React.useState("skoga/monolith-web");
  const [assignee, setAssignee] = React.useState("auto");
  const [model, setModel] = React.useState("claude-sonnet-4.7");
  const [budget, setBudget] = React.useState("4.00");

  const idleOrLight = agents.filter((a) => a.status === "idle" || a.status === "done").slice(0, 6);

  return (
    <div className="dispatch-shell">
      <div className="dispatch-main">
        <button className="btn-ghost" style={{ marginBottom: 16 }} onClick={onBack}>
          <IconBack size={12} /> Back to roster
        </button>
        <h1>Dispatch a new run</h1>
        <p className="hero-sub">
          Spawn an agent against a fresh worktree. Write it like a ticket — clear acceptance, links to context.
          You can always drop into the conversation to redirect.
        </p>

        <div className="dispatch-form">
          {/* template */}
          <div className="dispatch-field">
            <div className="field-label">Shape of work</div>
            <div className="template-row">
              {TEMPLATES.map((t) => {
                const G = t.glyph;
                return (
                  <button key={t.id}
                          className={"template-card" + (tmpl === t.id ? " on" : "")}
                          onClick={() => setTmpl(t.id)}>
                    <div className="glyph"><G size={18} /></div>
                    <div className="ttl">{t.title}</div>
                    <div className="desc">{t.desc}</div>
                  </button>
                );
              })}
            </div>
          </div>

          {/* title */}
          <div className="dispatch-field">
            <div className="field-label">Headline</div>
            <input className="dispatch-input"
                   value={title} onChange={(e) => setTitle(e.target.value)} />
          </div>

          {/* body */}
          <div className="dispatch-field">
            <div className="field-label">Brief · spec · acceptance</div>
            <textarea className="dispatch-textarea"
                      value={body} onChange={(e) => setBody(e.target.value)} />
          </div>

          {/* repo */}
          <div className="dispatch-field">
            <div className="field-label">Repository</div>
            <div className="repo-pills">
              {REPOS.map((r) => (
                <button key={r}
                        className={"repo-pill" + (repo === r ? " on" : "")}
                        onClick={() => setRepo(r)}>{r}</button>
              ))}
            </div>
          </div>

          {/* assignee */}
          <div className="dispatch-field">
            <div className="field-label">Assign to</div>
            <div className="assignee-row">
              <button className={"assignee-card auto" + (assignee === "auto" ? " on" : "")}
                      onClick={() => setAssignee("auto")}>
                <div className="av"><IconSpark size={14} /></div>
                <div className="meta">
                  <span className="nm">Auto · best fit</span>
                  <span className="st">Roster + history</span>
                </div>
              </button>
              <button className={"assignee-card" + (assignee === "spawn" ? " on" : "")}
                      onClick={() => setAssignee("spawn")}>
                <div className="av"><IconPlus size={14} /></div>
                <div className="meta">
                  <span className="nm">New agent</span>
                  <span className="st">Fresh runtime</span>
                </div>
              </button>
              {idleOrLight.map((a) => (
                <button key={a.id}
                        className={"assignee-card" + (assignee === a.id ? " on" : "")}
                        onClick={() => setAssignee(a.id)}>
                  <div className="av">{initials(a.name)}</div>
                  <div className="meta">
                    <span className="nm">{a.name}</span>
                    <span className="st">{a.role.split(" / ")[0]} · {a.status}</span>
                  </div>
                </button>
              ))}
            </div>
          </div>

          {/* model + budget */}
          <div className="dispatch-field" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
            <div>
              <div className="field-label">Model</div>
              <select className="dispatch-select" value={model} onChange={(e) => setModel(e.target.value)}>
                <option>claude-sonnet-4.7</option>
                <option>claude-opus-4.7</option>
                <option>gpt-5-codex</option>
                <option>gpt-5-mini</option>
                <option>local · qwen3-coder-32b</option>
              </select>
            </div>
            <div>
              <div className="field-label">Budget cap</div>
              <input className="dispatch-input"
                     value={"$" + budget}
                     onChange={(e) => setBudget(e.target.value.replace(/[^0-9.]/g, ""))} />
            </div>
          </div>

          <div className="dispatch-actions">
            <button className="btn-primary forest" onClick={() => onSubmit({ title, repo, assignee })}>
              <IconBolt size={13} /> Dispatch run
            </button>
            <button className="btn-ghost">Save as template</button>
            <span className="hint">⌘↵ to dispatch</span>
          </div>
        </div>
      </div>

      {/* preview side */}
      <aside className="dispatch-aside">
        <div className="block-title">Ticket preview</div>
        <div className="preview-ticket">
          <h3>{title || "Untitled run"}</h3>
          <div style={{ fontSize: 12, color: "var(--ink-mute)", lineHeight: 1.5, whiteSpace: "pre-wrap", maxHeight: 180, overflow: "hidden", maskImage: "linear-gradient(180deg, #000 60%, transparent)" }}>
            {body}
          </div>
          <dl className="kv">
            <dt>shape</dt><dd>{TEMPLATES.find((t) => t.id === tmpl)?.title}</dd>
            <dt>repo</dt><dd className="mono">{repo}</dd>
            <dt>branch</dt><dd className="mono">{(assignee === "auto" || assignee === "spawn" ? "agent" : assignee) + "/" + (title || "untitled").toLowerCase().replace(/[^a-z0-9]+/g, "-").slice(0, 28)}</dd>
            <dt>assignee</dt><dd>
              {assignee === "auto" ? "Auto · best fit"
                : assignee === "spawn" ? "New agent · spawn fresh"
                : (agents.find((a) => a.id === assignee)?.name || "—")}
            </dd>
            <dt>model</dt><dd className="mono">{model}</dd>
          </dl>
        </div>

        <div className="block-title">Estimate</div>
        <div className="preview-est">
          <div className="row"><span className="label">Time</span><span className="num">~1h 40m</span></div>
          <div className="row"><span className="label">Tokens</span><span className="num">180k – 240k</span></div>
          <div className="row"><span className="label">Cost</span><span className="num">$1.40 – $2.00</span></div>
          <div style={{ fontSize: 10.5, color: "var(--ink-faint)", fontFamily: "var(--mono)", marginTop: 4 }}>
            Based on 24 similar runs in this repo.
          </div>
        </div>

        <div className="block-title">Worktree</div>
        <div className="preview-est">
          <div style={{ fontFamily: "var(--mono)", fontSize: 10.5, color: "var(--ink-2)", lineHeight: 1.6 }}>
            $ git worktree add<br />
            &nbsp;&nbsp;<span style={{ color: "var(--ink-mute)" }}>.skoga/worktrees/{(assignee === "auto" ? "auto" : assignee)}-{Date.now().toString(36).slice(-4)}</span><br />
            &nbsp;&nbsp;-b {(assignee === "auto" ? "agent" : assignee)}/{(title || "untitled").toLowerCase().replace(/[^a-z0-9]+/g, "-").slice(0, 18)}<br />
            <span style={{ color: "var(--ink-faint)" }}># isolated · ephemeral</span>
          </div>
        </div>
      </aside>
    </div>
  );
}

// ─────────────────────────────────────────────────────────
// PR handoff modal
// ─────────────────────────────────────────────────────────

function PRModal({ agent, onClose, onConfirm }) {
  const [title, setTitle] = React.useState(agent.task.replace(/\.$/, ""));
  const [body, setBody] = React.useState(
`## Summary
${agent.task}

## What changed
- Added \`RefreshableScope\` wrapper around the Stripe scope cache
- On 401 from Stripe, transparently re-issues against the current secret and retries once
- Removed stale 60s scope-token cache (made invalid by rotates)

## Tests
- 11 new tests covering rotate-mid-flight + repeated 401s
- All \`pnpm -w test auth\` passing (57/57)

## Notes
Co-authored-by: Skoga / ${agent.name} <${agent.id}@agents.skoga.dev>`);

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-head">
          <div className="icon"><IconGithub size={18} /></div>
          <div>
            <h2 className="ttl">Open as Pull Request</h2>
            <div className="sub">{agent.repo} · {agent.branch}</div>
          </div>
          <button className="x" onClick={onClose}><IconClose size={12} /></button>
        </div>

        <div className="modal-body">
          <div className="branch-row">
            <div className="branch-pill"><span className="lbl">from</span>{agent.branch}</div>
            <div className="arrow">→</div>
            <div className="branch-pill"><span className="lbl">into</span>main</div>
          </div>

          <div className="diff-stat">
            <span className="files">{agent.files} files</span>
            <span className="add">+{agent.commits * 18}</span>
            <span className="rem">−{agent.commits * 4}</span>
            <span className="squares" style={{ marginLeft: "auto" }}>
              {Array.from({ length: 18 }).map((_, i) => (
                <i key={i} className={i < 13 ? "add" : i < 16 ? "rem" : ""} />
              ))}
            </span>
          </div>

          <div className="field">
            <label>Title</label>
            <input value={title} onChange={(e) => setTitle(e.target.value)} />
          </div>

          <div className="field">
            <label>Description</label>
            <textarea value={body} onChange={(e) => setBody(e.target.value)} />
          </div>

          <div className="field" style={{ flexDirection: "row", gap: 14, alignItems: "center" }}>
            <label style={{ marginRight: "auto" }}>Reviewers</label>
            <div style={{ display: "flex", gap: 6 }}>
              <div className="repo-pill">@mikael</div>
              <div className="repo-pill" style={{ background: "var(--paper)" }}>+ add</div>
            </div>
          </div>
        </div>

        <div className="modal-foot">
          <span className="hint">PR feedback will route back to {agent.name} automatically.</span>
          <div className="grow" />
          <button className="btn-ghost" onClick={onClose}>Cancel</button>
          <button className="btn-primary forest" onClick={onConfirm}>
            <IconGithub size={12} /> Open PR on GitHub
          </button>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────
// Empty / placeholder views (Review · Telemetry)
// ─────────────────────────────────────────────────────────

function ReviewView({ agents, onPick }) {
  const inReview = agents.filter((a) => a.status === "review");
  return (
    <div style={{ padding: 28, overflowY: "auto", flex: 1 }}>
      <h1 style={{ fontFamily: "var(--serif)", fontSize: 26, fontWeight: 500, margin: "0 0 6px" }}>Up for review</h1>
      <p style={{ fontSize: 13, color: "var(--ink-mute)", margin: "0 0 22px", maxWidth: 540, lineHeight: 1.5 }}>
        These agents finished their runs. Open as PRs on GitHub — review feedback loops back to the agent.
      </p>
      <div className="roster cards" style={{ padding: 0 }}>
        {inReview.map((a) => <AgentCard key={a.id} a={a} onClick={() => onPick(a.id)} />)}
      </div>
    </div>
  );
}

function TelemetryView({ agents }) {
  const totalSpend = agents.reduce((s, a) => s + a.cost, 0);
  const totalTok = agents.reduce((s, a) => s + a.tokens, 0);
  const byModel = {};
  agents.forEach((a) => {
    byModel[a.model] = byModel[a.model] || { runs: 0, cost: 0, tok: 0 };
    byModel[a.model].runs++;
    byModel[a.model].cost += a.cost;
    byModel[a.model].tok += a.tokens;
  });

  return (
    <div style={{ padding: 28, overflowY: "auto", flex: 1 }}>
      <h1 style={{ fontFamily: "var(--serif)", fontSize: 26, fontWeight: 500, margin: "0 0 6px" }}>Telemetry · today</h1>
      <p style={{ fontSize: 13, color: "var(--ink-mute)", margin: "0 0 22px" }}>
        Spend, throughput, and which agents keep getting stuck.
      </p>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 14, marginBottom: 22 }}>
        <div className="agent-card">
          <div className="role">spend</div>
          <div style={{ fontFamily: "var(--serif)", fontSize: 32, fontWeight: 500 }}>${totalSpend.toFixed(2)}</div>
          <div className="mono" style={{ fontSize: 11, color: "var(--ink-mute)" }}>of $40.00 budget · {Math.round(totalSpend / 40 * 100)}%</div>
        </div>
        <div className="agent-card">
          <div className="role">tokens</div>
          <div style={{ fontFamily: "var(--serif)", fontSize: 32, fontWeight: 500 }}>{(totalTok/1_000_000).toFixed(2)}M</div>
          <div className="mono" style={{ fontSize: 11, color: "var(--ink-mute)" }}>{agents.length} agents · avg {(totalTok/agents.length/1000).toFixed(0)}k each</div>
        </div>
        <div className="agent-card">
          <div className="role">blocked rate</div>
          <div style={{ fontFamily: "var(--serif)", fontSize: 32, fontWeight: 500 }}>{Math.round(agents.filter((a) => a.attn).length / agents.length * 100)}%</div>
          <div className="mono" style={{ fontSize: 11, color: "var(--ink-mute)" }}>{agents.filter((a) => a.attn).length} of {agents.length} need you</div>
        </div>
      </div>

      <div className="block-title" style={{ fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.10em", textTransform: "uppercase", color: "var(--ink-faint)", marginBottom: 10 }}>
        By model
      </div>
      <table className="roster-table">
        <thead>
          <tr><th>Model</th><th>Runs</th><th>Tokens</th><th>Spend</th><th>$/run</th></tr>
        </thead>
        <tbody>
          {Object.entries(byModel).map(([m, v]) => (
            <tr key={m}>
              <td className="mono" style={{ fontSize: 12 }}>{m}</td>
              <td><span className="num">{v.runs}</span></td>
              <td><span className="num">{(v.tok/1000).toFixed(0)}k</span></td>
              <td><span className="num">${v.cost.toFixed(2)}</span></td>
              <td><span className="num">${(v.cost/v.runs).toFixed(2)}</span></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

Object.assign(window, {
  RosterView, ConversationView, DispatchView, PRModal, ReviewView, TelemetryView,
});
