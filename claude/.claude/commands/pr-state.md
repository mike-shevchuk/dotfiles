---
description: "Reconstruct the current PR branch's pipeline state — recent git activity + which workflow steps (code-review, simplify, review-pr, just-test, bugbot, CI) ran — and refresh the statusline badges"
argument-hint: "[all | detect | stamp <step> | unstamp <step>]  (no args = show full state of this branch)"
---

# PR-State: pipeline status for the current branch

When Mike wants to understand "де ми / what's the state of this PR", reconstruct the
workflow pipeline for the **current git branch** and print it, then refresh the
per-branch state file the statusline reads.

**Terminal language:** match Mike (Ukrainian or English).
**No Mermaid in terminal** — use ASCII/Unicode boxes and tables (per project rule).

The badge order shown on the statusline is **CR · SMP · RPR · JT · FE · DEMO**
(code-review, simplify, review-pr, just-test, just-fe, demo). The detailed
output below also covers the rest of the 12-step pipeline.

**State is durable:** `~/.claude/pipeline-state/pipeline-<branch>.json` (survives a reboot;
`pipeline-stamp.sh` mirrors every write to `/tmp/claude/` for older readers and copies any
`/tmp` file that has no durable copy yet). "Commits ago" counts the branch's **own** commits
(`--first-parent --no-merges`), so merging main does not make a check stale.

**HARD RULE — every open PR is on the latest main (Mike 2026-10-20: «я хочу щоб всі мали останній main»).**
`behind` must be **0** for every open, non-paused PR in rescue-serverless and workflow-engine. No threshold, no "GitHub says CLEAN".
- no-arg mode: `behind > 0` → the merge-readiness line is ❌ «не на останньому main» and the FIRST "What's left" bullet is
  `jb2b pull-main` in the PR worktree, then `git push origin HEAD:<pr-branch>` (merge, never rebase).
- `all` mode: print a block «🌿 не на останньому main» BEFORE the table: one line per PR with `behind > 0` → owner window + fix.
  A PR with no live owner window: the lead merges `origin/main` into its worktree (clean tree, no local-only commits), checks
  ruff on the changed .py files, pushes; conflicts are reported, never force-resolved. Paused PRs (state.json) are listed, not touched.
- Merging main adds only a merge commit: CR/SMP/JT/DEMO stamps stay valid (they count own non-merge commits).

## Argument modes

- **no args** → full reconstruction + print + statusline refresh (the default). Works on a
  branch **without a PR** too: print `PR —`, skip the GitHub-only checks, still show git
  activity, stamps and heuristics. Never error out for "no PR".
- **`all`** → the verdict table (Mike 2026-10-20 «в табличці для кращої читабельності»): run
  `~/.claude/pipeline-stamp.sh gates` and print its box table **verbatim** in a code block (one row per open PR of mine in
  rescue-serverless + workflow-engine; Bugbot mirrors are skipped; paused PRs from the two newest `w*/state.json` go to the
  ⏸ line). Under the table it ALSO prints (Mike 2026-10-21) three blocks: ✅ ЗРОБЛЕНО (my PRs merged since Monday, both
  repos, mirrors skipped) · 🗓 ПЛАНУЄТЬСЯ / В РОБОТІ (newest board's `tracks.tsv`, last row per track not done, ⛔ = block;
  plus branches without PR) · ⏸ НА ПАУЗІ (paused PRs + `state.json` `paused_branches` prefixes). Print them verbatim too —
  so the lead must keep `tracks.tsv` true (close a track with `track.sh … done 100` when it ends). Then at most 3 lines: which row to act on first. Never re-gather per PR, never add columns by hand — a missing
  fact belongs in `scripts/pr-gates.py`. Read-only.
- **`all wide`** → the old 14-column table: `~/.claude/pipeline-stamp.sh fleet` (debugging only).

**VERDICT RULES (Mike 2026-10-20, enforced by `scripts/pr-gates.py`):**
1. Exactly one verdict per PR: ✅ МЕРДЖ (+ exact `gh pr merge` command) · 🙋 ТИ (only Mike's try/approval is missing, or an
   engine PR waiting for the rescue PR of the same ticket) · 🔴 СТОП (the FIRST failing gate + one action) · ⏸ пауза.
