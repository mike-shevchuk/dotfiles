---
description: Every PR of the current sprint in one view — /pr-state for each (open + merged this sprint), its justfile try and whether Mike approved it
argument-hint: "[week, e.g. 41]"
---

# /sprint-pr — /pr-state of the whole sprint

Chat: Ukrainian. Read-only (never push, merge, post or stamp). Box tables, no Mermaid.

## Sprint
- Week = `$ARGUMENTS` or the current one: W1 = week of the first Monday of January (not ISO);
  `week = (today - first_monday).days // 7 + 1`. Sprint dir = `~/.claude/fleet-board/w<week>/`.
- Sprint start = Monday of that week, Kyiv time.

## Gather
1. Open PRs (with try + preflight/Mike): `~/.claude/pipeline-stamp.sh fleet` — print its table verbatim.
2. Merged this sprint: `gh pr list -R back2back-team/rescue-serverless --author @me --state merged --search "merged:>=<sprint start>" --json number,title,mergedAt,headRefName`
   and for each: try = `~/.claude/pipeline-stamp.sh try <N>`,
   `~/.claude/demo-result.sh check <N> --preflight` and `check <N>` (Mike), JT comment present (`gh pr view <N> --json comments`).
3. Sprint PRs with no try: every open or merged-this-sprint PR whose try is `no-try`.

## Print
1. **Open** — the fleet table (CR SMP JT FE · behind · CI · TRY pre/mike · mergeable · train).
2. **Merged this sprint** — box table: `PR | Linear | що (1 рядок) | merged (Kyiv) | try | pre | Mike | JT`.
   Merged without Mike's ✓ → mark ⚠ «змерджено без твого прогону» (run it now on main: `jb2b <try>`).
3. **Gaps** — one line each, most urgent first: no-try · CR/SMP stale (✓-N) · behind main >0 · no JT · preflight ✗ ·
   Mike ✗ on a PR that is otherwise ready → `jb2b sprint-try` → «так» →
   `gh pr merge <N> -R back2back-team/rescue-serverless --merge --delete-branch=false`.
4. Progress bar: PRs fully done (merged + Mike ✓) / all sprint PRs, then ✅ МОЖНА / ⏳ ЧЕКАЙ for Mike.
