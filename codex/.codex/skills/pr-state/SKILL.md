---
name: pr-state
description: "Reconstruct the current PR branch's pipeline state — recent git activity + which workflow steps (code-review, simplify, review-pr, just-test, bugbot, CI) ran — and refresh the statusline badges"
---

# PR-State: pipeline status for the current branch

When Mike wants to understand "де ми / what's the state of this PR", reconstruct the
workflow pipeline for the **current git branch** and print it, then refresh the
per-branch state file the statusline reads.

**Terminal language:** match Mike (Ukrainian or English).
**No Mermaid in terminal** — use ASCII/Unicode boxes and tables (per project rule).

The badge order shown on the statusline is **CR · SMP · RPR · JT**
(code-review, simplify, review-pr, just-test). The detailed
output below also covers the rest of the 12-step pipeline.

## Argument modes

- **no args** → full reconstruction + print + statusline refresh (the default).
- **`stamp <step>`** → mark a step done manually, e.g. `/pr-state stamp code-review`.
  Run `~/.codex/pipeline-stamp.sh stamp <step> marker` then re-print.
- **`unstamp <step>`** → clear a step: `~/.codex/pipeline-stamp.sh unstamp <step>`.

Known steps: `brainstorm code-review simplify review-pr just-test pr-summary merged`.

`$ARGUMENTS`

## Workflow (no-arg mode)

### Step 1 — identify branch + PR

```bash
BR=$(git --no-optional-locks branch --show-current)
gh pr view --json number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,url 2>/dev/null
```
If `gh pr view` is empty, fall back to `gh pr view "$BR"`. Record the PR number
(`PR`). If there is no PR yet, say so — the pipeline is pre-PR; still show git
activity and the local steps.

### Step 2 — recent git activity ("last git commands you used")

Run and show all three (this is the "what did I just do" view Mike asks for):

```bash
echo "── commits on this branch (vs origin/main) ──"
git --no-optional-locks log --oneline --decorate -12
echo "── branch delta ──"
git --no-optional-locks log --oneline origin/main..HEAD | wc -l   # commits ahead
git --no-optional-locks diff --stat origin/main...HEAD | tail -1
echo "── recent git operations (reflog) ──"
git --no-optional-locks reflog -15 --date=relative
echo "── working tree ──"
git --no-optional-locks status --short
```
Summarise the reflog into a short human list of the last operations
(checkout / commit / merge / rebase / reset / pull) — that is the "останні git
команди які використовував" Mike wants.

### Step 2.5 — GSD phase state (only if `.planning/` exists)

GSD ([[get-shit-done]]) tracks its own **phase lifecycle** (discuss → plan →
execute → verify → review → ship) in `.planning/`, independent of the PR pipeline.
This is the "all GSD info" surface — the statusline only shows a compact `🛠 STEP
done/total` slot, so the full breakdown lives here.

Detect: if `[ -f "$cwd/.planning/STATE.md" ]` (else skip this section silently).
Pull authoritative state from the SDK (fast, ~0.1s, read-only):

```bash
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
gsd-sdk query progress 2>/dev/null   # {milestone_version,milestone_name,phases[],total_plans,total_summaries,percent}
gsd-sdk query stats   2>/dev/null    # adds phases_completed/phases_total, requirements, git, last_activity
```

Each `phases[]` entry has `{number, name, plans, summaries, status}` where
`status ∈ Pending | Planned | In Progress | Executed | Complete | Needs Review`.
Map status → next GSD action (same mapping the statusline uses):

| status | next step | badge |
|--------|-----------|-------|
| Pending | discuss / plan | `PLN` |
| Planned · In Progress | execute | `EXE` |
| Executed | verify | `VER` |
| Needs Review | review | `RVW` |
| Complete | (done) | `✓` |

Render a **GSD phase table**: `Phase | Name | Plans (sum/total) | Status | Next`.
Lead with a one-line headline: `🛠 GSD <milestone> — <phases_completed>/<phases_total>
phases · <percent>% · current: Phase <N> <name> → <STEP>`. The "current" phase is
the first non-`Complete` one (matches the statusline `🛠 STEP done/total` slot).
If `gsd-sdk` is unavailable, fall back to reading `.planning/STATE.md` +
`.planning/phases/*/` directly. Read-only — never mutate `.planning/`.

