// Skoga — root App

const PALETTES = {
  forest: { name: "Forest",  hue: 145 },
  ember:  { name: "Ember",   hue: 38  },
  dusk:   { name: "Dusk",    hue: 245 },
  amber:  { name: "Amber",   hue: 75  },
};

function App({ initial = {}, printMode = false }) {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);

  // dark/light handling — skip in printMode so multiple App instances don't fight
  React.useEffect(() => {
    if (printMode) return;
    document.documentElement.setAttribute("data-theme", t.dark ? "dark" : "light");
  }, [t.dark, printMode]);

  // accent palette → re-tint --forest / --forest-deep / --forest-soft
  React.useEffect(() => {
    if (printMode) return;
    const hue = PALETTES[t.accent]?.hue ?? 145;
    const root = document.documentElement;
    root.style.setProperty("--forest",       `oklch(0.46 0.085 ${hue})`);
    root.style.setProperty("--forest-deep",  `oklch(0.34 0.075 ${hue})`);
    root.style.setProperty("--forest-soft",  `oklch(0.86 0.040 ${hue})`);
  }, [t.accent, printMode]);

  // font mode → swap UI sans → mono
  React.useEffect(() => {
    if (printMode) return;
    document.body.classList.toggle("font-mono-mode", t.font === "mono");
  }, [t.font, printMode]);

  // ── App state ────────────────────────────────────────
  const allAgents = AGENTS_FULL;
  const agents = allAgents.slice(0, Math.max(3, Math.min(allAgents.length, t.agentCount)));

  const [view, setView] = React.useState(initial.view || "roster");
  const [openAgentId, setOpenAgentId] = React.useState(initial.openAgentId || null);
  const [filter, setFilter] = React.useState(initial.filter || "all");
  const [query, setQuery] = React.useState("");
  const [prAgentId, setPrAgentId] = React.useState(initial.prAgentId || null);
  const [toast, setToast] = React.useState(null);
  const [showCmd, setShowCmd] = React.useState(false);

  // dynamic conversation (so reply persists)
  const [convExtras, setConvExtras] = React.useState({});   // {agentId: [extra msgs]}
  const [pendingReply, setPendingReply] = React.useState("");

  const counts = React.useMemo(() => ({
    total: agents.length,
    running: agents.filter((a) => a.status === "running").length,
    blocked: agents.filter((a) => a.status === "blocked").length,
    review:  agents.filter((a) => a.status === "review").length,
    done:    agents.filter((a) => a.status === "done").length,
    idle:    agents.filter((a) => a.status === "idle").length,
    tokens:  agents.reduce((s, a) => s + a.tokens, 0),
  }), [agents]);

  const spend = React.useMemo(() => ({
    today: agents.reduce((s, a) => s + a.cost, 0),
    budget: 40,
  }), [agents]);

  // ── Actions ──────────────────────────────────────────
  const openConversation = (id) => {
    setOpenAgentId(id);
    setView("conversation");
    setPendingReply("");
  };

  const goBack = () => {
    setView("roster");
    setOpenAgentId(null);
  };

  const onDispatch = () => { setView("dispatch"); };

  const submitDispatch = ({ title }) => {
    setView("roster");
    showToast(`Dispatched "${title.slice(0, 48)}${title.length > 48 ? "…" : ""}". Worktree booting…`);
  };

  const openPR = (id) => setPrAgentId(id);
  const confirmPR = () => {
    const a = agents.find((x) => x.id === prAgentId);
    setPrAgentId(null);
    showToast(`Opened PR for ${a.name}. Routing review back to the agent.`);
  };

  const showToast = (text) => {
    setToast(text);
    clearTimeout(showToast.t);
    showToast.t = setTimeout(() => setToast(null), 3400);
  };

  const answerQuestion = (opt) => {
    if (!openAgentId) return;
    setConvExtras((prev) => ({
      ...prev,
      [openAgentId]: [
        ...(prev[openAgentId] || []),
        { kind: "msg", from: "you", when: "now", text: [`${opt}.`] },
        { kind: "msg", from: openAgentId, when: "now",
          text: ["Got it. Picking that — re-running the failing specs with the new resume rule. Will report back in a few minutes."],
          runtimeLabel: "claude-sonnet-4.7" },
      ],
    }));
  };

  const sendReply = () => {
    if (!pendingReply.trim() || !openAgentId) return;
    const text = pendingReply.trim();
    setPendingReply("");
    setConvExtras((prev) => ({
      ...prev,
      [openAgentId]: [
        ...(prev[openAgentId] || []),
        { kind: "msg", from: "you", when: "now", text: [text] },
        { kind: "msg", from: openAgentId, when: "now",
          text: ["Acknowledged — taking that direction now."],
          runtimeLabel: "claude-sonnet-4.7" },
      ],
    }));
  };

  // Send a reply directly from a roster card (without opening conversation)
  const sendCardReply = (agentId, text) => {
    setConvExtras((prev) => ({
      ...prev,
      [agentId]: [
        ...(prev[agentId] || []),
        { kind: "msg", from: "you", when: "now", text: [text] },
        { kind: "msg", from: agentId, when: "now",
          text: ["Got it — picking that up now."],
          runtimeLabel: "claude-sonnet-4.7" },
      ],
    }));
    const a = agents.find((x) => x.id === agentId);
    if (a) showToast(`Sent to ${a.name}.`);
  };

  // ── Command palette (⌘K) ─────────────────────────────
  React.useEffect(() => {
    if (printMode) return;
    const onKey = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setShowCmd((s) => !s);
      }
      if (e.key === "Escape") setShowCmd(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [printMode]);

  // ── Current conversation ─────────────────────────────
  const openAgent = openAgentId ? agents.find((a) => a.id === openAgentId) : null;
  const baseConv = openAgentId ? (CONVERSATIONS[openAgentId] || []) : [];
  const conversation = openAgent ? [...baseConv, ...(convExtras[openAgentId] || [])] : [];

  // If agent has no real conversation, synthesize a tiny one
  const synthConv = openAgent && baseConv.length === 0 ? [
    { kind: "msg", from: "you", initial: "M", when: "earlier", text: [openAgent.task] },
    { kind: "msg", from: openAgent.id, when: "earlier",
      text: ["On it. Setting up the worktree."], runtimeLabel: openAgent.model },
    { kind: "tool", tool: "read", path: openAgent.repo.replace("skoga/", "") + "/README.md", lines: "1–80" },
    { kind: "msg", from: openAgent.id, when: "earlier",
      text: ["I'll send updates as I make progress. Should be done in roughly an hour."],
      runtimeLabel: openAgent.model },
    ...(convExtras[openAgentId] || []),
  ] : conversation;

  // ── Context label for titlebar
  const contextLabel = {
    roster: `Roster · ${counts.total} agents`,
    conversation: openAgent ? `1:1 with ${openAgent.name}` : "Conversation",
    dispatch: "Dispatch · new run",
    review: `Review · ${counts.review} ready`,
    telemetry: "Telemetry",
  }[view];

  return (
    <div className="skoga-app">
      <TitleBar context={contextLabel} openCmd={() => setShowCmd(true)} />

      <Sidebar
        view={view}
        setView={(v) => { setView(v); setOpenAgentId(null); }}
        counts={counts}
        agents={agents}
        openConversation={openConversation}
      />

      <main className="main">
        {view !== "conversation" && view !== "dispatch" && view !== "telemetry" && view !== "review" && (
          <Cockpit counts={counts} spend={spend} />
        )}

        {view === "roster" && (
          <RosterView
            agents={agents}
            layout={t.layout}
            filter={filter} setFilter={setFilter}
            query={query} setQuery={setQuery}
            onPick={openConversation}
            onDispatch={onDispatch}
          />
        )}

        {view === "conversation" && openAgent && (
          <ConversationView
            agent={openAgent}
            conversation={synthConv}
            onBack={goBack}
            onOpenPR={() => openPR(openAgent.id)}
            onChooseOption={answerQuestion}
            pendingReply={pendingReply}
            setPendingReply={setPendingReply}
            onSendReply={sendReply}
          />
        )}

        {view === "dispatch" && (
          <DispatchView agents={agents} onSubmit={submitDispatch} onBack={goBack} />
        )}

        {view === "review" && (
          <ReviewView agents={agents} onPick={openConversation} />
        )}

        {view === "telemetry" && (
          <TelemetryView agents={agents} />
        )}
      </main>

      {prAgentId && (
        <PRModal
          agent={agents.find((a) => a.id === prAgentId)}
          onClose={() => setPrAgentId(null)}
          onConfirm={confirmPR}
        />
      )}

      {showCmd && (
        <CommandPalette
          agents={agents}
          onPickAgent={(id) => { setShowCmd(false); openConversation(id); }}
          onView={(v) => { setShowCmd(false); setView(v); setOpenAgentId(null); }}
          onDispatch={() => { setShowCmd(false); onDispatch(); }}
          onClose={() => setShowCmd(false)}
        />
      )}

      {toast && (
        <div className="toast">
          <IconCheck size={14} /> {toast}
        </div>
      )}

      {!printMode && <SkogaTweaks t={t} setTweak={setTweak} />}
    </div>
  );
}

