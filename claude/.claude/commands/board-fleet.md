---
description: "Fleet board — overview of ALL Mike's open PRs + sessions: status legend (busy/idle/stalled/waiting/blocked/paused/done), pr-state (CR/SMP/RPR/JT/REV), CI, pull-main (behind), just-test presence, then a per-PR detail card (desc, plan, pros/cons), a BLOCKERS table, a dependencies/conflict map, an incident log, value delivered, and the human/morning queue. Manage pause list."
argument-hint: "[pause <PR> | unpause <PR> | <PR>]  (no args = full board; <PR> = just that card)"
---

# /board-fleet — the fleet coordination board

Mike coordinates many parallel Claude sessions/worktrees. This renders ONE board so he
can see the whole fleet at a glance and drive it. See memory [[feedback_board_means_fleet_status]]
and [[feedback_describe_tmux_windows_before_killing]].

**Terminal language:** match Mike (Ukrainian default). **No Mermaid** — ASCII/Unicode boxes only. **Plain ASCII / readable.**

## Status model (rules)
- **🟢 working by default.** A session is non-working ONLY if explicitly **⏸ PAUSED** (persisted in `~/.claude/fleet-board/state.json` → `.paused[]`). ListAgents "idle" ≠ done.
- A PR is **✅ done** only with: current **/just-test** comment + full **/pr-state** (CR·SMP·RPR·JT·REV) + **up-to-date with origin/main** (behind==0). Else show the exact GAP.
- Always **render the STATUS LEGEND first**, use those exact emoji everywhere, and end with a **progress bar** of the fleet (done vs total, per [[feedback_show_progress_bars_after_each_task]]).

## STATUS LEGEND (render this block first, every time)
**Pane / teammate state** (derive from `ListAgents` + ping history + gates):
- 🟢 **BUSY** — running tools right now (`ListAgents=busy`).
- ⚪ **IDLE** — alive, between steps, ready to take work (`ListAgents=idle`).
- 🔴 **STALLED** — idle a long time despite an assigned task, or unresponsive to ≥2 pings (its pane may be holding cross-session msgs for approval, or hung). Name the suspected cause.
- ⏳ **WAITING** — blocked on an *external gate it can't clear itself*: a deploy going green, Mike's terminal for a gated dev-API mutation, or the lead's "go".
- ⛔ **BLOCKED** — hard blocker: disk ENOSPC, auth/token, auto-mode classifier denial.
- ⏸ **PAUSED** — deliberately parked (in `.paused[]`).
- ✅ **DONE** — task finished, pane free.
- 💤 **OFFLINE** — Remote Control / cloud session not active in this session.

**PR pipeline badge** (CR·SMP·RPR·JT·REV): ✅ done · ⬜ pending · ⏭ n/a · ✓⁻ᴺ stale (N commits since it ran).
**PR merge/CI:** 🟩 CLEAN · 🟥 CONFLICT · 🟧 DIRTY · 🎯 code-ready · 🏁 MERGED.

## Argument modes
- **no args** → full board (overview + every per-PR card).
- **`pause <PR>` / `unpause <PR>`** → edit `.paused[]` in the state file, then re-render.
- **`<PR>`** (a number) → render just that PR's detail card.

`$ARGUMENTS`

## Data — TWO calls, no hand-gathering (Mike 2026-10-19, token budget)
1. `cd ~/code/b2b/rescue-serverless/backend/src/lambdas/api/fast && just --justfile justfile.v2 lead board` → devnow + stuck + mine + idle, ready boxes.
2. `~/.claude/pipeline-stamp.sh gates` → the per-PR verdict table (10 gates incl. 🐛 Bugbot, behind main 0).
Print both verbatim, then only the parts the recipes don't cover (blockers, incident log, next move) from what you already know.
Never re-run gh/tmux/aws/df per PR — if a column is missing, extend `~/.claude/scripts/lead.py` instead.
The old step list below is the reference for what the recipe covers.

## Data to gather (reference — now inside lead.py / pipeline-stamp.sh)
1. **Sessions:** `ListAgents` → live busy/idle per session; cross-ref the pause list.
2. **Open PRs:** `gh pr list --author @me --state open --json number,title,headRefName,mergeable,isDraft`.
3. **Per PR:**
   - CI: `gh pr view <n> --json statusCheckRollup` → pass/FAIL/running.
   - **pull-main (behind):** `git rev-list --count origin/<branch>..origin/main` (0 = up-to-date).
   - **pr-state stamps:** `/tmp/claude/pipeline-<sanitized-branch>.json` (sanitize `/`→`-`) → which of CR/SMP/RPR/JT/REV are done.
   - **just-test:** `gh pr view <n> --json comments` → any body matching `end-to-end smoke trace|just-test`.
   - size: `additions/deletions/changedFiles`.
