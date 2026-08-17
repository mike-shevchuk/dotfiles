---
description: Render a technical investigation (incident root-cause, latency/cost measurement, codebase pattern sweep) as a bilingual EN/UA HTML report in the house style, served over LAN. Use after digging through prod logs, metrics, or the codebase and needing to present findings.
argument-hint: "<topic or ticket> [--lang eng|ukr|both] [--out <dir>] [--port N]"
---

# /analysis-html

Turn an investigation you have **already done** into a house-style HTML report.

`$ARGUMENTS` names the subject (ticket id, incident, sweep topic). Optional:
`--lang` (default `both`), `--out` (default `~/zettelkasten/claude_code/<repo>/alerts/`),
`--port` (default `8899`).

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
mkdir -p <OUT>
cp ~/dotfiles/claude/.claude/scripts/report/template.html <OUT>/<slug>-<YYYY-MM-DD>.html
```

Fill `{{TITLE}}`, `{{H1_EN}}`, `{{H1_UA}}`, `{{SUBTITLE}}`, `{{SECTIONS}}`.
The template already carries the house CSS, 🤖 favicon, sticky EN/UA + theme bar,
and the toggle script. **Never redesign it** — new visual needs go in the
`{{EXTRA_CSS}}` block. Reports must look like siblings of the existing ones in
`~/zettelkasten/claude_code/rescue-serverless/alerts/`.

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

## Step 4 — bilingual

Every prose node carries both languages:

```html
<span data-en>The watchdog only fires on a pair that reported nothing.</span><span data-ua>Watchdog спрацьовує лише для пари, яка не звітувала нічого.</span>
```

Log lines, identifiers, code and `file:line` stay untranslated. The UA text is a
real translation for an engineer, not a gloss — keep the technical register.

## Step 5 — serve + verify

**Never `pkill` a port you did not start.** Other report servers live on these
ports, each serving a *different* directory — killing one silently breaks
somebody's open tab. A port being busy tells you nothing about which directory it
serves, so claim a free one instead:

```bash
for P in <PORT> 8898 8897 8896; do
  lsof -nP -iTCP:$P -sTCP:LISTEN >/dev/null 2>&1 || { PORT=$P; break; }
done
cd <OUT> && nohup python3 -m http.server $PORT --bind 0.0.0.0 >/dev/null 2>&1 &
```

Then **prove the file is reachable before you hand over the URL** — a server on
the right port serving the wrong directory 404s while looking perfectly healthy:

```bash
# Resolve the IP of whichever interface holds the default route (en0 wired, en1 Wi-Fi, …).
LAN_IP=$(ipconfig getifaddr "$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')")
curl -s -o /dev/null -w "%{http_code}\n" "http://$LAN_IP:$PORT/<file>"
```

Anything but `200` means stop and diagnose — the usual cause is a pre-existing
server whose cwd is a sibling directory (`lsof -a -p <pid> -d cwd -Fn` shows it).

Then verify in a real browser before claiming it works — open it with Playwright
MCP and confirm: both languages toggle, both themes toggle, and at 760 px there
is **no horizontal page scroll** (`document.documentElement.scrollWidth >
clientWidth` must be `false`; wide tables scroll inside their own
`.tl-wrap`/`.lam-wrap`, never the page).

Report the LAN URL: `http://$LAN_IP:<PORT>/<file>` (from the `LAN_IP` resolved above).

**Say that the server is session-scoped.** It dies when the session ends, so a
URL handed over today is dead tomorrow. The report file itself is permanent —
reviving it is one `python3 -m http.server` from `<OUT>`. Mention this once,
alongside the link, so a later "it doesn't work" is understood as a dead server
and not a lost report.

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
