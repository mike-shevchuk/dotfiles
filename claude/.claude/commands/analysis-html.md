---
description: Render a technical investigation (incident root-cause, latency/cost measurement, codebase pattern sweep) as a bilingual EN/UA HTML report in the house style, served over LAN. Use after digging through prod logs, metrics, or the codebase and needing to present findings.
argument-hint: "<topic or ticket> [--lang eng|ukr|both] [--out <dir>]"
---

# /analysis-html

Turn an investigation you have **already done** into a house-style HTML report.

`$ARGUMENTS` names the subject (ticket id, incident, sweep topic). Optional:
`--lang` (default `both`), `--out` (default `~/zettelkasten/claude_code/<repo>/alerts/`).
The `--out` dir MUST be under `~/zettelkasten/claude_code/` so the one bun hub
(`jg hub`, fixed :8890) serves it — no per-report port.

This command does **not** do the investigation. Do the digging first. If you have
no evidence yet, say so and stop — a report with nothing measured is the one
failure mode this command cannot fix.

## The rule that makes these reports good

**Every claim carries its evidence, inline.** A log line, a `file:line`, a
measured delta. If you cannot attach evidence to a sentence, it goes in
§Provenance as an open question — never in the body as an assertion.

## Step 1 — gather (before writing any HTML)

Collect and keep the raw material; you will paste it verbatim later:
- log lines with their **UTC timestamps and source log group**
- the identifiers that make it checkable: operation/alert/request ids, device ids, account
- `file:line` for every code claim — read the actual lines, don't cite from memory
- retention / permission limits you hit

## Step 2 — build the page from the template

```bash
cp ~/dotfiles/claude/.claude/scripts/report/template.html <OUT>/<slug>-<YYYY-MM-DD>.html
```

Fill `{{TITLE}}`, `{{H1_EN}}`, `{{H1_UA}}`, `{{SUBTITLE}}`, `{{SECTIONS}}`, `{{EXTRA_CSS}}`.
The template already carries the house CSS, 🤖 favicon, the `☰` burger and the
control script. **Never redesign it** — new visual needs go in the `{{EXTRA_CSS}}`
block. Reports must look like siblings of the existing ones in
`~/zettelkasten/claude_code/rescue-serverless/alerts/`.

**What the `☰` burger carries (all persisted in `localStorage`, all inherited free — never re-implement these per report):**
- **Language** — EN/UA toggle (`rep:ua`).
- **Theme** — 5 themes; **default is Nord** (`rep:theme`, falls back to `nord`). Dark/Light/Nord/Dracula/Solarized.
- **Layout** — live sliders for **Width** (`--wrap-w`), **Side padding** (`--wrap-px`) and **Font size** (`--fs`), persisted as `rep:ww`/`rep:wpx`/`rep:fs`.
- **Blocks** — **Collapse all** / **Expand all** / **Reset layout & sizes**.
- **Download HTML** — both / UA-only / EN-only export.

**Every `<h2>` section is automatically collapsible + resizable.** The script wraps
each section body in a `.blk` (drag its bottom edge to resize — `rep:h:<id>`; click
the heading to collapse — `rep:col:<id>`, keyed by the `h2` `id`, so give every `h2`
a stable `id` like `s1`…`sN`). Standout blocks (`.hero`, `.verdict`, `.callout`,
`.flow`, `.tl-wrap`, `pre.raw`, `pre.diff`) are resizable too. Author plain
`<h2 id="sN">…</h2>` + content; do not hand-roll collapse/resize markup.

**Every panel carries a hover icon toolbar (＋ fit · ⤢ full · ▾ collapse · ✕ close · ↺ reset), all remembered.**
`＋` fit enlarges the panel **in place** (full row width + taller, stays in the flow — `.pfit`, `st.f`); `⤢` full is the fixed overlay maximize.
The script adds it to `.ecard`, `.hero`, `.verdict`, `.callout` (extend the `SEL`
list in the script for more), and the panel is corner-resizable. State persists per
block under `rep:pk:<key>` (`{c,x,w,h}`) — give a stable key with `data-pk="…"` on
the element (falls back to `class-index`). A resized panel that is a flex child
gets `.psized` (`flex:0 0 auto`) so `flex-grow` stops snapping its width back —
without it, a grid/flex card cannot hold or save a dragged width. Collapse keeps the panel's first child
(header) visible; reserve room for the toolbar in a panel's own header, e.g.
`.ecard.pchrome .ehd{padding-right:116px}`. The burger's **Reset layout & sizes**
also reopens closed panels and clears their remembered state.

## Step 3 — the section contract

Numbered `N · Title` sections, in this order. Skip one only when the
investigation genuinely produced nothing for it, and say so in §Provenance.

