---
description: "Lead status report (format A1) with progress bars — live fleet state: dev slot, every PR's gates, every teammate window, Mike's actions, forecast, prod-after-merge reminders"
argument-hint: "[short]  (no args = full A1; short = header + Тобі + bars)"
model: sonnet
---

# /lead-status — A1 report with progress bars

Chat language: Ukrainian (Mike). Everything comes from LIVE data — never from memory or earlier messages.

## Step 1 — collect (one call, read-only)

```bash
~/dotfiles/claude/.claude/scripts/lead-status.sh b2b > /tmp/claude/lead-status.json && jq . /tmp/claude/lead-status.json
```

It returns: `now`, `dev_holder` (PR with the `deploy` label), `last_deploy`, `disk`, `swap`,
`windows[]` (win, name, busy, last ⏺ line, last 🙋/STATUS signal, idle_since, pr),
`prs[]` (pr, linear, title, draft, labels, cr, smp, jt, demo_ok, demo), `reminders[]`, `dev_queue`.

A PR is **in the fleet** if a window names it or `dev_queue` mentions it; other open PRs
(e.g. labelled `invalid`, old drafts) go into ONE line "інші відкриті, не в роботі: #…".

If a window's `signal` is newer than your last handling of it, **act on it first** (approve,
hand over dev, answer) — the report must not describe a teammate waiting on the lead.

## Step 2 — progress per PR (deterministic)

Stages, in order: `CR · SMP · dev · JT · DEMO · merge`. Done = `cr`, `smp`, (JT or DEMO done ⇒ dev done), `jt`, `demo_ok`, merged.
Bar = 16 cells, `█` per done share, `░` rest: `round(16 × done/6)`.
Mark the current stage ▶ when its window is `busy`, ⏳ when it waits on a deploy (`last_deploy` in_progress
for its branch), ⛔ when it waits on Mike (draft without ticket, new-PR approval), 🙋 when only merge is left.

```
#2205 PUN-1680  [████████████░░░░]  75%  CR ✅ SMP ✅ dev ✅ │ JT ▶ │ DEMO · │ merge ·
Fleet           [████████████░░░░]  3/6 ready to merge · N teammates busy
```
Items without a PR yet (local branches from windows) get their own row: `код ✅ │ PR ⛔`.

## Step 3 — render A1 (this order, nothing skipped)

1. **Header quote** — `dev: #N · PUN-x <state> → ETA` · `⛔ ти блокуєш: n` · `🙋 чекає тебе: n` · `▶ працює: n` · time.
2. **🆕 З минулого апдейту** — only deltas since your previous status (merges, deploys, signals, new blockers).
3. **📊 Прогрес** — the bars from Step 2 in one fenced block.
4. **🙋 Тобі** — table `# · ⛔/🙋 · що зробити (with PR link) · хв · чекає (⌛ if > 60 хв) · розблокує`,
   most-unblocking first; then `🧮 разом N хв · найцінніше: …`.
5. **👥 Команда** — table `вікно · PR · Linear · стан · скільки в стані (🔴 > 20 хв without progress) · 💬 останнє слово (signal or last ⏺, ≤ 70 chars) · ETA`.
6. **⏱ Прогноз** — fenced, `HH:MM  icon  event`; `~` marks a forecast, no `~` = measured.
7. **🔗 Залежності** — one line of `A → B`.
8. **🚀 Прод після merge** — from `reminders[]` (🔔 slug) + PR bodies' prod steps; any step not yet a reminder → 📥 with the ready `just -g rem-add <slug> <title>` command.
9. **🧯 Мої промахи** — only if the lead lost time since the last report; honest minutes.
10. `<sub>⚙️ dev #N · працюють n з m · диск · swap · 🌐 links</sub>`

`short` argument → items 1, 3, 4 only.

## Rules

- Legend icons exactly: ✅ done · ▶ running · ⏳ waiting on automation · 📋 queued · ⏸ paused · 🙋 Mike's action (ready) · ⛔ Mike blocks · 🔒 lead blocks · ❌ failed · 💤 idle.
- Every PR written as `#N · PUN-x` (Linear id) with a link; never a bare number.
- Never claim a gate you did not read from the JSON (`demo_ok`, `jt`, `cr`).
- Mike-facing text in Ukrainian; PR/branch names stay as they are.
