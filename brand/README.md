# Skoga Brand Pack

Visual identity for **Skoga** and its mascot **Kongle** — a little evergreen who
watches over your team of agents. (Kongle is Norwegian for "pinecone"; he is,
technically, a conifer. That's the joke.)

Open **brand-guide.html** in a browser for the full overview.

## Contents
- `01-logo/` — horizontal, stacked & reversed lockups + wordmark only.
  The wordmark is **outlined vector paths** (Newsreader 500), so the logo never
  depends on a font loading.
- `02-mascot/` — canonical Kongle + an `expressions/` set (happy, focused,
  winking, waving, sleeping, celebrating).
- `03-icons/` — app icon (primary + reversed), simplified favicon, and
  `png/` exports at 512 / 180 / 32 / 16.
- `04-animations/` — standalone animated SVGs (coffee sip, on-the-job,
  waving, celebrating, napping). Pure SMIL, no JS.
- `fonts/` — Newsreader (variable TTF) under the SIL Open Font License.

## Color
Linen `#ece6d6` · Ink `#1a1812` · Forest `#1a5530`
Forest deep `#123c22` · Forest light `#2c6b41` · Sprout `#3d8757`
Accents: Ochre `#c97f4a` · Rust `#b5532f` · Gold `#d8a23a`

## Type
Headings: Newsreader · Body/UI: IBM Plex Sans · Code: JetBrains Mono

## Notes
- Icons: use the detailed mark down to ~40px; switch to the simplified
  (faceless) mark at 32px and below.
- Animations: gate behind `prefers-reduced-motion` and fall back to the
  matching static expression.
- Don't recolor, rotate, stretch, or add effects to the logo. Keep clear space
  equal to the height of Kongle's sprout.