**Verdict box first** (`.verdict`, before section 1) — the answer in 1–3
sentences. What broke, why, how bad. The reader must be able to stop here.

1. **The facts.** `.cards` + `table.kv`. The immutable, checkable identifiers —
   ids, timestamps, versions, orgs. Two competing things (emergency #1 vs #2,
   cold vs warm)? Two `.card`s side by side, with the discriminating row marked
   `.hl`.
2. **Cost at each hop.** A Δ table: hop, absolute t, `+Δ`, what happened, cost.
   This is where the reader sees *which* hop is the problem. Mark the bad hop
   `.hl`, healthy ones `.hlg`.
3. **Why (root cause).** The core section. An ASCII causality diagram in
   `.flow > pre` showing how one input became the wrong output — branches,
   the moment it diverges, which guard was supposed to catch it and why it
   missed. Colour the divergence with `.hl`. Prose underneath names the exact
   mechanism, with `file:line`.
4. **How to fix.** `.optgrid` of options, each with `+`/`−` (`li.plus`/`li.minus`)
   and its measured or estimated effect; mark the recommended one `.opt.rec`.
   Then `.plan` steps in rollout order. Fix at the source, not per-symptom.
5. **Raw evidence.** `table.tl` inside `.tl-wrap`: one row per log line —
   `t (UTC)`, `Δ`, `service`, `log line`. Colour rows by actor/stream
   (`r-sub`/`r-e1`/`r-e2`/`r-res`/`r-other`) and add a `.legend`. Then the
   **full untrimmed dump** in `pre.raw`, headed with account, role, log groups.
6. **Data provenance & limits.** Non-negotiable. Source account + role + log
   groups. Retention that cost you data. What you could **not** access and why.
   And explicitly: which conclusions are **directly observed** vs **proven by
   elimination** vs **still open**. This section is what makes the rest
   trustworthy — write it even when it is unflattering.

## Step 3b — the design / change-analysis variant

The section contract above is incident-shaped. When the report argues for a
**change** (a design proposal, a migration, "how do we do X and roll it back"),
keep the evidence discipline but reshape the sections — and reach for the richer
component set below. A design report that reads as informative as the best ones
(`pun1678-notify-to-rescue-conversion`) uses this order:

0. **Context** — what the thing *is*, in prose. A reader who has never seen the
   subsystem must be able to follow. One `.callout.info` stating what the ticket wants.
1. **The two (or N) states, field by field** — `.cards` side by side + a
   per-field **deep-dive** (`.deep .row`: one card per field, name in mono, one
   paragraph on what it is and why it matters to the change).
2. **How they behave differently at runtime** — a table of branch points with
   `file:line`, so QA knows what the change silently flips.
3. **The measured data** — a census / real counts (`.cmp` big numbers + `.barrow`
   bars). Surface any *live* inconsistency here; a real broken record beats a
   hypothetical.
4. **Why the naive version breaks** — the ASCII `.flow > pre` mechanism, plus a
   `.callout.danger` naming the precise trap.
5. **Lifecycle** — a small `.life` diagram of the state transitions the change adds.
6. **Options & a scored decision matrix** — `.optgrid` for the options, then a
   `table.matrix` scoring them per criterion with `.scorebar` bars and a bold total.
7. **Worked BEFORE / AFTER on a REAL record** — the section that makes it land.
   See below; never skip it for a change report.
8. **Risk register & open questions** — a table (risk → if unhandled → mitigation)
   and an explicit `.callout.info` list of decisions still owed to the reader.
9. **Raw evidence** and 10. **Provenance** as in the incident contract; close with
   a **Glossary** (`dl.gloss`) for every non-obvious field/term.

Add a **hero header** (`.hero` with an `.eyebrow`, `.lead`, a `.metabar` of chips,
and a `.sev` severity meter), a **table of contents** (`.toc` with anchor links to
`#s0…#sN`), and **numbered section badges** (`h2 .n`). These are navigation, not
decoration — a report past ~6 sections is hard to present without them.

### The worked BEFORE/AFTER (the highest-value section)

Pull **one real record** from the live system (read-only) and show the chosen
method applied to it:

1. **BEFORE** — the real item as plain JSON in `pre.raw`, unwrapped (no DynamoDB
   `S`/`N` wrappers), zero info loss. Pick a record that also exercises an edge
   (e.g. the one row on the provider value that must be reset).
2. **N-state side-by-side** — `table.ba` with a column per state
   (BEFORE / AFTER-forward / AFTER-rollback), each cell colour-coded
   `.rm` (removed, red) / `.set` (written, green) / `.same` (grey); tint the
   snapshot rows.
