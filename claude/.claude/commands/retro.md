---
description: "Post-mortem for a finished branch/PR — measure where the time actually went, separate real work from friction, and render a bilingual HTML retrospective"
argument-hint: "[branch|PR#]  (no args = current branch)"
---

# Retro: where did this task's time actually go?

Produce an evidence-backed retrospective for a completed (or nearly completed)
branch. The deliverable is a bilingual HTML report; the value is the honest
accounting of **why the wall clock looks the way it does**.

**Terminal language:** match Mike. **No Mermaid in terminal** — ASCII only
(Mermaid is fine inside the HTML and in GitHub posts).

This command is retrospective, not exploratory. If the branch is mid-flight
with unpushed work, say so and offer to run after it lands — half-finished
work produces a misleading commit-timestamp analysis.

## The rule that makes these honest

**Every claim carries its number, and every number carries its source.** If you
cannot attach a measurement, it goes in §Provenance as *derived* or *open*, never
in the body as fact. A retro that flatters the work is worthless — the friction
section is the point.

## Step 1 — measure, before writing a word

```bash
BR=$(git --no-optional-locks branch --show-current)

# commit shape
git log --no-merges --format='%h|%ad|%s' --date=format:'%m-%d %H:%M' origin/main..HEAD | tac
git log --no-merges --format='%s' origin/main..HEAD | awk -F: '{print $1}' | sed 's/(.*//' | sort | uniq -c | sort -rn
git diff --stat origin/main...HEAD | tail -1
```

**Real work vs calendar time** — the single most important number. Sum the gaps
between consecutive commits, discarding any gap > 2 h as "not working":

```python
# gaps > 2h are pauses (sleep, other tasks), not effort
total = sum(d for d in deltas if d <= timedelta(hours=2))
```

Report BOTH: calendar span and actual work. A 15-hour span that is 6 hours of
work is a completely different story from 15 hours of grinding, and the raw
span alone always tells the wrong one.

**Caveat it explicitly:** commit timestamps are a proxy for effort, not a time
sheet. Say that in §Provenance.

## Step 2 — classify the commits

The `fix:` ratio is the headline finding of most retros:

| Prefix | Meaning |
|--------|---------|
| `feat` / `refactor` / `perf` | forward progress |
| `fix` | **correcting our own work** |

A high `fix:` share is not automatically bad — it usually means review caught
things before users did. Say which it was, with evidence: for each `fix:`
commit, name what found it (bot, review agent, live test, user report).

## Step 3 — reconstruct the problems

Sources, in order of reliability:

1. `.superpowers/sdd/<plan>/progress.md` if it exists — the ledger is written
   contemporaneously and survives compaction. Trust it over recollection.
2. PR + mirror-PR review threads: `gh api graphql` for `reviewThreads`, and
   `gh pr view <n> --json comments`.
3. The session transcript, if still in context.

For each problem, capture four things — a list of "we hit some issues" is not a
retro:

- **What was wrong** (one sentence)
- **Who or what found it** — self, bot, agent, live test, user
- **Why it was invisible** — this is the reusable insight
- **Whether it would have shipped**

Mark separately any defect found by **two independent checkers converging on the
same line by different routes**. That convergence is the strongest signal a
retro can surface, and it justifies redundant review to anyone asking why it
costs what it costs.

## Step 4 — separate friction from work

Split the time into three honest buckets:

- **Productive** — building, reviewing, fixing real defects.
- **Structural cost** — unavoidable given the architecture. Deploy latency for
  anything that can't run locally; auth that needs a human (MFA); waiting on CI.
  Name the architectural fact that forces it.
- **Pure friction** — produced nothing. Broken tooling, false test passes,
  environment surprises, chasing phantoms from mangled output, work redone
  because a check silently didn't run.

The friction bucket must be written even when it is unflattering, and
especially when the cause was your own mistake. A retro that hides its own
false starts teaches nobody anything.

## Step 5 — turn findings into rules

For each recurring problem ask: **would a written rule have prevented this?**

