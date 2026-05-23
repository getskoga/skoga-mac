// Skoga — shared UI components: icons, wordmark, status, sparkline

// ─────────────────────────────────────────────────────────
// Icons (stroke, currentColor — minimal, lucide-shaped)
// ─────────────────────────────────────────────────────────

const Icon = ({ d, size = 14, stroke = 1.5, fill = "none", children, vb = "0 0 24 24" }) => (
  <svg width={size} height={size} viewBox={vb} fill={fill} stroke="currentColor"
       strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    {children || <path d={d} />}
  </svg>
);

// Skoga glyph — pair of overlapping pines (the "place-mark")
const SkogaGlyph = ({ size = 22 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
    <path d="M12 2.5 L18 9.5 L15.5 9.5 L20 15 L17 15 L21 20 L3 20 L7 15 L4 15 L8.5 9.5 L6 9.5 Z"
          fill="currentColor" stroke="none" />
    <path d="M12 20 L12 22.5" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
  </svg>
);

const IconRoster   = (p) => <Icon {...p} d="M3 6h10M3 10h10M3 14h7M3 18h7 M18 4l4 4l-4 4 M18 14l4 4l-4 4" />;
const IconDispatch = (p) => <Icon {...p}><path d="M4 12h13"/><path d="M14 6l6 6-6 6"/></Icon>;
const IconReview   = (p) => <Icon {...p}><circle cx="7" cy="5" r="2"/><circle cx="7" cy="19" r="2"/><circle cx="17" cy="12" r="2"/><path d="M7 7v10"/><path d="M9 5h6a2 2 0 0 1 2 2v3"/><path d="M15 12L9 19"/></Icon>;
const IconTelemetry= (p) => <Icon {...p}><path d="M3 17l5-7 4 4 5-8 4 6"/></Icon>;
const IconSettings = (p) => <Icon {...p}><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></Icon>;
const IconBack     = (p) => <Icon {...p}><path d="M15 18l-6-6 6-6"/></Icon>;
const IconChevron  = (p) => <Icon {...p}><path d="M9 6l6 6-6 6"/></Icon>;
const IconClose    = (p) => <Icon {...p}><path d="M18 6L6 18M6 6l12 12"/></Icon>;
const IconPlus     = (p) => <Icon {...p}><path d="M12 5v14M5 12h14"/></Icon>;
const IconPause    = (p) => <Icon {...p}><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></Icon>;
const IconStop     = (p) => <Icon {...p}><rect x="5" y="5" width="14" height="14" rx="2"/></Icon>;
const IconBranch   = (p) => <Icon {...p}><circle cx="6" cy="5" r="2"/><circle cx="6" cy="19" r="2"/><circle cx="18" cy="12" r="2"/><path d="M6 7v10"/><path d="M18 10c0-3-4-3-4-5"/><path d="M14 14c0 3 4 3 4 5"/></Icon>;
const IconBolt     = (p) => <Icon {...p}><path d="M13 2L4 13h7l-1 9 9-11h-7l1-9z"/></Icon>;
const IconBug      = (p) => <Icon {...p}><rect x="8" y="6" width="8" height="14" rx="4"/><path d="M12 6V3M9 3l3 3 3-3M4 11h4M16 11h4M4 18h4M16 18h4"/></Icon>;
const IconShield   = (p) => <Icon {...p}><path d="M12 3l8 3v6c0 5-4 8-8 9-4-1-8-4-8-9V6l8-3z"/></Icon>;
const IconWrench   = (p) => <Icon {...p}><path d="M14 6a4 4 0 0 1 5 5l-9 9a3 3 0 0 1-4-4l9-9z"/><path d="M14 6l4 4"/></Icon>;
const IconBeaker   = (p) => <Icon {...p}><path d="M9 3v6L4 19a2 2 0 0 0 2 3h12a2 2 0 0 0 2-3l-5-10V3"/><path d="M8 3h8"/><path d="M6 14h12"/></Icon>;
const IconDoc      = (p) => <Icon {...p}><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><path d="M8 13h8M8 17h6"/></Icon>;
const IconGithub   = (p) => <Icon {...p}><path d="M9 19c-4 1-4-2-6-2m12 4v-3a3 3 0 0 0-1-2c3 0 6-2 6-6 0-1.5-.5-3-1.5-4 .5-1 .5-3-.5-4 0 0-1.5 0-3 1.5-3-1-6-1-9 0C5 1 3.5 1 3.5 1 2.5 2 2.5 4 3 5 2 6 1.5 7.5 1.5 9c0 4 3 6 6 6-.7.7-1 1.5-1 2v4"/></Icon>;
const IconCheck    = (p) => <Icon {...p}><path d="M5 12l5 5L20 7"/></Icon>;
const IconAlert    = (p) => <Icon {...p}><path d="M12 2L1 21h22L12 2z"/><path d="M12 9v5M12 18v.5"/></Icon>;
const IconCmd      = (p) => <Icon {...p}><path d="M18 6a3 3 0 0 1-3 3H9a3 3 0 1 1 3-3v12a3 3 0 1 1-3-3h6a3 3 0 1 1 3 3"/></Icon>;
const IconSearch   = (p) => <Icon {...p}><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></Icon>;
const IconWatch    = (p) => <Icon {...p}><rect x="6" y="6" width="12" height="12" rx="6"/><path d="M12 9v3l2 1"/><path d="M9 6V4h6v2M9 18v2h6v-2"/></Icon>;
const IconSpark    = (p) => <Icon {...p}><path d="M12 3l1.8 5.4L19 10l-5.2 1.6L12 17l-1.8-5.4L5 10l5.2-1.6z"/></Icon>;
const IconClock    = (p) => <Icon {...p}><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></Icon>;
const IconLoop     = (p) => <Icon {...p}><path d="M3 12a9 9 0 0 1 15-6.7L21 8"/><path d="M21 4v4h-4"/><path d="M21 12a9 9 0 0 1-15 6.7L3 16"/><path d="M3 20v-4h4"/></Icon>;

// Role → glyph map (subtle)
const ROLE_ICON = {
  "backend / svc":      IconBranch,
  "frontend / web":     IconBolt,
  "frontend / ui":      IconBolt,
  "frontend / a11y":    IconBolt,
  "qa / e2e":           IconBeaker,
  "qa / load":          IconBeaker,
  "devops / ci":        IconWrench,
  "refactor":           IconLoop,
  "docs":               IconDoc,
  "data / migrate":     IconBranch,
  "data / etl":         IconBranch,
  "debug":              IconBug,
  "security":           IconShield,
  "api / contracts":    IconBranch,
  "perf":               IconSpark,
  "infra":              IconWrench,
  "search":             IconSearch,
  "backend / api":      IconBranch,
  "release":            IconCheck,
};

// ─────────────────────────────────────────────────────────
// Status helpers
// ─────────────────────────────────────────────────────────

const STATUS_LABEL = {
  running: "Running",
  blocked: "Blocked",
  review:  "PR up",
  done:    "Done",
  idle:    "Idle",
};

const StatusPill = ({ status }) => (
  <span className="status-pill" style={{ color: `var(--${
    {running:"amber", blocked:"ember", review:"dusk", done:"forest", idle:"ink-faint"}[status]
  })` }}>
    <span className={"pulse " + status} />
    {STATUS_LABEL[status]}
  </span>
);

// initials from "Björn" → "Bj"
function initials(name) {
  return String(name).trim().slice(0, 2);
}

// ─────────────────────────────────────────────────────────
// Wordmark
// ─────────────────────────────────────────────────────────

function Wordmark() {
  return (
    <div className="wordmark">
      <div className="glyph"><SkogaGlyph size={20} /></div>
      <div className="name">Skoga</div>
      <span className="badge">α 0.7</span>
    </div>
  );
}

// ─────────────────────────────────────────────────────────
// Activity bars (instrument-strip sparkline)
// ─────────────────────────────────────────────────────────

function ActivityBars({ data = ACTIVITY, height = 38 }) {
  // tag a few highest as "hot" so it has visual rhythm
  const enriched = data.map((v) => {
    let cls = "";
    if (v > 0.85) cls = "hot";
    else if (v > 0.65) cls = "warm";
    return { v, cls };
  });
  return (
    <div className="bars" style={{ height }}>
      {enriched.map((b, i) => (
        <i key={i} className={b.cls} style={{ height: `${Math.max(8, b.v * 100)}%` }} />
      ))}
    </div>
  );
}

// ─────────────────────────────────────────────────────────
// Sidebar nav
// ─────────────────────────────────────────────────────────

function NavItem({ icon: I, label, count, warn, active, onClick }) {
  return (
    <div className={"nav-item" + (active ? " active" : "")} onClick={onClick}>
      <div className="icon"><I size={14} /></div>
      <span>{label}</span>
      {count != null && <span className={"count" + (warn ? " warn" : "")}>{count}</span>}
    </div>
  );
}

function Sidebar({ view, setView, counts, agents, openConversation }) {
  return (
    <aside className="sidebar">
      <Wordmark />

      <div className="nav-section"><span>Cockpit</span><span className="line" /></div>
      <NavItem icon={IconRoster}    label="Roster"    count={counts.total}    active={view === "roster"}    onClick={() => setView("roster")} />
      <NavItem icon={IconDispatch}  label="Dispatch"  active={view === "dispatch"}  onClick={() => setView("dispatch")} />
      <NavItem icon={IconReview}    label="Review"    count={counts.review}    active={view === "review"}    onClick={() => setView("review")} />
      <NavItem icon={IconTelemetry} label="Telemetry" active={view === "telemetry"} onClick={() => setView("telemetry")} />

      <div className="nav-section"><span>Guild · {agents.length}</span><span className="line" /></div>
      {agents.slice(0, 8).map((a) => {
        // Slug = the part of the branch after "name/" — that's the actual issue
        const slug = a.branch.includes("/") ? a.branch.split("/").slice(1).join("/") : a.branch;
        return (
          <div key={a.id} className="nav-item" onClick={() => openConversation(a.id)}>
            <div className="icon"><span className={"pulse " + a.status} /></div>
            <span>{a.name}</span>
            <span className="count" title={slug}>{slug}</span>
          </div>
        );
      })}
      {agents.length > 8 && (
        <div className="nav-item" style={{ color: "var(--ink-faint)" }}>
          <div className="icon" /> <span>+{agents.length - 8} more</span>
        </div>
      )}

      <div className="sidebar-footer">
        <div className="you-avatar">M</div>
        <div style={{ display: "flex", flexDirection: "column", lineHeight: 1.2 }}>
          <span style={{ color: "var(--ink-2)", fontWeight: 500 }}>Mikael</span>
          <span style={{ fontFamily: "var(--mono)", fontSize: 9.5, color: "var(--ink-faint)" }}>manager · plan: forge</span>
        </div>
      </div>
    </aside>
  );
}

// ─────────────────────────────────────────────────────────
// Title bar
// ─────────────────────────────────────────────────────────

function TitleBar({ context, openCmd }) {
  return (
    <div className="titlebar">
      <div className="traffic">
        <div className="dot red"   />
        <div className="dot yellow"/>
        <div className="dot green" />
      </div>
      <div className="titlebar-center">
        <b>skoga</b> &nbsp;·&nbsp; {context}
      </div>
      <div className="titlebar-right">
        <button className="btn-ghost" onClick={openCmd}>
          <IconSearch size={12} /> Command
          <span className="kbd">⌘K</span>
        </button>
        <button className="btn-ghost" title="Notifications">
          <IconWatch size={12} />
        </button>
        <button className="btn-ghost" title="Settings">
          <IconSettings size={12} />
        </button>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────
// Cockpit — instrument strip
// ─────────────────────────────────────────────────────────

function Cockpit({ counts, spend }) {
  return (
    <div className="cockpit">
      <div className="instrument">
        <div className="label"><span className="pulse running" /> Active</div>
        <div className="value">{counts.running}<span className="unit">agents</span></div>
        <div className="sub">{counts.tokens.toLocaleString()} tok · last 5m</div>
      </div>

      <div className={"instrument" + (counts.blocked > 0 ? " attn" : "")}>
        <div className="label"><span className={"pulse " + (counts.blocked > 0 ? "blocked" : "idle")} /> Needs you</div>
        <div className="value">{counts.blocked}<span className="unit">blocked</span></div>
        <div className="sub">{counts.blocked > 0 ? "questions pending" : "all clear"}</div>
      </div>

      <div className="instrument">
        <div className="label"><span className="pulse review" /> Up for review</div>
        <div className="value">{counts.review}<span className="unit">PRs</span></div>
        <div className="sub">avg age 1h 12m</div>
      </div>

      <div className="instrument">
        <div className="label"><span className="pulse done" /> Spend</div>
        <div className="value">${spend.today.toFixed(2)}<span className="unit">today</span></div>
        <div className="sub">${spend.budget.toFixed(0)} budget · {Math.round(spend.today/spend.budget*100)}%</div>
      </div>

      <div className="activity">
        <div className="label" style={{ fontFamily: "var(--mono)", fontSize: 9.5, letterSpacing: "0.10em", textTransform: "uppercase", color: "var(--ink-faint)", display: "flex", justifyContent: "space-between" }}>
          <span>Guild pulse · last 30m</span>
          <span style={{ color: "var(--ink-mute)" }}>tokens/min</span>
        </div>
        <ActivityBars />
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────
// Filter rail
// ─────────────────────────────────────────────────────────

function FilterRail({ filter, setFilter, layout, setLayout, counts, query, setQuery, onDispatch }) {
  const Chip = ({ value, label, dot }) => (
    <div className={"chip" + (filter === value ? " on" : "")} onClick={() => setFilter(value)}>
      {dot && <span className={"pulse " + dot} />}
      {label}
      <span className="count">{counts[value]}</span>
    </div>
  );
  return (
    <div className="filter-rail">
      <div className="group">
        <Chip value="all"     label="All" />
        <Chip value="running" label="Running" dot="running" />
        <Chip value="blocked" label="Blocked" dot="blocked" />
        <Chip value="review"  label="Review"  dot="review" />
        <Chip value="done"    label="Done"    dot="done" />
        <Chip value="idle"    label="Idle"    dot="idle" />
      </div>

      <div className="grow" />

      <div className="search">
        <IconSearch size={12} />
        <input
          placeholder="Filter agents, tasks, repos…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
      </div>

      <button className="btn-primary forest" onClick={onDispatch}>
        <IconPlus size={13} /> Dispatch
      </button>
    </div>
  );
}

// ─────────────────────────────────────────────────────────
// Agent card (CARDS layout)
// ─────────────────────────────────────────────────────────

function AgentCard({ a, onClick }) {
  const RoleIcon = ROLE_ICON[a.role] || IconBranch;
  return (
    <div className={"agent-card" + (a.attn ? " attn" : "")} onClick={onClick}>
      <div className="top-row">
        <div className="avatar">{initials(a.name)}</div>
        <div style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>
          <div className="name">{a.name}</div>
          <div className="role"><RoleIcon size={10} /> &nbsp;{a.role}</div>
        </div>
        <StatusPill status={a.status} />
      </div>

      {a.attn && (
        <div className="attn-banner">{a.attnMessage}</div>
      )}

      <div className="task">
        <span className="repo">{a.repo} · {a.branch}</span>
        {a.task}
      </div>

      <div className="progress-row">
        <div className="bar">
          <i
            className={a.status === "blocked" ? "warn" : a.status === "running" ? "warm" : ""}
            style={{ width: `${Math.round(a.progress * 100)}%` }}
          />
        </div>
        <span className="mono" style={{ fontSize: 10.5, color: "var(--ink-mute)" }}>
          {Math.round(a.progress * 100)}%
        </span>
      </div>

      <div className="meta-row">
        <span><IconClock size={10} /> &nbsp;{a.runtime}</span>
        <span className="sep">·</span>
        <span>{a.commits} commits</span>
        <span className="sep">·</span>
        <span>{a.files} files</span>
        <span className="right">
          <span>{a.tokens > 0 ? (a.tokens / 1000).toFixed(0) + "k tok" : "—"}</span>
          <span style={{ color: "var(--ink-faint)" }}>{a.model.split("-").slice(0, 2).join("-")}</span>
        </span>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────
// Roster table layout
// ─────────────────────────────────────────────────────────

function AgentTable({ agents, onPick }) {
  return (
    <table className="roster-table">
      <thead>
        <tr>
          <th style={{ width: 32 }}></th>
          <th>Agent</th>
          <th>Task</th>
          <th>Status</th>
          <th style={{ width: 110 }}>Progress</th>
          <th style={{ width: 80 }}>Runtime</th>
          <th style={{ width: 80 }}>Tokens</th>
        </tr>
      </thead>
      <tbody>
        {agents.map((a) => (
          <tr key={a.id} onClick={() => onPick(a.id)}>
            <td><div className="av">{initials(a.name)}</div></td>
            <td>
              <div className="name-cell">
                <div style={{ display: "flex", flexDirection: "column" }}>
                  <span className="name">{a.name}</span>
                  <span className="role">{a.role}</span>
                </div>
              </div>
            </td>
            <td>
              <div className="task-cell">
                <span className="repo">{a.repo}</span>
                <div>{a.task}</div>
              </div>
            </td>
            <td><StatusPill status={a.status} /></td>
            <td>
              <span className="bar">
                <i
                  className={a.status === "blocked" ? "warn" : a.status === "running" ? "warm" : ""}
                  style={{ width: `${Math.round(a.progress * 100)}%` }}
                />
              </span>
              &nbsp;<span className="num">{Math.round(a.progress * 100)}%</span>
            </td>
            <td><span className="num">{a.runtime}</span></td>
            <td><span className="num">{a.tokens > 0 ? (a.tokens / 1000).toFixed(0) + "k" : "—"}</span></td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

// ─────────────────────────────────────────────────────────
// Roster list (dense one-line)
// ─────────────────────────────────────────────────────────

function AgentList({ agents, onPick }) {
  return (
    <div>
      {agents.map((a) => (
        <div key={a.id} className="roster-list-row" onClick={() => onPick(a.id)}>
          <span className={"pulse " + a.status} />
          <div className="name-cell">
            <span className="name">{a.name}</span>
            <span className="role">{a.role}</span>
          </div>
          <div className="task-cell">
            <span className="repo">{a.repo}</span>
            {a.task}
          </div>
          <span className="num">{a.runtime}</span>
          <span><span className="bar" style={{ width: 60, height: 4, background: "var(--paper-4)", borderRadius: 2, display: "inline-block", overflow: "hidden", verticalAlign: "middle" }}>
            <i style={{ display: "block", height: "100%", width: `${Math.round(a.progress * 100)}%`, background: a.status === "blocked" ? "var(--ember)" : a.status === "running" ? "var(--amber)" : "var(--forest)" }} />
          </span></span>
          <span className="num">{a.tokens > 0 ? (a.tokens / 1000).toFixed(0) + "k" : "—"}</span>
        </div>
      ))}
    </div>
  );
}

Object.assign(window, {
  Icon, SkogaGlyph, IconRoster, IconDispatch, IconReview, IconTelemetry,
  IconSettings, IconBack, IconChevron, IconClose, IconPlus, IconPause, IconStop,
  IconBranch, IconBolt, IconBug, IconShield, IconWrench, IconBeaker, IconDoc,
  IconGithub, IconCheck, IconAlert, IconCmd, IconSearch, IconWatch, IconSpark, IconClock, IconLoop,
  ROLE_ICON, STATUS_LABEL, StatusPill, initials,
  Wordmark, ActivityBars, NavItem, Sidebar, TitleBar, Cockpit,
  FilterRail, AgentCard, AgentTable, AgentList,
});
