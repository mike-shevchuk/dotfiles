---
description: "Show the state of a subagent-driven-development (SDD) run — every task from the plan with its status, per-commit timings, and open findings, read live from the SDD ledger and git so it can never go stale"
argument-hint: "[plan-slug | path/to/plan.md]  (no args = auto-detect the active run)"
---

# SDD-State: where is this implementation plan

Mike asks "покажи план / де ми / what's left". Reconstruct the state of a
subagent-driven-development run and print it.

**Never hand-maintain this list.** Everything below is derived from three live
sources, so a stale answer is impossible:

| Source | Gives you |
|---|---|
| the plan file — `## Task N:` headings | the task list and its titles |
| the SDD ledger — `<workspace>/progress.md` | per-task status, fix rounds, parked/deferred findings |
| `git log` on the branch | commits and real elapsed time |

**Terminal language:** match Mike (Ukrainian or English).
**No Mermaid in terminal** — ASCII/Unicode tables only (project rule).
Times are **measured**, never estimated. If a task has no commit, say so rather
than guessing a duration.

## Step 1 — locate the run

With an argument: treat it as a plan slug or a path to the plan `.md`.

Without one, auto-detect. An SDD run may live in a worktree, so check those too:

```bash
git worktree list
```

For the main checkout and each worktree, look for a ledger:

```bash
ls -d <root>/.superpowers/sdd/*/ 2>/dev/null
```

Each directory is one plan's workspace. Its `progress.md` starts with
`# SDD ledger — plan: <plan file path>` — that first line tells you which plan
it belongs to. If several exist, list them and ask which one, unless only one
has activity.

If no ledger exists anywhere, say the run has not started (or was already
cleaned up after merge) and stop — do not invent a status.

## Step 2 — read the three sources

```bash
grep '^## Task [0-9]*:' <plan-file>          # task numbers + titles
cat <workspace>/progress.md                  # the ledger
git -C <root> log --reverse --format='%h|%at|%s' $(git -C <root> merge-base main HEAD)..HEAD
```

Ledger line shapes you are matching, in priority order:

| Ledger line | Status |
|---|---|
| `Task N: complete (commits a..b, review clean)` | **DONE** |
| `Task N: complete (..., K parked)` | **DONE**, note the parked count |
| `Task N: BLOCKED — ...` | **BLOCKED** — surface this loudly, first |
| `Task N: fix round R/5 ...` | **FIXING**, show R |
| `Task N: review ...` | **REVIEW** |
| any other `Task N: ...` | **WIP** |
| no line at all | **todo** |

Also collect every `Task N: minor (deferred)` and `Task N: parked` line — those
are the open items, and a roll-up nobody reads is a silent discard.

## Step 3 — print

Lead with one line: branch, worktree path, and `X/N tasks done`.

Then the **progress bars**, before the table — the bar answers "how far in",
the table answers "far in what". Count *execution units*, not plan headings: a
task the plan splits (6a/6b) is two units, and a unit counts as done only when
it is committed AND its review came back clean. A task mid-fix-round is not
done.

```
  █████████████████████████░░░░░░░░░░░░░░░  60%   9/15 units

  PR 1  ████████████████████████████████████████ 100%  8/8  MERGED
  PR 2  ██████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  17%  1/6
```

One bar per slice when the plan ships in slices, plus the overall bar. 40 cells
wide, `█` filled and `░` empty, so bars stay comparable between runs. Never
invent a denominator — if the plan has no numbered tasks, skip the bars and say
so.

Then the table — one row per task, in plan order:

```
  #    TASK                                 STATUS   CREATED           DONE              DUR    COMMITS
  1    Marker model and constants           ✅       2026-09-02 12:05  2026-09-02 12:18   13m   edca4d2..5dafe27
  2    Repository — claim                   ✅       2026-09-02 12:19  2026-09-02 12:24    5m   5dafe27..d97eba3
  3    Repository — release                 🩹 2/5   2026-09-02 12:25  —                   —    d97eba3..407460a
  4    Service — claim before save          ⏳       —                 —                   —    -
```

- **CREATED** = when work on it started: the `Task N: dispatched` line in the
  ledger, else the first commit that touches it. Local time, `YYYY-MM-DD HH:MM`.
- **DONE** = the timestamp of the commit that completed it, or `—` while open.
- **DUR** = DONE − CREATED in minutes. **Measured only** — never estimate a
  duration for a task with no commit; forecasts belong in their own block,
  labelled as extrapolation.
- Status: ✅ done · 🔄 in flight · ⏳ todo · ❌ blocked · 🩹 fix round R/5.

Then measured timings, computed from the commit timestamps — per commit and a
total. Convert to minutes; seconds are noise at this scale. Count fix rounds and
review cycles explicitly: on a real run they dominate elapsed time, and hiding
them makes every later estimate too optimistic.

Then, only if non-empty, an **open items** block listing deferred minors,
parked findings, and anything BLOCKED. If a task completed with parked
findings, say which and why — the ruling is in the ledger.

Close with the ledger path so Mike can read the full record himself.

## What to flag without being asked

- **Anything BLOCKED** — put it first, above the table. It is the only status
  that means the run cannot proceed on its own.
- **A task in FIXING at round 4 or 5** — the loop is near its cap; after round 5
  the controller must adjudicate rather than keep dispatching.
- **The baseline** — if the ledger's pre-flight notes record pre-existing test
  failures, repeat that number beside any test summary. "5 failed" means
  nothing without "…and 5 failed before we started".
- **A ledger whose first line names a different plan** than the one you were
  asked about — that is another run's progress. Do not read it as this one's.

## Do not

- Do not re-run the test suite to "check" a status — the ledger and the commits
  are the record; running tests here just burns time.
- Do not mark anything complete yourself. This command reports; it never writes
  to the ledger.
- Do not estimate a duration for a task with no commits. Print `-`.