3. **Each transition as a git-style diff** — `pre.diff` with `.add` / `.del` /
   `.chg` / `.cmt` lines, one per field, each ending in a `# why` comment.
4. Close with a `.callout.ok` **"zero collateral change"** — list exactly which
   fields move and assert everything identity-bearing is byte-for-byte identical.

### Component library — paste into `{{EXTRA_CSS}}` (template stays untouched)

All of these are theme-safe (built only from the template's `var(--…)` tokens), so
they render correctly in all five themes. Copy the ones you use:

```css
/* hero + metabar + severity meter */
.hero{position:relative;background:linear-gradient(135deg,var(--panel),var(--panel2));border:1px solid var(--bd);border-radius:16px;padding:22px 26px;overflow:hidden}
.hero::before{content:"";position:absolute;left:0;top:0;bottom:0;width:5px;background:linear-gradient(180deg,var(--acc),var(--pur))}
.hero .eyebrow{font:700 11px ui-monospace,monospace;letter-spacing:.14em;text-transform:uppercase;color:var(--acc)}
.hero .lead{color:var(--mut);max-width:74ch}
.metabar{display:flex;flex-wrap:wrap;gap:8px;margin-top:16px}
.meta{display:inline-flex;gap:6px;background:var(--bg);border:1px solid var(--bd);border-radius:20px;padding:4px 13px;font-size:12px}.meta b{color:var(--acc)}
.sev{display:flex;align-items:center;gap:12px;margin:16px 0 4px}
.sev .track{flex:1;height:11px;border-radius:6px;background:linear-gradient(90deg,var(--grn),var(--org) 55%,var(--red));position:relative}
.sev .track>i{position:absolute;top:-4px;width:4px;height:19px;background:var(--tx);border-radius:2px;box-shadow:0 0 0 2px var(--bg)}
/* table of contents + numbered section badges */
.toc{background:var(--panel);border:1px solid var(--bd);border-radius:12px;padding:14px 18px;margin:16px 0}
.toc ol{margin:0;padding:0;list-style:none;columns:2;column-gap:26px}@media(max-width:640px){.toc ol{columns:1}}
.toc a{text-decoration:none;color:var(--tx);display:flex;gap:8px}.toc a:hover{color:var(--acc)}.toc a .num{color:var(--acc);font:700 12px ui-monospace,monospace;min-width:20px}
h2{scroll-margin-top:60px}
h2 .n{display:inline-flex;align-items:center;justify-content:center;width:29px;height:29px;border-radius:9px;background:var(--acc);color:var(--bg);font:800 14px ui-monospace,monospace;margin-right:11px;vertical-align:middle}
/* callouts (info/warn/danger/ok) */
.callout{border:1px solid var(--bd);border-left-width:4px;border-radius:11px;padding:13px 17px;margin:15px 0;font-size:13.6px;background:var(--panel)}
.callout .ct{font-weight:800;display:block;margin-bottom:5px}
.callout.info{border-left-color:var(--acc)}.callout.info .ct{color:var(--acc)}
.callout.warn{border-left-color:var(--org)}.callout.warn .ct{color:var(--org)}
.callout.danger{border-left-color:var(--red)}.callout.danger .ct{color:var(--red)}
.callout.ok{border-left-color:var(--grn)}.callout.ok .ct{color:var(--grn)}
/* per-field deep-dive */
.deep{display:grid;gap:10px;margin:12px 0}
.deep .row{background:var(--panel);border:1px solid var(--bd);border-radius:10px;padding:12px 15px}
.deep .row .fn{font-family:ui-monospace,Menlo,monospace;color:var(--pur);font-weight:700}
/* decision matrix + score bars */
table.matrix td.win{color:var(--grn);font-weight:700}table.matrix td.lose{color:var(--red);font-weight:700}table.matrix td.mid{color:var(--org);font-weight:700}
table.matrix tr.total td{border-top:2px solid var(--bd);font-weight:800}
.scorebar{display:inline-block;width:60px;height:8px;border-radius:4px;background:var(--panel2);border:1px solid var(--bd);overflow:hidden;vertical-align:middle}.scorebar>i{display:block;height:100%}
/* lifecycle strip */
.life{display:grid;grid-template-columns:1fr auto 1fr auto 1fr;align-items:center;gap:8px;margin:14px 0;font-size:12.5px}@media(max-width:720px){.life{grid-template-columns:1fr;text-align:center}}
.life .st{background:var(--panel);border:1px solid var(--bd);border-radius:11px;padding:13px 15px}.life .arr{color:var(--mut);font:700 20px ui-monospace,monospace;text-align:center}
/* git-style JSON diff */
pre.diff{background:#010409;border:1px solid var(--bd);border-radius:10px;padding:14px;overflow:auto;font-size:11.5px;line-height:1.65;color:#adbac7;font-family:ui-monospace,Menlo,monospace}
:root.light pre.diff{background:#f6f8fa;color:#1f2328}
pre.diff .add{color:#7ee787;background:rgba(63,185,80,.13);display:block}
pre.diff .del{color:#ffa198;background:rgba(248,81,73,.13);display:block}
pre.diff .chg{color:#e3b341;background:rgba(210,153,34,.13);display:block}
pre.diff .cmt{color:var(--mut);display:block}
/* N-state before/after table (wrap in .ba-wrap{overflow-x:auto} like .tl-wrap) */
table.ba td.f{white-space:nowrap;font-family:ui-monospace,Menlo,monospace;color:var(--pur)}
table.ba .rm{color:var(--red);font-weight:700}.ba .set{color:var(--grn);font-weight:700}.ba .same{color:var(--mut)}
table.ba tr.snap td{background:rgba(88,166,255,.06)}
/* glossary */
dl.gloss{display:grid;gap:8px;margin:12px 0}
dl.gloss div{background:var(--panel);border:1px solid var(--bd);border-radius:9px;padding:10px 14px}
dl.gloss dt{font-family:ui-monospace,Menlo,monospace;color:var(--pur);font-weight:700}
```

Two hard rules carry over: **the template file itself is never edited** (every new
component lives in `{{EXTRA_CSS}}` and is built only from `var(--…)` tokens so all
five themes keep working), and **wide tables scroll inside their own wrapper**
(`.ba-wrap`, `.lam-wrap`, `.tl-wrap`) — never the page. Verify both, plus the
before/after diffs render coloured, in the Step 5 browser pass.

## Step 4 — bilingual

Every prose node carries both languages:

```html
<span data-en>The watchdog only fires on a pair that reported nothing.</span><span data-ua>Watchdog спрацьовує лише для пари, яка не звітувала нічого.</span>
```

Log lines, identifiers, code and `file:line` stay untranslated. The UA text is a
real translation for an engineer, not a gloss — keep the technical register.

## Step 5 — serve + verify

**Do NOT spawn a `python -m http.server`.** That was the old per-page sprawl. The
file already lives under `~/zettelkasten/claude_code/`, and ONE bun hub on fixed
**:8890** serves that whole tree with live-reload. Just make sure the one hub is up:

```bash
just -g hub-fix        # frees :8890 from any squatter + (re)starts the one bun hub
```

Then **prove the file is reachable before you hand over the URL** — its path under
the hub root IS the URL path:

```bash
REL="${OUT#*/zettelkasten/claude_code/}<file>"   # path relative to the hub root
curl -s -o /dev/null -w "%{http_code}\n" "http://$(ipconfig getifaddr en0):8890/$REL"
```

Anything but `200` means stop and diagnose — usually the file isn't under the hub
root (`~/zettelkasten/claude_code/…`), or the hub isn't up (rerun `just -g hub-fix`).

Then verify in a real browser before claiming it works — open it with Playwright
MCP and confirm: both languages toggle, both themes toggle, and at 760 px there
is **no horizontal page scroll** (`document.documentElement.scrollWidth >
clientWidth` must be `false`; wide tables scroll inside their own
`.tl-wrap`/`.lam-wrap`, never the page).

Report the hub URL: `http://$(ipconfig getifaddr en0):8890/$REL`. The hub is
persistent (bun in tmux session `hub`); the report file is permanent under the hub
root, and if a link ever 404s, `just -g hub-fix` brings the hub back — a later
"it doesn't work" means a stopped hub, not a lost report.

## Style rules

- **Answer first.** Verdict before investigation. Never build suspense.
- **Numbers beat adjectives.** `+105.9s`, `24 s cold vs 6.9 s warm`, `3/3 TIMED_OUT` —
  not "significantly slower". Use `.cmp` big-number boxes for the headline pair.
- **Severity is a score.** Colour emoji *and* number: `🔴 84/100`, `🟠 71/100`.
- **Never truncate evidence.** No `...` in `pre.raw`. The full dump is the point.
- **Say what you could not prove.** A limit stated plainly is worth more than a
  confident guess, and the reader will find the guess anyway.
- Terminal-facing text stays ASCII; Mermaid belongs in `.md` docs, not here — in
  these reports causality is ASCII inside `.flow > pre`.

## Afterwards

Offer to save the companion `.md` note next to the HTML (same slug) with the
findings in prose, and to post an English summary to the Linear issue or PR —
but **show the draft and wait for an explicit go** before anything is posted.
