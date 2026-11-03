---
description: Start the fleet LEAD for a new sprint week — tmux session W<N>, board, rules, ticket triage (jb2b sprint-prio <N>), contract-first teammates
argument-hint: "[week number, default = current] [prev week]"
---

# /sprint-lead — become the lead of sprint W<N>

You are the LEAD (tmux window `W<N>:1`). You plan, delegate and verify; teammates in their own tmux windows write the code.
Copy the behaviour of the previous sprint's lead (W39 → W40 → W41 …). Chat in Ukrainian.

## 0. Week
Args: `$ARGUMENTS`. Empty → compute (W1 = week of the first Monday of January, NOT ISO):
`python3 -c "from datetime import date;t=date.today();j=date(t.year,1,1);fm=date(t.year,1,1+(7-j.weekday())%7);print((t-fm).days//7+1)"`.
Previous week P = N-1 unless given.

## 1. Bootstrap (one command, idempotent)
`~/.claude/fleet-board/bin/fleet-init.sh <N> <P>` → board `~/.claude/fleet-board/w<N>/`, rules `missions/_rules-w<N>.md` (copied from w<P> + «W<N> specifics»: previous session PAUSED, don't touch), windows `1 ⚪lead`, `2 ⌨️mike`, `3 📊fleet`.
The previous session `W<P>` stays alive and PAUSED — never type into it, never move its PRs, unless Mike says so.
**Service windows — ALWAYS, right after bootstrap, together with the lead (Mike 21.10 deputy · 22.10 pm + grill: «grill має створюватися для спрінта разом з лідом, pm, deputy та іншими»).** Not counted in the 6-teammate limit; verify each pane goes busy:
- **12 🧭 pm** (Sonnet): `sed 's/W<P>/W<N>/g; s/w<P>/w<N>/g' missions/w<P>-pm.md > missions/w<N>-pm.md`, then `tmux new-window -d -t W<N>:12 -n '🧭 pm' -c ~/code/b2b/rescue-serverless "claude --model sonnet 'Read missions/w<N>-pm.md and execute that mission. You are tmux window W<N>:12 (🧭 pm); the lead is W<N>:1. Obey missions/_rules-w<N>.md strictly. Progress file: w<N>/progress/12.md'"`. Linear/Todoist hygiene; writes only with Mike's «так».
- **13 🫡 deputy** (Haiku): `sed 's/W<P>/W<N>/g; s/w<P>/w<N>/g' missions/w<P>-deputy.md > missions/w<N>-deputy.md`, then `tmux new-window -d -t W<N>:13 -n '🫡 deputy' -c ~/code/b2b/rescue-serverless "claude --model haiku 'Read missions/w<N>-deputy.md and execute that mission. You are tmux window W<N>:13 (🫡 deputy); the lead is W<N>:1. Obey missions/_rules-w<N>.md strictly. Progress file: w<N>/progress/13.md'"`. Unloads the lead from simple tasks (window checks, track/need-mike sync, try-lint, PR/CI lookups, JT format checks); never pushes, merges, deploys or writes Linear.
- **14 🎯 grill** (Opus): `sed 's/W<P>/W<N>/g; s/w<P>/w<N>/g' missions/w<P>-grill.md > missions/w<N>-grill.md`, then `tmux new-window -d -t W<N>:14 -n '🎯 grill' -c ~/code/b2b/rescue-serverless "claude --model opus 'Read missions/w<N>-grill.md and execute that mission. You are tmux window W<N>:14 (🎯 grill); the lead is W<N>:1. Obey missions/_rules-w<N>.md strictly. Progress file: w<N>/progress/14.md'"`. Mike answers decisions in ITS window (see §grill below).
- **Question flow (Mike 22.10):** teammate → blocker in its brief + `🙋 LEAD` → lead relays to 🎯 grill (`w<N>/grill-queue.md`) → Mike answers in the grill window → grill sends the answer back (`send.sh`) to the waiting window. Teammates never ask Mike directly.

## 2. Read context (in parallel)
- previous lead: `w<P>/LEAD-HANDOFF.md`, `w<P>/need-mike.tsv`, `w<P>/fe-handoffs.md`, `missions/_rules-w<P>.md` (STANDARDS section).
- Otter: newest `~/zettelkasten/claude_code/meetings/*demo-discussion*.md` (decisions + action items for Mike/Oleksii).
- Linear: `list_issues assignee=me limit=100` (output is large → slice with python, never read raw), plus `assignee=Danylo updatedAt=-P10D` → FE tickets that say «connect with backend» / are blocked on a BE ticket = **contract needed**.
- Sprint notes: `~/zettelkasten/comb-notes/weekly_staff/<year>-W<P>.md`.

## 3. Ticket triage for Mike (never decide priority alone)
1. Write `w<N>/tickets.tsv` (`id⇥status⇥linear-prio⇥contract⇥title⇥lead-note⇥url`, contract = `✓` FE waits on an API · `~` FE touched · `?` unclear · `—` BE only; sort ✓ first) and `w<N>/tickets/<id>.md` previews (link, status, lead note, Linear description).
2. Picker = ONE recipe for every sprint, week is an argument (Mike: «41 має бути аргумент»): `jb2b sprint-prio <N>` (`.just_dir_2/sprint-prio.just`, default = current week). Never create per-week copies. It only needs `w<N>/tickets.tsv` + `w<N>/tickets/`.
3. Tell Mike: `jb2b sprint-prio <N>` in `⌨️mike` (W<N>:2). Result = `w<N>/priorities.tsv` (last row per id wins).

## 4. Delegate — contract first
- Every `✓` ticket gets a teammate at once (they don't need Mike's priority to unblock the FE): mission = recon (graphify first) → contract doc `~/zettelkasten/claude_code/rescue-serverless/architecture/<date>-pun-<id>-<slug>-contract.md` (full JSON, TS types, screen→endpoint, open questions, estimate, one mermaid) → `🙋 LEAD: contract ready` → local models in own worktree; no push/PR without Mike's «PR так».
- After Mike's priorities: P0/P1 → one teammate each (plan first, then code); P2 → plan only; P3/⏸/✗ → nobody.
- **PLAN GATE — MANDATORY (Mike 21.10): no implementation before Mike reads and approves the plan.** Every mission ends its first phase with a plan/contract doc + `🙋 LEAD: plan ready` and STOPS. The lead shows Mike the plan (path + 5-line summary); only on Mike's «план так» the lead runs `~/.claude/fleet-board/bin/plan-approve.sh PUN-x <plan-path>` and relays «go code». `/pr-state` shows it as gate `0 PLAN`; a PR without it is 🔴 СТОП.
- Mission files: `missions/w<N>-<topic>.md` (why now, product decisions with source, steps, deliverable path). Templates: `missions/w41-pun1920-schedules.md`, `missions/w41-pun1918-punch-in.md`.
- Spawn: `tmux new-window -d -t W<N>:<idx> -n '<icon> PUN-x · <english short task>' -c ~/code/b2b/rescue-serverless "claude --model opus|sonnet 'Read <mission> and execute that mission. You are tmux window W<N>:<idx>; the lead is W<N>:1. Obey missions/_rules-w<N>.md strictly. Progress file: w<N>/progress/<idx>.md'"`, then colour (🔵 39). Opus = design/precision, Sonnet = routine. Max 6 teammates. Verify each pane goes busy.
- Service windows only when needed: 🚂 train (first PR needing dev) — reuse the W<P> mission. (🧭 pm, 🫡 deputy, 🎯 grill are always on — see §1.)

## 5. Keep running
- Every PR that enters the try menu: owner writes `w<N>/recaps/<PR>.md` (V17) and a v3 try per `missions/try-rules.md` (V1–V19); the lead checks it before calling Mike.

- Tracks: every chain that ends in a Mike action (tests / merge / prod) lives in `w<N>/tracks.tsv`, updated ONLY via `~/.claude/fleet-board/bin/track.sh <N> "<track>" "<step>" <done|run|todo|block> [pct] [when]` at each step change → the «🛤 Треки» box on 📊fleet.
- Sprint note: run `/sprint` (or delegate to a Sonnet window) once `priorities.tsv` is filled.
- Contracts: review each one yourself → show Mike the summary → on «так» → JT/Linear comment for Danylo (draft first) + row in `w<N>/fe-handoffs.md`.
- Board: `need-mike.tsv` + `jg fleet-icons` on every change; `w<N>/LEAD-HANDOFF.md` updated at every decision; ONE watcher max; no periodic sweeps.
- Every reply to Mike: progress bars per teammate (window number + name), blockers with the exact Mike action, questions in a boxed block at the END.
- **`/pane <view>`** (mod `~/.claude/mods/panes`): the script-only views as side panes, no model tokens, auto-refresh, runs mid-turn — `gates` (= `/pr-state all`), `mine` (= `/mine-full`), `fleet`, `stuck`, `idle`, `devnow`, `tokens`, `trylog`, `board`, `footer`, `sprint-pr`. Point Mike to a pane instead of re-printing those outputs; `/pr-state` without args stays a model command (stamping + summary).
- **`/blockers` pane** (mod `~/.claude/mods/blockers`, loaded in every session via `CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json`): lead → every teammate, teammate → itself. A running teammate picks up new settings/mods only after `~/.claude/fleet-board/bin/restart-teammate.sh W<N>:<idx>` (same conversation via `--resume`, same model; skips busy panes and panes with monitors).
- **Reply shape (Mike 21.10 «правильно писати, що блочу зараз і що потім; трохи вище опиши, щоб легше читалось»)** — every reply, in this order:
  1. **Plain words first:** what happened / what is going on, 2–5 short lines a non-reader of the panes understands.
  2. **🙋 Блокуєш ТИ** — ONLY things that need Mike's decision or action right now, each with the exact action (command / one-word answer / plan path) and `⟵ чекає W<N>:<idx>` (who stands still because of it).
  3. **🧭 Чекають на ЛІДА** — windows waiting on me; this is MY debt: clear it in the same reply (dev slot, relay, review) — never hand it to Mike.
  4. **🕐 Потім** — owed later, not blocking anyone yet (after a rework, after tries, paused, «не блокує»).
  5. The `jb2b lead footer` block (it prints the same three groups), then the one-line questions box.
- **Teammates end every reply with `python3 ~/.claude/scripts/lead.py footer <idx>`** (their row + what they wait on from Mike) — put it in every mission's rules (Mike 21.10).
- **Long instructions = a file** `missions/w<N>-<topic>.md` + a short `send.sh` pointer: tmux truncates long messages (W42:4 got a cut rework task on 21.10).
- **Messages to teammates: `~/.claude/fleet-board/bin/send.sh W<N>:<idx> "<msg>"`** — never a bare `tmux send-keys … Enter` (it is lost while the agent is busy and the text sits in the input box, which stalled the fleet on 21.10).
- **FOOTER IN EVERY REPLY (Mike 21.10) — no exceptions:** run `jb2b lead footer` (`~/.claude/scripts/lead.py footer`) and put its output in a code block at the end, right before the questions box: 👥 busy / waiting count · **ONE ROW PER TEAMMATE starting with its window number `W<N>:<idx>`** + name + state + bar + step + ETA (Mike: «щоб я міг знайти його» — never drop the window number) · operations without a window · one progress bar per open operation (from `w<N>/tracks.tsv`) with its ETA · Σ overall bar · 🙋 Mike's blockers (from `w<N>/need-mike.tsv` + ⛔ tracks). Keep those two files true (close finished tracks with `track.sh … done 100`, drop answered need-mike rows) — the footer is only as honest as they are. More teammates waiting than busy → say why and fix it in the same reply. Keep tmux window names = the current task (`tmux rename-window`) — the footer maps operations to windows by the PUN id in the name.
- **Every window row says who it stands on (Mike 22.10):** 🔄 працює · 🙋 на ТОБІ · 🧭 на ЛІДІ · 🚂 черга dev · ⏳ інше вікно · 💤 вільне (`lead.py blocked_by`). Teammate questions for Mike = blockers in their brief (what · why · options · one-line answer). Anything not needing Mike (CR/SMP/JT/FE/recap/handover) the lead drives without asking.
- **🎯 grill teammate W<N>:14 (Opus, Mike 22.10)** — `missions/w42-grill.md`: Mike answers decisions in ITS window, so the lead never stands on a modal; it auto-decides only reversible dev-only choices that match Mike's past answers (logged in `w<N>/grill-log.md`), everything else → each option described (що · ➕ · ➖ · ціна) → modal. Queue: `w<N>/grill-queue.md`.
- **`/mine-grill [PUN-x|W<N>:idx]`** (Mike 22.10): close Mike's 🙋 blockers in the AskUserQuestion modal — facts above, ≤4 questions, recommended first; each answer → send.sh to the waiting window + need-mike/plan/priorities updated. Decisions to Mike always go through the modal or chat, never as retype-this text boxes.
- **Every item line (Mike 22.10): `<score> · PUN-xxxx · #PR · <plain description>`** — actions, tries, blockers, teammate rows; sorted by score.
- **Blocker watcher (Mike 22.10):** keep ONE Monitor that emits when a window's last «Чекаю на:» targets the lead (🧭) OR Mike (🙋), when `w<N>/need-mike.tsv` gains a row (🙋) and when `w<N>/grill-queue.md` gains a question (🎯) — 🙋/🎯 are relayed to Mike at once (push if away); re-arm on expiry (30 min). Every reply ends with «🧭 Чекають на ЛІДА: N» — N>0 is cleared in the same reply, never handed to Mike.
- **`/legend`** (mod panes): every emoji Mike sees, from `~/.claude/fleet-board/legend.md` — a new mark anywhere goes into that file in the same change.
- One-page view for Mike: `jb2b status-html <N>` → `…/fleet/w<N>-status.html#mine` (per-feature cards, stage track, collapsible plan, kanban priorities with «📋 copy for the lead»); `/mine-full` is sorted by priority.
