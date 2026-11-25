---
description: "Audit of everything Mike asked for: what each ask was, what was done, proof, owner, blockers, progress bars + predicted times, and the next commands in order. /mike-audit [today|week|<topic|PR|PUN>]"
argument-hint: "[today|week|<PR#|PUN-x|word>]  (no args = today)"
---

# /mike-audit — що Mike просив → що зроблено, хто блокує, що далі

Mike 06.11: «я хочу бачити аудит лог високого рівня, щоб я знав, чи виправив ти те, що я кидав, і наступні команди з прогресбаром та предікт час»; «зроби таку команду … більше деталей, прогресбар, предікт час, блокери і так далі»; «щоб було трохи більше опису».
Chat: Ukrainian, terms stay English. Everything from LIVE sources — never from memory of earlier turns.

## Source of truth
- `~/.claude/fleet-board/<week>/mike-asks-audit.md` — one row per thing Mike asked (the ask in his words, short).
  **The lead appends a row the moment Mike asks for something** (fix X, check Y, change rule Z) and updates its status when it changes.
  `<week>` = newest `~/.claude/fleet-board/w*` dir with that file (or the current tmux session lowercased).
- Live facts to verify each row (never trust the row's old status):
  - PR state: `gh pr view <N> --json state,mergeable,mergeStateStatus,headRefOid,mergeCommit` (rescue-serverless / workflow-engine `WE#N`).
  - Gates: `~/.claude/pipeline-stamp.sh gates only=<N>`.
  - Mike approval / lead preflight: `~/.claude/demo-result.sh check <N>` and `check <N> --preflight` (engine PRs: key `eng-<N>`).
  - Dev: last deploy `gh run list -R back2back-team/rescue-serverless -w 165841775 -L 3` (status, train branch), `~/.claude/fleet-board/train-current.txt` (which PR heads are on dev), `<board>/dev-freeze.txt`.
  - Fixture lock: `/tmp/b2b-dev-fixture.lock.d/*` (who runs a try now); `<board>/preflight-queue.txt`.
  - Windows: `tmux capture-pane` of the owner window → its `📍` line (what it is doing / waiting on).
  - Linear status only if a row is about Linear.
  - Measured durations: try length from the newest `~/.cache/try-logs/<recipe>-*.log` (name timestamp → mtime); deploy = median of the last successful deploy runs.

## Step 0 — the page (Mike 06.11 «виглядає не супер професійно» → real page, not a terminal box)
Run `python3 ~/.claude/fleet-board/bin/mike-audit-html.py <week>` → `~/zettelkasten/claude_code/rescue-serverless/fleet/w<week>-audit.html`,
served at `http://mac.local:8890/rescue-serverless/fleet/w<week>-audit.html` (if :8890 is down: `just -g hub-up`). Give Mike the link first.
The page has: KPIs (done / in work / waiting Mike / deferred / dev / lock), 🔀 merge queue one-by-one, 🐛 open Bugbot findings with «виправлено (коміт) / не виправлено», all asks with times, day timeline.
In the terminal print only a SHORT plain summary (no box tables with emoji — they misalign): sections 1, 3 (open items), 4 (blockers as a list), 5, 6, 7.

## Output (in this order)

### 1. Головне одним абзацом
2–3 sentences: how many asks today, how many done, what is the ONE thing that matters next and who it waits on.

### 2. 🧾 Аудит — box table in a code block
One row per ask, newest-important first. Columns (Mike 06.11: «не зручно, що тут годин нема»):
`# · просив HH:MM · що просив (його словами, ≤36 симв.) · статус · зроблено HH:MM · що зроблено (1 рядок простими словами) · доказ (sha/PR/run) · хто далі`
Times: «зроблено» from git commit / GitHub mergedAt / try log (exact); «просив» from the audit file / grill-log (`≈` when approximate). Mike's local time; another day → `05.11 18:00`.

### 2b. 🕒 Стрічка дня — ASCII timeline (визуалізація)
One line per hour from the first ask to now; on each line the asks (`◆ #N`) and completions (`✓ #N`, `⇢ merge #PR`, `🚂 deploy train-x`) at that time, e.g.
```
08:00 ┤ ◆7 xxxxx   ✓7  ⇢ #2437 #1743 #2444
11:00 ┤ ◆2 CI  ◆8 POST-only  ⇢ #2435   ✓8
13:00 ┤ ✓2 #2459  🚂 train-8  ✓4 фікс 500  ⇢ #2442
15:00 ┤ ✓1 Bugbot на dev  ▶ зараз
```
Then one bar of the day: `✅ ████████████░░░░ 13/22 за день`.
Status icons: ✅ зроблено й перевірено наживо · ⏳ у роботі · 🙋 чекає Mike · 🧭 чекає ліда · 🔴 блокер/регресія · ⏸ відкладено за рішенням Mike.
A row is ✅ only if the live check confirms it (merged / commit present on the PR head / rule file exists). If the live check disagrees with the file — fix the file and say so in one line.
Footer line: `✅ N · ⏳ N · 🙋 N · 🧭 N · 🔴 N · ⏸ N`.

### 3. 📝 Деталі по відкритих (⏳ 🙋 🧭 🔴) — 3–5 lines each, plain words
For every not-done row:
- **Що це** — what the ask means for the product / user (one sentence, no jargon without a gloss).
- **Що вже зроблено** — concrete: commit, PR, test, preflight result with commit sha and who ran it (lead vs window agent).
- **Що лишилось** — the remaining steps, in order.
- **Блокер** — who/what blocks it right now (Mike decision · Mike try · lead OK · agent W<N>:<i> · deploy · fixture lock held by <who> · BE dev/FE dev · GitHub) and since when.
- **Ризик** — one line, only if real.

### 4. ⛔ Блокери — box table
`хто блокує · що саме · з якого часу · що розблокує · хто має діяти` — Mike rows first (they are the ones he can clear now).

### 5. 📊 Прогрес і прогноз — per open ask, bars + times
```
<ask short>      ██████░░░░ 60%  <current step>            → ≈HH:MM
```
- 10 cells, % = done steps / total steps of that ask (state the steps if unclear).
- Predicted finish uses measured durations and real dependencies: review gates ∥ deploy; preflight after deploy and after the fixture lock frees (holder's remaining time + tries queued ahead); Mike's try ≈ try length ×2 + 3 min; merge 5 min. Mark «прогноз».
- Show what is already done today with times (`✔ 13:28 деплой train-w44-8 завершено`, `✔ 14:22 preflight WE#86 6/6 (лід, a5f4725)`).

### 6. ▶️ Наступні команди — numbered, in priority order
Each: when it can start (`з ≈HH:MM` or `зараз`), what it proves in one line, how long. The FIRST command in a plain code block between `---` lines (never inside a frame), ready to copy. Only list tries whose lead preflight is ✅ on the current dev and PR head.

### 7. 🙋 Від тебе — numbered actions/decisions for Mike (empty → «нічого не блокує»).

End with `result:` one line.

## Rules
- Read-only: this command never merges, pushes, deploys, posts or edits Linear. It only reads and (if a row is stale) corrects `mike-asks-audit.md`.
- Never call something «✅ виправлено» without the live proof column filled.
- Times are Mike's local time.
