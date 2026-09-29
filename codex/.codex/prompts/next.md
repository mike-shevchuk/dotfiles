---
description: "Pipeline autopilot — sense the active track (GSD phase lifecycle vs PR pipeline) and EXECUTE the next stale/pending step. PR track: code-review, simplify, merge main, push, PR, EN summary, just-test. GSD track: discuss→plan→execute→verify→review→ship. Safe steps run automatically, outward-facing steps wait for explicit go"
argument-hint: "[dry]  (dry = show the plan, execute nothing)"
---

# Next: execute the next pipeline step for the current branch

`/pr-state` and the statusline SHOW where the pipeline stopped (the `➜SMP` chip).
`/next` is the actuator: it DOES that step, stamps it, and moves on.

**Terminal language:** match Mike. **No Mermaid in terminal** — ASCII only.

## ALWAYS show a Stage banner (MANDATORY — Mike's standing request)

Every `/next` run (PR or GSD track, `dry` or live) MUST open AND close with a
**stage banner** — a full map of the pipeline with Mike's current position and
what's left, so he never has to guess where he is. Format (ASCII, adapt counts):

```
📍 STAGE 3/7 · PR track · card-zone-clamp (PR #1535)
   ✅ CR   ✅ SMP   ➜ main   ⏳ push   ⏳ PR   ⏳ summary   ⏳ just-test
   ▶ now:  merge origin/main (AUTO)
   ⏳ left: push · PR · EN summary · just-test   (next GO-gate: push)
```

- `✅` done/fresh · `➜` running now · `⏳` still to do. Mark the **first GO-gate** in "left".
- GSD track: same banner over the phase lifecycle (`discuss ▸ plan ▸ execute ▸ verify ▸ review ▸ ship`),
  with `📍 PHASE n/N · <name> · <status>` and the current phase step as `➜ now`.
- Print it in **Step 2 (Plan)** before acting, and again in **Step 4 (Report)** with the
  updated position. If the pipeline is complete, the banner says so and names the only
  remaining manual action (e.g. "merge").

`$ARGUMENTS`

## Step 0 — Track router (GSD vs PR)

`/next` drives **one of two tracks**, picked from context (same context-switch as
the statusline `🛠`/`🧭` slot and `/pr-state`):

```bash
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
_gsd=0
if [ -f .planning/STATE.md ] && ! gh pr view --json number >/dev/null 2>&1; then _gsd=1; fi
```

- **GSD track** (`_gsd=1`): a GSD project is active **and** there's no open PR yet
  → advance the **phase lifecycle**. See "GSD track" below.
- **PR track** (default): everything else → the existing PR pipeline (Step order
  + Workflow sections below), unchanged.

Announce which track you're on in one line before planning. `dry` works on both.

### GSD track

Sense with the SDK (read-only, ~0.1s), then advance the **current** phase (first
non-`Complete`) one step, honouring the same AUTO-vs-GO discipline as the PR track:

```bash
gsd-sdk query progress 2>/dev/null   # phases[] {number,name,plans,summaries,status}, percent
gsd-sdk query stats   2>/dev/null    # phases_completed/total, last_activity
```

| Phase status | Next GSD step | Skill to invoke | Gate |
|--------------|---------------|-----------------|------|
| Pending | discuss → plan | `gsd-discuss-phase` then `gsd-plan-phase` | AUTO |
| Planned · In Progress | execute | `gsd-execute-phase` | AUTO |
| Executed | verify | `gsd-verify-work` | AUTO |
| Needs Review | review | `gsd-code-review` | AUTO (findings only; no auto-fix without go) |
| Complete (all phases) | ship | `gsd-ship` | **GO** (PR / outward — explicit go) |

Plan-print exactly like the PR track (one line: current phase, status, the step
that will run, the first GO-gate). On `dry` → stop after the plan. Otherwise run
the one AUTO step (delegate to the skill, or `gsd-progress --next` for GSD's own
safety gates), then **stop** — re-run `/next` to take the following step. Stop and
require explicit "go" at `gsd-ship` (it opens a PR / posts outward), matching the
push/PR/comment rule. Knowledge written to the second brain is handled by the
vault bridge (`gsd-zettel-sync`), not by `/next`.

## Step order (the actionable tail of Mike's 12-step pipeline — PR track)

| # | Step          | Detect "needed" via                                              | Action                                   | Gate |
|---|---------------|------------------------------------------------------------------|------------------------------------------|------|
| 1 | code-review   | state `code-review` pending OR stale (commits-ago > 0)           | invoke the `code-review` skill           | AUTO |
| 2 | simplify      | state `simplify` pending OR stale                                | invoke the `simplify` skill              | AUTO |
| 3 | merge main    | `git fetch origin main` then `rev-list --count HEAD..origin/main` > 0 | `git merge origin/main`             | AUTO* |
| 4 | push          | no upstream OR `rev-list --count origin/<br>..HEAD` > 0          | `git push` (+ `-u origin <br>` if new)   | **GO** |
| 5 | PR opened     | `gh pr view` fails                                               | `gh pr create --label bugbot` (draft body first) | **GO** |
| 6 | pr-summary    | state `pr-summary` pending                                       | draft EN summary comment → show → post   | **GO** |
| 7 | just-test     | state `just-test` pending OR stale                               | hand off to the `/just-test` skill (it has its own plan+go flow) | skill's own |

