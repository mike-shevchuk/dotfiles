---
description: "Lead monitor: every 10 min clear the 🧭 lead lane, regenerate tiki, report changes with progress bars + predicted times. /monitor-tiki 2h | on | off | status"
argument-hint: "<Nh|Nm|on|off|status>  (2h = for two hours, on = 2h default, off = stop)"
---

# /monitor-tiki — лід стежить за флотом і пише Mike кожні 10 хв

Mike 06.11: «кожні 10 хвилин протягом 2 годин пиши мені про зміни і оновлюй tiki, використовуй прогресбар та предікт час».
Chat: Ukrainian. Session = current tmux session (`tmux display -p '#S'`, e.g. W44); board dir `~/.claude/fleet-board/<session lowercase>/`.
State file: `~/.claude/fleet-board/monitor-tiki.json` → `{"job": "<cron id>", "until": "<HH:MM>", "session": "W44", "started": "<HH:MM>"}`.

## Argument `$ARGUMENTS`
- `off` → read the state file, `CronDelete` its job (load the tool via ToolSearch `select:CronDelete` if deferred), delete the file, say «моніторинг вимкнено». No file → «моніторинг не запущено».
- `status` → print state file + time left; no cron changes.
- `on` → same as `2h`.
- `<N>h` / `<N>m` (e.g. `2h`, `90m`) → if a state file exists, CronDelete the old job first (one monitor at a time). Then `CronCreate` with
  `cron: "*/10 * * * *"`, `recurring: true` and the **tick prompt** below (substitute UNTIL = now + duration as HH:MM, SESSION).
  Write the state file. Then run one tick right now. Tell Mike: job id, until when, how to stop (`/monitor-tiki off`).
  Cron jobs live only in this Claude session — say so.

## Tick prompt (what every 10-minute run does)
```
/monitor-tiki tick UNTIL=<HH:MM> SESSION=<S>
```
`tick` mode (internal, the cron sends it):
1. If now ≥ UNTIL → last report, then behave as `off`.
2. **Lead lane first** (memory: clear 🧭 every reply): `tmux capture-pane` each window of SESSION, read `📍` / `🙋 LEAD:` lines; give OK/decisions within lead authority via `~/.claude/fleet-board/bin/send.sh`; anything that is Mike's call → AskUserQuestion modal with context (never decide for him). A window stuck on its own modal → tell Mike, don't answer it blindly.
3. `python3 ~/.claude/fleet-board/bin/tiki-board.py <week>` (regenerates every card: progress bars, ⏱ parallel forecast, 📡 what the try proved).
4. Live facts only: last deploy (`gh run list -R back2back-team/rescue-serverless -w 165841775 -L 3`), fixture lock `/tmp/b2b-dev-fixture.lock.d`, `~/.claude/demo-result.sh check <pr>` (and `--preflight`) for open PRs, helper panes' done-files in `<board>/progress/` (close a helper pane when its file says DONE — RAM), new PRs → add to `<board>/pr-windows.tsv`.
5. Reply (short):
   - «Що змінилось за 10 хв» — 3–6 lines, facts with time.
   - Progress board: one bar per active task `█░` 10 cells + % + predicted finish `→ ≈HH:MM` (parallel lanes: review gates ∥ deploy; PRE after deploy; Mike last). Label predictions as forecast.
   - «🧪 Тобі можна зараз» — only tries whose lead preflight is ✅ on the current dev sha and PR head unchanged; give the exact `jb2b …-try` command in a plain code block between `---` lines.
   - «🙋 Від тебе» — numbered actions/decisions.
   - Last line `result:` one-line headline.
Never merge/push in a tick; never touch dev fixture data while the lock is held.
