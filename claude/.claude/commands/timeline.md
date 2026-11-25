---
description: "Таймлайн: чи можна тестити зараз (dev) · зведення змерджено/чекає тебе/робиться/пауза/нові тікети · твій план проб за пріоритетом з годинами · що найлегше закрити · план Claude по вікнах"
argument-hint: "[tmux-сесія: W45 / esp / 45] — порожньо = сесія, де запущено"
---
Scope = ONE tmux session (Mike 11.11): the argument, else the session this runs in (`tmux display -p '#S'`), else the newest sprint board. Only PRs owned by that session's windows (`<board>/pr-windows.tsv`) and only its windows are shown.

Run exactly one command and print its stdout VERBATIM in a code block (it is already formatted, all data is live — never re-gather with gh/tmux/aws):
`cd ~/code/b2b/rescue-serverless/backend/src/lambdas/api/fast && just --justfile justfile.v2 timeline $ARGUMENTS`
(= `jb2b timeline [сесія]` — recipe in `.just_dir_2/lead.just`, echoes the resolved python call; script `~/.claude/fleet-board/bin/timeline.py`)

What the board shows, top-down (Mike 11.11 — keep this order and these blocks):
- header: time · session · sprint day bar · dev = <train|main> + verdict. ✅ ONLY when dev runs OUR train and no deploy is running;
  dev = main («затерто чужим мерджем») or a running deploy → ⛔ with the clock time tries can start (≈HH:MM).
- ┏ 🧪 МОЖЕШ ТЕСТИТИ ЗАРАЗ ┓ box right under the header (Mike 12.11 «більше виділяй, що я можу протестити»): numbered big commands, each with PR · ⏱ · 🎯 · lead's own result; then «спершу дозвіл» tries; then the one-line «<PR> так …» answer. When dev is not ready the box says ⛔ with ≈HH:MM.
- 🤖 «АГЕНТИ ЗАРАЗ» right after the box (Mike 12.11 «показуй, які агенти працюють»): every window live — 🟢 працює (+ its current ⏺ action) · 🔴 питає (modal/permission open) · ⚪ чекає (+ «Чекаю на»); busy first.
- «ХТО НА КОГО ЧЕКАЄ І ЧОМУ» table under the agents block (Mike 12.11 «дуже класно — записуй так у timeline»): window · на кого (🔄 на себе / 👤 на тебе / 🚂 на dev / 🧭 на ліда) · що блокує (the red gates with plain meaning, or the wait) · що далі. A window with its own red gates is never «на тебе». Reuse this table in your 3 lines when Mike asks «чому чекає».
- 👤 «ТИ: ЩО РОБИТИ ВЖЕ · НА ЩО ЧЕКАЄШ» — ▶ МОЖНА ВЖЕ (decisions, GitHub permissions, the first try's Visual plan to read while
  waiting; the tries themselves only when dev is ready) and ⏳ ЧЕКАЄШ (what blocks Mike: dev/deploy, a window's gate, a merge —
  each with WHO clears it and WHEN ≈HH:MM). Dev-dependent gates (CI · PRE · MIKE) never hide a ready PR.
- 🧪 tries by 🎯 with measured seconds, clock times counted from when dev is READY, ⚡ speed rank, commands.
  Every mention of a try (▶ можна вже, task card «▶ …», 🌅 tomorrow, your 3 lines) carries its exact copyable `jb2b …-try`
  command (Mike 11.11: «пишеш проба, але не даєш justfile command»). PRs blocked only by Mike's own gates (PLAN title, Bugbot
  permission) are tries too, marked «спершу дозвіл ↑». Never a bare PR number — always `#N PUN-x · short meaning`.
- 📋 one card per task (pipeline bar, on whom, ETA, due, «що це», links) · 🤖 Claude's windows by 🎯 · 📅 today as ONE timeline
  (our trains + others' merges into main with «backend → затер dev» + incidents) · ⚠ risks · 🧭 lead debt · 📈 health · 🌅 tomorrow.

When nothing waits on Mike the board prints «🟢 ТИ ВІЛЬНИЙ» (Mike 12.11) — then your first line says exactly that.
Then at most 3 lines in Ukrainian:
1. What Mike can do RIGHT NOW (from ▶ МОЖНА ВЖЕ) and what blocks him (from ⏳ ЧЕКАЄШ: what, who clears it, ≈HH:MM). If ⛔ — say clearly: проби ПІСЛЯ ≈HH:MM, and why (deploy / dev затерто мерджем).
2. Which try to run first and why — name its 🎯 priority score and what it unblocks — with its clock time.
3. Anything 🔄 «Робиться» that waits on Mike (a decision, a permission) — one line with the exact ask.
Every duration you add carries a clock time: «~N хв (≈HH:MM)» (Mike 11.11).
