---
name: week-recap
description: "Readable terminal summary of everything you did in a week — per-day commit list, per-PR scoreboard, week-at-a-glance bar chart, and Linear tracking-hygiene gaps"
---

# Week Recap

Trace one work-week of your own git activity and render a readable terminal summary in three layers: **by day**, **by PR**, and a **week-at-a-glance** bar chart, ending with **tracking-hygiene** gaps (work with no Linear PUN). Terminal only — never posts anywhere.

This is the format Mike approved on 2026-05-29. Match it exactly.

## Resolve the week window

The argument is `$ARGUMENTS`. Resolve `START` (Monday 00:00) and `END` (Sunday 23:59, or now if the week is in progress). Platform is macOS — use BSD `date` (`date -v`, `date -j -f`).

- **empty** → current week. `DOW=$(date +%u)` (1=Mon..7=Sun); `START=$(date -v-$((DOW-1))d +%Y-%m-%d)`; `END=now`.
- **`last`** / `минулий` → previous week. Same as above then subtract 7 days from START, END = START+6.
- **`W<NN>`** (e.g. `W21`) → that week of the year, using Mike's convention: **W1 = the first Mon–Sun week of January** (first Monday of the year starts W1), NOT ISO-8601. Compute the first Monday, then `START = first_monday + (NN-1)*7 days`.
- **`<YYYY-MM-DD>..<YYYY-MM-DD>`** → explicit range, used verbatim.