2. Eleven gates in this fixed order; ✅ only when all pass:
   `0 PLAN` Mike was GRILLED on the plan (`/pr-state grill`, 2026-10-22) and approved it BEFORE implementation (Mike 2026-10-21; `~/.claude/fleet-board/plan-approvals.tsv`,
   written only by `~/.claude/fleet-board/bin/plan-approve.sh PUN-x <plan-path>` after Mike says «план так»; PRs opened
   before the rule — rescue ≤ #2379, engine ≤ WE#77 — show ·) · `1 CI` no ✗/⏳ · `2 MRG` MERGEABLE · `3 MAIN` behind 0 · `4 CR` ✓ with 0 own commits after · `5 SMP` same ·
   `6 🐛` 0 unresolved Bugbot threads on the mirror (`<branch>-review`) · `7 TRY` try in preflight-map · `8 PRE` agent preflight ✓ ·
   `9 JT` JT comment/stamp fresh · `10 MIKE` Mike's DEMO approval ✓. Gates 7–10 are rescue-serverless only (· in engine rows).
3. A gate that cannot be checked is ✗. Never call a PR «закритий/готовий» unless its row is ✅.
4. no-arg mode starts with this PR's row: `~/.claude/pipeline-stamp.sh gates only=<PR>`, then the detail sections below.
- **`grill [PUN-x]`** (Mike 2026-10-22: «добавити grill-me, щоб ти запитував мене відносно плану — бачу різнобіжжя») → before «план так»
  the lead DRILLS Mike on the plan. Read the plan (`~/.claude/fleet-board/plan-approvals.tsv` / `lead.py plan_doc`) + the Linear ticket + the code it touches,
  then ask 5–8 questions, each a 5-part block (що · факт з file:line/URL · чому важливо · варіанти A/B/C · рекомендація + відповідь одним рядком). Cover:
  1. **Parity** — does the new path behave exactly like the existing one Mike will compare it to (chat, push/SMS/email, workflows, 911, fan-out, map, AI report…)? Name each.
  2. **What the user sees end-to-end** — screen by screen, incl. FE that reads the new data (null fields, new states).
  3. **Reuse** — which existing mechanism it rides on, and what that drags in (names like `QRSUBMIT#`, limits like 4 KB env).
  4. **Edge cases** — double tap, retry, resolve-then-new, wrong org header, missing optional field.
  5. **Out of scope** — what this PR will NOT do, said out loud.
  6. **Prod / infra impact** — env vars, new resources, migrations, data writes.
  Write Mike's answers into the plan as `## Grill (Mike, <date>)` — one line each `Q… → Mike: <answer>`. `plan-approve.sh` refuses without ≥3 of them.
  Also run it on an OPEN PR whose plan predates the rule when Mike says the behaviour diverges (#2379 chat, 22.10).
- **`detect`** → `~/.claude/pipeline-stamp.sh detect`: stamps code-review / simplify from
  commit subjects (`src=heuristic:commit:<sha>`), never over a newer stamp.
- **`stamp <step>`** → mark a step done manually, e.g. `/pr-state stamp code-review`.
  Run `~/.claude/pipeline-stamp.sh stamp <step> marker` then re-print.
- **`unstamp <step>`** → clear a step: `~/.claude/pipeline-stamp.sh unstamp <step>`.

Known steps: `brainstorm code-review simplify review-pr just-test just-fe demo pr-summary merged`.

**Teammate one-liners** (run in the PR worktree, right after the step):
```bash
~/.claude/pipeline-stamp.sh stamp code-review commit:$(git rev-parse --short HEAD)   # after /code-review (+ its fixes)
~/.claude/pipeline-stamp.sh stamp simplify    commit:$(git rev-parse --short HEAD)   # after /simplify
```

**DEMO is MANDATORY before merge (Mike, 2026-09-29).** Every PR has a guided demo recipe
`jb2b <topic>-try` whose RESULT box calls
`~/.claude/demo-result.sh write <pr> <recipe> <passed> <failed> <secs>` → `~/.claude/demo-results/pr-<N>.json`
(+ stamps `demo`, anchored to the dev SHA it ran against). Gate: `~/.claude/demo-result.sh check <pr>`
must exit 0 (failed=0 AND no non-merge commits after the demoed build). A PR without a passing,
fresh DEMO is NOT merge-ready — say so in the merge-readiness line.

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
~/.claude/pipeline-stamp.sh show     # existing state (may be empty)
```

**0. DEMO — two records, show both** (rescue-serverless PRs only):
- agent preflight ⟶ `~/.claude/demo-result.sh check "$PR" --preflight`
- Mike's approval ⟶ `~/.claude/demo-result.sh check "$PR"` (this one is the merge gate)
Print each line's own ✓/✗ reason, e.g. `DEMO pre ✓ (6 passed, dev 1ca9b28f5) · Mike ✗ not run yet`.

**A. GitHub (PR comments + checks)** — `gh pr view "$PR" --json comments,reviews` then:
- **just-test** ⟶ a comment matching (case-insensitive) `End-to-end smoke trace`, `Smoke trace`,
  `## /just-test` or `/just-test ·` → `stamp just-test pr-comment "$PR"`.
- **just-fe** ⟶ a comment matching `API for the frontend`, `FE hand-off`, `Frontend hand-off` or
  `/just-fe` → `stamp just-fe pr-comment "$PR"` (the FE badge).
- **review-pr** ⟶ a substantial review comment: contains severity scores
  (`/100`, `🟠`/`🔴`/`🟡`) or a `### `/`## ` review structure with findings.
- **pr-summary** ⟶ an English summary comment (a `## Summary`-style or
  "what changed / why" comment that isn't the review).
- **CI** ⟶ `gh pr checks "$PR"` — note Build / Deploy / Cursor Bugbot buckets.
- **bugbot** ⟶ the mirror PR is usually `PR+1`; check
  `gh pr view $((PR+1)) --json comments` for Cursor findings, plus the
  `Cursor Bugbot` check bucket on this PR.

**B. Git commit heuristics (local steps)** — run `~/.claude/pipeline-stamp.sh detect`. Over
`origin/main..HEAD` (merges skipped), newest match wins:
- **simplify** ⟶ subject starts with `refactor`/`simplify` or mentions "simplif".
- **code-review** ⟶ subject says `review fixes`, `from code-review`, `code-review`, `review-fix`,
  or `fix(...): … review`.
It stamps `src=heuristic:commit:<sha>` and never overwrites a stamp anchored at the same or a
newer commit. No match ⇒ leave it **pending** and point to the teammate one-liner above —
never fabricate it.

**C. Marker file** — anything already stamped stays stamped (manual truth wins).

For every step you positively detect, stamp it (idempotent):
```bash
~/.claude/pipeline-stamp.sh set-pr "$PR"
~/.claude/pipeline-stamp.sh stamp just-test      pr-comment "$PR"
~/.claude/pipeline-stamp.sh stamp just-fe        pr-comment "$PR"
~/.claude/pipeline-stamp.sh stamp review-pr      pr-comment
~/.claude/pipeline-stamp.sh stamp simplify       "commit:<sha>"
# … only the ones with real evidence
```
Do NOT stamp a step you can't back with evidence — pending is honest.

**Also force-refresh the PR/bugbot badge** (the OTHER half of the statusline).
The stamps above only write the pipeline-step JSON; the `🔀 PR#N … 🐛<n>` badge
lives in a separate `pr-cache-<cwd>.txt` that the statusline refreshes on its own
**120 s TTL**. `/pr-state` is an explicit "refresh now", so force it (TTL is left
intact for the statusline's own background refreshes):
```bash
~/.claude/pipeline-stamp.sh refresh-pr     # re-runs gh, rewrites pr-cache for cwd + subdirs
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

0. **Progress in percent, then the work items.** Always both, in this order —
   the bar answers "how far in", the table answers "far in what". Percent is
   `done / total` of *execution units*, not of pipeline steps: if a plan splits
   a task (6a/6b), each half is its own unit, and a task in flight counts as
   done only when it is committed AND its review came back clean.

   ```
     █████████████████████████░░░░░░░░░░░░░░░  60%   9/15 units

     PR 1  ████████████████████████████████████████ 100%  8/8  MERGED
     PR 2  ██████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  17%  1/6
   ```

   Render one bar per slice/PR when the plan ships in slices, plus the overall
   bar. 40 cells wide, `█` filled and `░` empty, so bars stay comparable
   between runs. If there is no plan with numbered tasks, skip the bars and say
   so — never invent a denominator.

   Then the work-item table, one row per unit, in plan order:

   `# | Task | Status | Created | Done | Duration | Commits`

   - **Created** = when work on it started: the dispatch line in the SDD ledger
     if there is one, else the first commit that touches it. Local time,
     `YYYY-MM-DD HH:MM`.
   - **Done** = the timestamp of the commit that completed it (`git log
     --format='%ad' --date=format:'%Y-%m-%d %H:%M'`), or `—` while it is open.
   - **Duration** = Done − Created in minutes, `—` when either end is missing.
     **Measured only.** Never estimate a duration for a task with no commit;
     a forecast belongs in "What's left", clearly labelled as extrapolation.
   - Status: ✅ done · 🔄 in flight · ⏳ todo · ❌ blocked · 🩹 in fix round R/5.

1. **Recent git** — the summarised reflog list + commits-ahead + dirty count.
2. **Pipeline checklist table**: `Step | Status | Commits ago | Evidence`. Use
   ✅ done / ⏳ pending / ⏭ n-a. "Commits ago" = `git rev-list --count
   <anchor>..HEAD` where anchor is the stamp's `head` field — how many commits
   landed AFTER the check ran. Cover at least: brainstorm, code-review,
   simplify, fetch+merge main, push, PR opened, EN summary, review-pr,
   check-pr/bugbot, just-test, merge. Mark each with its evidence
   (commit sha, comment id, check bucket) or "—".
3. **ASCII pipeline bar** mirroring the statusline badges, e.g.
   `🧭  CR ✓   SMP ✓-2   RPR ·   JT ✓   DEMO ✓`
   (`✓-N` = done but N commits behind, rendered yellow on the statusline).
4. **CI / merge readiness** line: checks summary + `mergeable`/`mergeStateStatus` + DEMO gate (`demo-result.sh check`) — no DEMO ✓ ⇒ not merge-ready.
   **Try (Mike 2026-10-16, always print for rescue-serverless):** the PR's justfile try + who ran it —
   recipe = `pipeline-stamp.sh` `try_of <PR>` (newest `~/.claude/fleet-board/w*/preflight-map.tsv`, else last
   `demo-results/pr-<N>.json`) → `🎯 try: jb2b <recipe> · pre ✓/✗ (<passed>, dev <sha>) · Mike ✓ апрувнув / ✗ не запускав`.
   `no-try` ⚠ → the PR has no try: name it as the first gap (add a try + a preflight-map row).
   **Behind main (Mike 2026-10-15, always print):** `git fetch -q origin main` then
   `git rev-list --count HEAD..origin/main` (behind) and `origin/main..HEAD` (ahead) →
   `🌿 main: behind <N> · ahead <M>` — `behind 0` ✅ up to date; `behind >0` ⚠ → name the fix:
   `jb2b pull-main` in the PR worktree, then push `HEAD:<pr-branch>`. A PR behind main is NOT merge-ready
   (its CR/JT/DEMO ran on code that is not what lands). In `all` mode the BEHIND column is the same number.
   **Mike-approved, not merged** (Mike 2026-10-06): if `demo-result.sh check` exits 0 (pr-N.mike.json `approved:true`) AND the PR is still OPEN,
   print a separate bold line FIRST in this section: `✅ Mike апрувнув (DEMO <passed>/0, <local Kyiv time>), НЕ змерджено → gh pr merge <N> -R <repo> --merge --delete-branch=false`.
   Note: his «так» lives in the DEMO gate, not as a GitHub review — `reviewDecision` stays empty; never report it as "not approved".
5. **Stale-check warnings** — for any step with commits-ago > 0, flag it
   explicitly: per Mike's rule, code-review must re-run after EVERY fix, so
   `CR✓-3` means "3 unreviewed commits — re-run /code-review". Same logic for JT.
6. **What's left** — 1–3 bullets of the next concrete actions (the pending
   steps + stale re-runs).

7. **Timeline** — the branch's own history as measured wall-clock, so the
   cost of the work is visible next to its state:

   ```
     spec        2026-09-02 10:45
     plan        2026-09-02 11:14   +29m
     first task  2026-09-02 12:18   +64m
     last commit 2026-09-02 15:21   +183m
     ────────────────────────────────────
     elapsed     4h 07m · 8 tasks · 3 fix rounds
   ```

   Include fix rounds and review cycles in the count — on a real branch they
   dominate the elapsed time, and hiding them makes every future estimate wrong.

End with a Summary block (3–7 bullets, lead with the most important number),
per the analysis-summary rule.

### Step 5 — confirm statusline refresh

Step 3 refreshed BOTH halves the statusline reads:
1. `~/.claude/pipeline-state/pipeline-<branch>.json` (+ `/tmp/claude` mirror) — the pipeline-step badges (`CR·SMP·RPR·JT·FE·DEMO`).
2. `/tmp/claude/pr-cache-<cwd>.txt` — the `🔀 PR#N … 🐛<n>` badge (via `refresh-pr`).

Tell Mike both are updated and show the pipeline file path
(`~/.claude/pipeline-stamp.sh path`). No restart needed — the statusline re-reads
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
- **Helper:** `~/.claude/pipeline-stamp.sh` (stamp|unstamp|set-pr|detect|fleet|refresh-pr|migrate|show|path|branch).
- The stamping skills (`/just-test`, `/review-pr-eng`, `/review-pr-ukr`) also
  stamp their own step after they post, so the state stays fresh between
  `/pr-state` runs.