// ─────────────────────────────────────────────────────────
// Command palette (⌘K)
// ─────────────────────────────────────────────────────────

function CommandPalette({ agents, onPickAgent, onView, onDispatch, onClose }) {
  const [q, setQ] = React.useState("");
  const inputRef = React.useRef(null);
  React.useEffect(() => { inputRef.current?.focus(); }, []);

  const lc = q.toLowerCase();
  const cmds = [
    { id: "v-roster",    label: "Go to Roster",    icon: IconRoster,    run: () => onView("roster") },
    { id: "v-dispatch",  label: "Dispatch new run",icon: IconBolt,      run: onDispatch },
    { id: "v-review",    label: "Go to Review",    icon: IconReview,    run: () => onView("review") },
    { id: "v-telemetry", label: "Go to Telemetry", icon: IconTelemetry, run: () => onView("telemetry") },
  ].filter((c) => !lc || c.label.toLowerCase().includes(lc));

  const matchedAgents = agents.filter((a) =>
    !lc || a.name.toLowerCase().includes(lc) || a.task.toLowerCase().includes(lc) || a.repo.toLowerCase().includes(lc)
  ).slice(0, 8);

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal" style={{ width: 540, top: 80, position: "absolute", left: "50%", transform: "translateX(-50%)" }}
           onClick={(e) => e.stopPropagation()}>
        <div style={{ padding: "14px 18px", borderBottom: "0.5px solid var(--rule)", display: "flex", alignItems: "center", gap: 10 }}>
          <IconCmd size={16} />
          <input
            ref={inputRef}
            placeholder="Find agent, task, repo, command…"
            value={q} onChange={(e) => setQ(e.target.value)}
            style={{ flex: 1, border: 0, background: "transparent", outline: "none", font: "15px var(--sans)", color: "var(--ink)" }}
          />
          <span className="mono" style={{ fontSize: 10, color: "var(--ink-faint)" }}>esc</span>
        </div>
        <div style={{ padding: "8px 0", maxHeight: 380, overflowY: "auto" }}>
          {cmds.length > 0 && (
            <>
              <div className="nav-section" style={{ padding: "8px 18px 4px" }}><span>Commands</span><span className="line" /></div>
              {cmds.map((c) => {
                const I = c.icon;
                return (
                  <div key={c.id} className="nav-item" style={{ margin: "0 8px" }}
                       onClick={() => { c.run(); onClose(); }}>
                    <div className="icon"><I size={13} /></div>
                    <span>{c.label}</span>
                  </div>
                );
              })}
            </>
          )}
          {matchedAgents.length > 0 && (
            <>
              <div className="nav-section" style={{ padding: "12px 18px 4px" }}><span>Agents</span><span className="line" /></div>
              {matchedAgents.map((a) => (
                <div key={a.id} className="nav-item" style={{ margin: "0 8px" }}
                     onClick={() => onPickAgent(a.id)}>
                  <div className="icon"><span className={"pulse " + a.status} /></div>
                  <span>{a.name}</span>
                  <span className="count" style={{ marginLeft: 8, color: "var(--ink-faint)", flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                    {a.task.slice(0, 50)}
                  </span>
                </div>
              ))}
            </>
          )}
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────
// Tweaks panel
// ─────────────────────────────────────────────────────────

function SkogaTweaks({ t, setTweak }) {
  return (
    <TweaksPanel title="Tweaks">
      <TweakSection label="Appearance" />
      <TweakToggle label="Dark mode (forest at dusk)" value={t.dark}
                   onChange={(v) => setTweak("dark", v)} />
      <TweakColor label="Accent" value={t.accent}
                  options={["forest", "ember", "amber", "dusk"]}
                  onChange={() => {}} />
      {/* hand-rolled accent picker since options are tokens, not hex */}
      <div className="twk-row">
        <div className="twk-chips" role="radiogroup">
          {Object.entries(PALETTES).map(([k, p]) => (
            <button key={k} type="button" className="twk-chip"
                    data-on={t.accent === k ? "1" : "0"}
                    title={p.name}
                    style={{ background: `oklch(0.46 0.085 ${p.hue})` }}
                    onClick={() => setTweak("accent", k)}>
              {t.accent === k && (
                <svg viewBox="0 0 14 14" aria-hidden="true" style={{ position: "absolute", top: 6, left: 6, width: 13, height: 13, filter: "drop-shadow(0 1px 1px rgba(0,0,0,.3))" }}>
                  <path d="M3 7.2 5.8 10 11 4.2" fill="none" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" stroke="#fff" />
                </svg>
              )}
            </button>
          ))}
        </div>
      </div>

      <TweakSection label="Roster" />
      <TweakRadio label="Layout" value={t.layout}
                  options={[{ value: "cards", label: "Cards" }, { value: "table", label: "Table" }, { value: "list", label: "List" }]}
                  onChange={(v) => setTweak("layout", v)} />
      <TweakSlider label="Agents" value={t.agentCount} min={3} max={20} step={1}
                   onChange={(v) => setTweak("agentCount", v)} />

      <TweakSection label="Type" />
      <TweakRadio label="UI font" value={t.font}
                  options={[{ value: "mixed", label: "Mixed" }, { value: "mono", label: "All-mono" }]}
                  onChange={(v) => setTweak("font", v)} />
    </TweaksPanel>
  );
}

Object.assign(window, { App, CommandPalette, SkogaTweaks });