- Yes, and it generalises → propose a concrete addition to the repo's
  `CLAUDE.md` (or the user's memory). Quote the exact wording you propose.
- Yes, but only here → propose a justfile recipe or a documented setup step.
- No → say so. Not every problem has a rule-shaped fix, and inventing one adds
  noise to a file everyone has to read.

Show proposed `CLAUDE.md` edits as a draft and wait for a go before writing —
it is a checked-in file that changes how every future session behaves.

## Step 6 — render the HTML

Use the house template (never redesign it):

```bash
cp ~/dotfiles/claude/.claude/scripts/report/template.html <OUT>/<slug>-<YYYY-MM-DD>.html
```

Default `<OUT>`: `~/zettelkasten/claude_code/<repo>/architecture/`.

Fill `{{TITLE}}`, `{{H1_EN}}`, `{{H1_UA}}`, `{{SUBTITLE}}`, `{{SECTIONS}}`,
`{{EXTRA_CSS}}`. Generate the sections from a small Python script rather than
hand-writing HTML — bilingual span pairs are mechanical and easy to get wrong
by hand.

**Section order:**

1. **Verdict box** (`.verdict`, before section 1) — the answer in 1–3 sentences.
2. **The facts** — `.cards` + `table.kv`: ticket, PR, commits, files, languages,
   and the calendar-vs-actual time pair. Mark the actual-work row `.hlg`.
3. **Why it broke** — ASCII causality in `.flow > pre`, the divergence marked
   `.hl`. Skip if the branch was a feature, not a fix.
4. **What was built** — the architecture as ASCII, plus a `table.kv` of the
   numbers that matter (timeouts, thresholds) and where each is derived from.
5. **Why it took as long as it did** — the core section. One `<h3>` per reason,
   each with its measurement. Use a `.bar` for the commit-type split.
6. **What the review layers caught** — `.optgrid`, one `.opt` per checker, and
   mark convergence `.opt.rec`.
7. **Evidence** — `pre.raw` with untrimmed logs, request ids, durations.
8. **Provenance & limits** — non-negotiable. Split **directly observed** from
   **derived** from **still open**.

Every prose node carries both languages:

```html
<span data-en>…</span><span data-ua>…</span>
```

Identifiers, log lines, code and `file:line` stay untranslated. The Ukrainian is
a real translation for an engineer, not a gloss.

## Step 7 — serve and VERIFY

`<OUT>` is under `~/zettelkasten/claude_code/`, so the ONE bun hub on fixed :8890
already serves it with live-reload. Do NOT spawn a `python -m http.server`; just
make sure the hub is up:

```bash
just -g hub-fix        # frees :8890 from any squatter + (re)starts the one bun hub
```

Then verify in a real browser with Playwright MCP — do not claim it works
without this. Check, at 760 px viewport:

```js
document.documentElement.scrollWidth > document.documentElement.clientWidth  // must be false
```

…in **both** languages (UA text is longer and overflows where EN does not), plus
both themes and all three download buttons. Wide tables must scroll inside their
own `.tl-wrap`, never the page — a bare `<table class="tl">` will drag the whole
page sideways.

Report the hub URL: `http://$(ipconfig getifaddr en0):8890/${OUT#*/zettelkasten/claude_code/}<file>` (persistent; `just -g hub-fix` revives it).

## Style rules

- **Numbers beat adjectives.** "6 h 25 min of 15 h 22 min" — not "took a while".
- **Answer first.** The verdict box before any narrative.
- **Own the mistakes by name.** If a check was claimed but never ran, say so
  plainly in the friction table and mark it `.hl`. That row is the most useful
  one in the document.
- **Never truncate evidence** — no `...` in `pre.raw`.
- **Say what you could not prove.** A stated limit beats a confident guess.

## Afterwards

Offer — do not do unprompted — to:
- save a companion `.md` next to the HTML with the findings in prose,
- post an English summary to the PR or Linear issue (show the draft, wait for an
  explicit go),
- apply the proposed `CLAUDE.md` rules.