Compute the week number for the header with Mike's convention (per `~/CLAUDE.md`):
```bash
YEAR=$(date -j -f "%Y-%m-%d" "$START" +%Y)
JAN1_DOW=$(date -j -f "%Y-%m-%d" "$YEAR-01-01" +%u)
if [ "$JAN1_DOW" -eq 1 ]; then OFF=0; else OFF=$((8-JAN1_DOW)); fi
FIRST_MON=$(date -j -v+${OFF}d -f "%Y-%m-%d" "$YEAR-01-01" +%Y-%m-%d)
# Day-of-year arithmetic, NOT epoch seconds — a DST transition between FIRST_MON and
# START shifts the second-count by ±1h and silently off-by-ones the week. 10# forces
# base-10 so zero-padded day-of-year (e.g. 089) isn't parsed as octal. START is always
# a Monday in the same year, so day-of-year difference is exact.
DOY_START=$(date -j -f "%Y-%m-%d" "$START" +%j)
DOY_FM=$(date -j -f "%Y-%m-%d" "$FIRST_MON" +%j)
WEEK=$(( (10#$DOY_START - 10#$DOY_FM) / 7 + 1 ))
```
Sanity check (Mike's convention): `2026-04-13 → W15`, `2026-05-25 → W21`.

## Gather data

Resolve the author from git config so the filter follows whoever runs it:
```bash
AUTHOR=$(git config user.name)
git fetch origin --quiet 2>/dev/null
```

Run these in parallel:

**1. Per-day commits** (loop each date START..END, all branches, author-filtered):
```bash
for d in <each YYYY-MM-DD in window>; do
  echo "── $d : $(git log --all --author="$AUTHOR" --since="$d 00:00" --until="$d 23:59" --oneline | wc -l | tr -d ' ') commits ──"
  git log --all --author="$AUTHOR" --since="$d 00:00" --until="$d 23:59" \
    --pretty=format:"  %h %ad %s" --date=format:"%H:%M"
done
```

**2. Merged PRs in the window:**
```bash
gh pr list --author "@me" --state merged --limit 60 \
  --json number,title,mergedAt,additions,deletions,changedFiles \
  --jq ".[] | select(.mergedAt >= \"${START}\" and .mergedAt <= \"${END}T23:59:59Z\") | \"#\(.number) | \(.mergedAt[0:10]) | +\(.additions)/-\(.deletions) | \(.changedFiles)f | \(.title)\""
```

**3. PRs opened in the window (still open):**
```bash
gh pr list --author "@me" --state open --limit 60 \
  --json number,title,createdAt,headRefName,additions,deletions,isDraft \
  --jq ".[] | select(.createdAt >= \"${START}\") | \"#\(.number) | created \(.createdAt[0:10]) | +\(.additions)/-\(.deletions) | draft=\(.isDraft) | \(.headRefName) | \(.title)\""
```
Open PRs created *before* the window are pre-existing work — list them separately under a one-line "(older open PRs, untouched this week)" note, don't fold them into the week's totals.

**4. (optional) Enrich a PR** — only if a PR's intent isn't clear from its title/commits, pull its body + commits + top files:
```bash
gh pr view <N> --json title,state,additions,deletions,changedFiles,body,commits,files \
  --jq '...'   # headline + commits + top-12 files by churn + body
```
Don't enrich every PR — only the ones where the one-liner doesn't explain the *why*.

## Output structure

Render to **terminal stdout**. No Mermaid (per `feedback_no_mermaid_in_terminal.md`) — Unicode box-drawing and ASCII bars only. Tag every code fence with a language. Cite files as `path:line`.

Follow this exact section order.

### 1. Header banner

```
╔══════════════════════════════════════════════════════════════════════════════╗
║  WEEK RECAP — W21 · Mon 2026-05-25 → Fri 2026-05-29                           ║
║  Author: Mike · 112 commits · 8 PR merged · 1 PR opened                      ║
╚══════════════════════════════════════════════════════════════════════════════╝
```
(Commit count includes merge commits — state that if asked. PR counts are window-scoped.)

### 2. 📅 By day

One subsection per day, in order. Days with 0 commits get a single grey line with the reason if known (weekend / holiday — e.g. US Memorial Day = last Monday of May).

For light days (≤5 commits) list every commit as a table row. For heavy days (>5), **group by theme/PUN** (don't dump 40 raw lines) — one bullet per workstream with a ~5-word gist and the PUN, plus which PRs merged that day. Use the day-color emoji by load:
`⬜ 0 · 🟦 1–5 · 🟧 6–20 · 🟥 >20`.

```markdown
## 🟥 Ср, 27 травня — 48 комітів (пік тижня)
**3 PR merged: #1398, #1418, #1432.**
- **Audit пристроїв (PUN-1225)** — ~20 комітів: wrappers, ядро, емісія на ~20 ендпоінтах.
- **Triangulation (PUN-1305)** — 5 code-review фіксів → merge #1398.
- ...
```

For a light day:
```markdown
## 🟦 Вт, 26 травня — 3 коміти
| Коміт | Що | PUN |
|---|---|---|
| `92cd1654` | audit: 2 Bugbot-фікси | PUN-1225 |
```

### 3. 📦 By PR — scoreboard

A monospace fenced block, merged first (sorted by churn, biggest first), then opened-this-week. Align columns. Mark new-from-scratch features with 🆕. Show the PUN or `(без PUN)`.

```text
ЗМЕРДЖЕНО ЦЬОГО ТИЖНЯ (8):
#1398 triangulation conf-radius   +3413/-108   21f  Ср  PUN-1305
#1436 audit DEVICE category        +851/-109   15f  Чт  PUN-1225
#1448 map zones 🆕                  +647/-21    12f  Пт  (без PUN)
...

ВІДКРИТО ЦЬОГО ТИЖНЯ (1):
#1463 offline-latch notifications 🆕 +286/-3   draft=false  Пт  PUN-1358
```

Then, for each non-trivial merged PR, a short prose paragraph: **Проблема → Що зробив → Ключові рішення**. Pull the *why* from the PR body. Keep one-liner PRs (≤10 lines diff) to a single sentence. Lead with the most impactful PR.

### 4. 📊 Week at a glance

ASCII bar chart of commits per day (20-char full bar = the week's max day), then the totals line.

```text
Пн 25  ░░░░░░░░░░░░░░░░░░░░   0   вихідний
Вт 26  ██░░░░░░░░░░░░░░░░░░   3
Ср 27  ████████████████████ 48   ← пік
Чт 28  ███████████████░░░░░ 36
Пт 29  ██████████░░░░░░░░░░ 25
                            ───
                            112 комітів · 8 PR merged · 1 PR відкрито
```

Then a numbered "shipped to main" list (the merged features, most important first) and a "+ у роботі" line for open PRs.

### 5. ⚠️ Tracking-hygiene

Scan commit messages and PR titles/branches for `PUN-\d+`. List every PR or branch with **no PUN** as a gap, plus any feature shipped from scratch that lacks a ticket. This matches Mike's Linear sync habit (`feedback_todoist_linear_sync_check.md`). End by offering to draft Linear tickets for the gaps — but **do not create anything**; creating Linear issues is team-visible, so wait for explicit "go" (`feedback_never_post_without_explicit_go.md`).

```markdown
**Tracking-гігієна:** 2 PR без PUN — **#1448 map-zones** (велика фіча, варто тікет), **#1432 test-policy** (chore). Оформити драфти Linear?
```

## Rendering rules

| Rule | Why |
|---|---|
| Default to Ukrainian prose (Mike's working language) | Terminal chat with Mike is any language; only GitHub posts must be English (`feedback_rescue_serverless_english_only_posts.md`) |
| No Mermaid — Unicode boxes + ASCII bars only | `feedback_no_mermaid_in_terminal.md` |
| Severity/load shown with emoji + number where relevant | `feedback_severity_numeric_score.md`, `feedback_analysis_summary_at_end.md` |
| Heavy days grouped by PUN, not raw-dumped | Readability — 40 commit lines is noise |
| Files cited `path:line`, fences language-tagged | Project tone rule; TUI highlighting |
| JSON only via `jq` | `feedback_jq_format_all_json.md` |
| Lead every summary list with the most important number/decision | `feedback_analysis_summary_at_end.md` |

## Do not

- Do not post anywhere, comment on PRs, or create Linear issues. Terminal render only.
- Do not run `git commit` / `git push` / `gh pr ...` write commands.
- Do not fold pre-existing open PRs (created before the window) into the week's totals.
- Do not dump raw commit lists for heavy days — group by theme/PUN.
- Do not create Linear tickets for tracking gaps without an explicit "go".
- Do not invent PUNs — if a commit/PR has none, report it as a gap.

## Sizing guide

| Week shape | By-day | By-PR prose | Hygiene |
|---|---|---|---|
| Quiet week (<20 commits) | 1 table | 1–2 sentences each | usually clean |
| Normal week (20–80) | grouped + light tables | 4–6 paragraphs | 0–2 gaps |
| Heavy week (>80, many PRs) | all grouped by PUN | 6–8 paragraphs, lead with biggest | list all gaps |

A well-rendered recap fits ~2 screens.