After the phase table, ALSO print the **GSD command cheatsheet** below (verbatim
table — it's a fixed reference, not detected state). Mark the command that
advances the *current* phase with a `➜` (use the status→next mapping above:
Pending→`/gsd:discuss-phase`/`/gsd:plan-phase`, Planned/In Progress→`/gsd:execute-phase`,
Executed→`/gsd:verify-work`, Needs Review→`/gsd:code-review`, all Complete→`/gsd:ship`).
This is the "which GSD command do I run next + what do they all do" reference Mike wants.

**GSD command cheatsheet** (core — short descriptions):

| Command | What it does |
|---------|--------------|
| **Lifecycle (per phase)** | |
| `/gsd:discuss-phase` | Gather phase context via adaptive questioning before planning |
| `/gsd:plan-phase` | Create detailed `PLAN.md` (task breakdown + verification loop) |
| `/gsd:execute-phase` | Execute all plans in a phase (wave-based parallelization) |
| `/gsd:verify-work` | Validate built features through conversational UAT |
| `/gsd:code-review` | Review phase's changed files for bugs/security/quality |
| `/gsd:ship` | Create PR, run review, prep for merge (GO — outward) |
| `/gsd:progress` | Situational: check progress / advance / dispatch the next step |
| **Project / milestone** | |
| `/gsd:new-project` | Initialize a new project (deep context → `PROJECT.md`) |
| `/gsd:new-milestone` | Start a new milestone cycle |
| `/gsd:complete-milestone` | Archive completed milestone, prep next version |
| `/gsd:phase` | CRUD phases in `ROADMAP.md` (add/insert/remove/edit) |
| `/gsd:autonomous` | Run all remaining phases autonomously (discuss→plan→execute) |
| **Quick / small** | |
| `/gsd:quick` | Small ad-hoc task WITH GSD guarantees (atomic commits, STATE) |
| `/gsd:fast` | Trivial task inline — no subagents/planning overhead |
| **Context / intel** | |
| `/gsd:map-codebase` | Parallel mappers → `.planning/codebase/` analysis docs |
| `/gsd:extract-learnings` | Pull decisions/lessons/patterns from completed phase |
| `/gsd:graphify` | Build/query the project knowledge graph |
| **Review / quality** | |
| `/gsd:debug` | Systematic debugging with state persisted across resets |
| `/gsd:audit-uat` | Cross-phase audit of outstanding UAT/verification items |
| `/gsd:health` | Diagnose `.planning/` health and optionally repair |
| `/gsd:help` | Full GSD command list + usage guide |

> Context note: GSD axis and PR axis are independent. The statusline shows the GSD
> `🛠` slot when a GSD project is active **and** there's no open PR; once a PR is
> open it switches back to the `🧭` PR badges. `/pr-state` always prints **both**
> when both have state — this section (GSD) and Step 4 (PR pipeline).

### Step 3 — detect pipeline steps

Combine three evidence sources. Start from the existing marker file so prior
stamps persist, then add what you can detect now.

```bash
~/.codex/pipeline-stamp.sh show     # existing state (may be empty)
```

**A. GitHub (PR comments + checks)** — `gh pr view "$PR" --json comments,reviews` then:
- **just-test** ⟶ any comment body contains `End-to-end smoke trace`.
- **review-pr** ⟶ a substantial review comment: contains severity scores
  (`/100`, `🟠`/`🔴`/`🟡`) or a `### `/`## ` review structure with findings.
- **pr-summary** ⟶ an English summary comment (a `## Summary`-style or
  "what changed / why" comment that isn't the review).
- **CI** ⟶ `gh pr checks "$PR"` — note Build / Deploy / Cursor Bugbot buckets.
- **bugbot** ⟶ the mirror PR is usually `PR+1`; check
  `gh pr view $((PR+1)) --json comments` for Cursor findings, plus the
  `Cursor Bugbot` check bucket on this PR.

**B. Git commit heuristics (local steps)** — over `origin/main..HEAD`:
- **simplify** ⟶ a commit whose subject starts with `refactor:`/`simplify`
  or mentions "simplify". Stamp `src=commit:<short-sha>`.
- **code-review** ⟶ evidence that review ran: a commit fixing review/bugbot
  findings (`fix: <cursor|review> …`), or simplify present (simplify follows
  code-review in the pipeline). If there's no signal, leave it **pending** and
  tell Mike he can `/pr-state stamp code-review` — never fabricate it.

**C. Marker file** — anything already stamped stays stamped (manual truth wins).

For every step you positively detect, stamp it (idempotent):
```bash
~/.codex/pipeline-stamp.sh set-pr "$PR"
~/.codex/pipeline-stamp.sh stamp just-test      pr-comment "$PR"
~/.codex/pipeline-stamp.sh stamp review-pr      pr-comment
~/.codex/pipeline-stamp.sh stamp simplify       "commit:<sha>"
# … only the ones with real evidence
```
Do NOT stamp a step you can't back with evidence — pending is honest.

**Also force-refresh the PR/bugbot badge** (the OTHER half of the statusline).
The stamps above only write the pipeline-step JSON; the `🔀 PR#N … 🐛<n>` badge
lives in a separate `pr-cache-<cwd>.txt` that the statusline refreshes on its own
**120 s TTL**. `/pr-state` is an explicit "refresh now", so force it (TTL is left
intact for the statusline's own background refreshes):
```bash
~/.codex/pipeline-stamp.sh refresh-pr     # re-runs gh, rewrites pr-cache for cwd + subdirs
```
This is what makes `/pr-state` refresh **everything** in one go. `🐛<n>` = count of
unresolved + un-reacted Bugbot threads on the mirror PR — it only drops when those
threads are resolved or reacted (+1/-1) on GitHub, not by re-running `/pr-state`.

Each stamp records an **anchor commit** (`head`): `src=commit:<sha>` pins it to
that sha, anything else anchors at current HEAD. The anchor powers the
"commits ago" staleness display — prefer `commit:<sha>` srcs when the evidence
is a commit, so the ago-count reflects when the check actually ran.

### Step 4 — print the state

Lead with a one-line headline (branch · PR#N(+mirror) · state · X/Y steps done
— include the Bugbot mirror PR in parens when it exists), then:

1. **Recent git** — the summarised reflog list + commits-ahead + dirty count.
2. **Pipeline checklist table**: `Step | Status | Commits ago | Evidence`. Use
   ✅ done / ⏳ pending / ⏭ n-a. "Commits ago" = `git rev-list --count
   <anchor>..HEAD` where anchor is the stamp's `head` field — how many commits
   landed AFTER the check ran. Cover at least: brainstorm, code-review,
   simplify, fetch+merge main, push, PR opened, EN summary, review-pr,
   check-pr/bugbot, just-test, merge. Mark each with its evidence
   (commit sha, comment id, check bucket) or "—".
3. **ASCII pipeline bar** mirroring the statusline badges, e.g.
   `🧭  CR ✓   SMP ✓-2   RPR ·   JT ✓`
   (`✓-N` = done but N commits behind, rendered yellow on the statusline).
4. **CI / merge readiness** line: checks summary + `mergeable`/`mergeStateStatus`.
5. **Stale-check warnings** — for any step with commits-ago > 0, flag it
   explicitly: per Mike's rule, code-review must re-run after EVERY fix, so
   `CR✓-3` means "3 unreviewed commits — re-run /code-review". Same logic for JT.
6. **What's left** — 1–3 bullets of the next concrete actions (the pending
   steps + stale re-runs).

End with a Summary block (3–7 bullets, lead with the most important number),
per the analysis-summary rule.

### Step 5 — confirm statusline refresh

Step 3 refreshed BOTH halves the statusline reads:
1. `/tmp/codex/pipeline-<branch>.json` — the pipeline-step badges (`CR·SMP·RPR·JT`).
2. `/tmp/codex/pr-cache-<cwd>.txt` — the `🔀 PR#N … 🐛<n>` badge (via `refresh-pr`).

Tell Mike both are updated and show the pipeline file path
(`~/.codex/pipeline-stamp.sh path`). No restart needed — the statusline re-reads
every render. The statusline's own 120 s TTL on the PR cache is unchanged; `/pr-state`
just forced an immediate refresh on top of it. If `🐛<n>` is still non-zero, that is
**accurate** (un-triaged Bugbot threads), not stale — clear them on GitHub to drop it.

## Notes / rules

- **Read-only on GitHub.** This command never posts, pushes, or merges — it only
  reads `gh` and writes the local state file. (Stamping is local-only.)
- **Honest pending.** A step with no evidence is ⏳, not ✅. Offer the manual
  `/pr-state stamp <step>` escape hatch.
- **Branch-keyed.** State lives per branch, so each worktree/PR has its own
  badges. Switching branches switches the badge set automatically.
- **Helper:** `~/.codex/pipeline-stamp.sh` (stamp|unstamp|set-pr|refresh-pr|show|path|branch).
- The stamping skills (`/just-test`, `/review-pr-eng`, `/review-pr-ukr`) also
  stamp their own step after they post, so the state stays fresh between
  `/pr-state` runs.