4. **tmux (optional):** `tmux list-panes -a` to map windows→worktrees (for cleanup; describe before killing — never kill first).
5. **Environment / blockers:** `df -h /` (disk headroom — ENOSPC has repeatedly blocked the whole fleet; flag if <1Gi). Note any active cross-cutting blocker: auto-mode gate on dev-API mutations, shared dev last-deploy-wins, a running deploy, a stalled/unresponsive pane.
6. **Conflicts / dependencies:** for big-behind PRs, `git diff --name-only origin/main...origin/<branch>` (scope) and mergeable=CONFLICTING to spot which PRs collide with main or each other; note ordering constraints (e.g. two PRs touching the same file must merge in sequence).
7. **SDD / dev-lifecycle phase** (Mike asked to show /sdd-state here): for each active worktree, show its dev-lifecycle phase — 💭 brainstorm → 📋 plan → 🔨 execute → 🔍 review (CR·SMP·RPR) → 🧪 just-test → 🚀 ship. Derive it from the SDD ledger (`<worktree>/.superpowers/sdd/*/progress.md` per-task status, or `.planning/` if GSD) + the teammate's reported state. This is a COMPACT per-PR phase for the board; the full per-task drill-down is `/sdd-state <slug>` (run it standalone when Mike wants task-level detail). Never fabricate a phase — derive from the ledger/git/teammate report.
8. **⏱ TIME-PREDICT (from /sdd-state) + ⏭ /next** — Mike wants both on the board, per active PR:
   - **⏱ ETA:** the MEASURED elapsed (first→last commit on the branch, or since-spawn if no commit) PLUS a clearly-labelled `~forecast` of the remaining time to the next milestone (extrapolated from the SDD ledger's measured per-task avg × tasks-left). Measured is stated as fact; the remainder is always tagged `~` and "forecast" — never present an estimate as measured (the /sdd-state rule). If there is no basis, say "no basis" rather than invent a number.
   - **⏭ /next:** the single next concrete action for that PR (the `/next`-style next-stage banner) — e.g. "run /just-test in terminal", "brainstorm → design options to lead", "push (Mike)". End the board with a consolidated "NEXT ACTIONS" list (one line per active PR) mirroring `/next`.

## Render — TWO layers

### Layer 1 — OVERVIEW (one framed table)
Columns: `PR | Task | pr-state(CR SMP RPR JT REV) | JT-comment | behind-main | CI | mergeable | 🟢/⏸ status`.
Header line: any cross-cutting blocker (e.g. shared dev broken) + dev deploy state.

### Layer 2 — PER-PR CARD (one block each, skip paused unless asked)
For every PR, a compact card:
```
┌─ #<n> <title> ─ <🟢 working | ⏸ paused> ────────────────────┐
│ What:  <1-line description of what the PR delivers>          │
│ State: pr-state badges · CI · behind=<n> · JT=<yes/no>       │
│ Plan:  1) … 2) … 3) …   (the concrete next steps)           │
│ ✅ Pros:  <why this is in good shape / value>                │
│ ⚠ Cons:  <gaps/risks: missing JT, behind main, conflicts…>  │
└──────────────────────────────────────────────────────────────┘
```

### Layer 3 — BLOCKERS + context (always render these blocks, in order)

**⛔ BLOCKERS** — a table of every active blocker, most-impactful first. Columns:
`Blocker | Impact (what it stops) | Who can clear | ETA/next step`. Cover disk/ENOSPC,
auto-mode gates on dev-API mutations, stalled panes, CONFLICTING branches, waiting-on-Mike
gates. If none: one line "⛔ Blockers: none".

**🔗 DEPENDENCIES / CONFLICT MAP** — ordering constraints and collisions: PRs that must merge
in sequence (shared files), branches with real merge conflicts vs main, and any "A must ship
before B" (e.g. BE contract before FE). ASCII only, no Mermaid.

**🧯 INCIDENT LOG** — bullets of what broke this session and how it resolved (e.g. "ENOSPC
00:00→05:xx froze fleet → Mike freed 4.5Gi"; "dev 502 pydantic skew → #2183 pin"). Keep the
last few; this is the running memory of the night.

**🎁 VALUE DELIVERED** — what actually shipped/landed this session (posts, commits, deploys,
bugs found+fixed), one line each — so the board answers "what did the fleet achieve", not just
"what's pending".

**📋 HUMAN / MORNING QUEUE** — the checklist of actions that need Mike (terminal-gated dev
mutations, merges, prod steps, rotations, cleanups). Each item copy-paste ready where possible.

## Rules
- Verify every number (CI/behind/stamps/df) — never fabricate a pr-state badge, just-test, or blocker.
- Use the STATUS LEGEND emoji consistently across the overview, cards, and blockers.
- Paused PRs: show in overview greyed as ⏸ with the pause note; omit their detail card unless `<PR>` names them.
- Outward actions (deploy/merge/push) are only *recommended* here — never executed by this command without Mike's go.
- End with the fleet progress bar + a one-line "next move" recommendation.