`AUTO*` = AUTO while the merge is clean; on ANY conflict — STOP, show the
conflicting files, and wait for guidance (never auto-resolve).

`review-pr` (Mike's own posted review) is NOT in the autopilot — too heavy and
draft-first by rule. If it's the only thing pending, say so and suggest
`/review-pr-eng` / `/review-pr-ukr`.

## Workflow

### 1. Sense

```bash
BR=$(git --no-optional-locks branch --show-current)
~/.codex/pipeline-stamp.sh show          # state file (may be empty — then treat all as pending)
git --no-optional-locks status --short    # dirty?
git fetch origin main --quiet && git rev-list --count HEAD..origin/main   # behind main?
git rev-list --count origin/$BR..HEAD 2>/dev/null                          # unpushed?
gh pr view --json number,state 2>/dev/null                                 # PR?
```

Compute staleness per stamped step: `git rev-list --count <stamp.head>..HEAD`
(same logic as the statusline badges). Stale = needed again.

**Pre-flight blocks (stop and report, do nothing):**
- On `main` → refuse: "create a feature branch first" (always-branch rule).
- Dirty working tree → show `status --short`, propose a commit (specific files
  by name, NEVER `git add -A`), wait for go. Uncommitted work makes every
  downstream step lie.
- PR already merged / branch gone → say so, suggest cleanup.

### 2. Plan

Print the plan BEFORE acting — one line per step in order, marking what will
run, what is fresh-skip, and where the first GO-gate is:

```
➜ next plan for card-zone-clamp (PR #1535)
  1. CR   ✓-2 stale → RUN  code-review (2 new commits)
  2. SMP  ✓ fresh   → skip
  3. main ↓3        → RUN  merge origin/main
  4. push ↑2        → GATE push 2 commits
  5. JT   stale     → GATE hand off to /just-test
```

If `$ARGUMENTS` contains `dry` → **stop here.** The plan is the output.

### 3. Execute

Run the AUTO steps in order, top to bottom:

- **code-review** → invoke the `code-review` skill scoped to the new commits
  (`<anchor>..HEAD` if stale, whole branch if never run). If it produces fixes,
  apply + commit them — and remember: any new commit re-stales CR, so re-run
  until clean (per the re-run-after-every-fix rule).
- **simplify** → invoke the `simplify` skill on the branch diff.
- **merge main** → `git merge origin/main`. *On conflicts: STOP. Show the
  conflicting files and proposed resolutions; NEVER resolve with destructive
  git ops (`checkout --`, `restore`, `reset --hard`) without explicit approval.*

After each completed step:
```bash
~/.codex/pipeline-stamp.sh stamp <step> <src>   # src=commit:<sha> when the evidence is a commit
```
and print a one-line result: `✅ code-review — 0 findings (stamped @ <sha>)`.

**At the first GO-gated step: stop.** Show exactly what will be sent (the push
target + commit list, the full PR body, the full summary comment text — full
preview, never condensed) and ask. Only an explicit affirmative ("go", "так",
"пуш", "пости") proceeds. Anything else = stay stopped. After Mike's go,
execute, stamp, then continue to the next step (which may gate again).

GitHub content (PR bodies, comments, summaries) is ALWAYS English. No
Co-Authored-By lines. New PRs get `--label bugbot`.

### 4. Report

End with the same ASCII pipeline bar `/pr-state` uses, showing the new state:

```
🧭  CR ✓   SMP ✓   RPR ·   JT ✓      (was: CR ✓-2  SMP ✓  RPR ·  JT ✓-2)
```

plus a Summary block (3–7 bullets): what ran, what got stamped, where it
stopped and why, what remains. If everything is fresh and done → say the
pipeline is complete and suggest the merge step (Mike merges manually).

## Rules

- **Sense → plan → execute, in that order.** Never act before printing the plan.
- **AUTO steps**: code-review, simplify, merge main (no conflicts), stamping.
  Everything visible to others (push, PR, comments) is GO-gated — no exceptions,
  re-invoking `/next` is NOT a go.
- **Honest staleness**: a step is re-run when commits landed after its anchor —
  same `rev-list --count` math as the statusline; never skip a stale CR.
- **One branch at a time** — `/next` operates on the current worktree's branch
  only. For the fleet view use `/prs`, then run `/next` inside the chosen worktree.
- Stamps keep `/pr-state` and the statusline badges live automatically.
