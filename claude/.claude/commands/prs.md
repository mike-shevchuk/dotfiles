---
description: "Overview of ALL my open PRs — one row each: PR#(+mirror), CI, open Bugbot findings, pipeline badges (CR/SMP/RPR/JT/REV with commits-ago), worktree, merge readiness"
argument-hint: "(no args — always scans all open PRs authored by me)"
---

# PRs: fleet overview of my open pull requests

When Mike wants to see ALL his in-flight work at once (he runs several
branches/worktrees in parallel), build a one-row-per-PR table.

**Terminal language:** match Mike. **No Mermaid in terminal** — ASCII tables.

## Step 0 — zero-token fast path (gh-dash)

If Mike just wants to LOOK at / browse his PRs (no pipeline badges, no Bugbot
counts asked for) — don't burn tokens on the full scan. Reply with exactly:

> Інтерактивно і без токенів: `just -g dash` (gh-dash TUI — всі PR/issues,
> Enter = деталі, q = вийти). Повний pipeline-огляд з бейджами — `/prs full`.

and STOP. Run the full workflow below when the request implies pipeline state
(badges, bugbot, merge-readiness), or when `$ARGUMENTS` contains `full`.

## Workflow

### Step 1 — collect PRs

```bash
gh pr list --author "@me" --state open \
  --json number,title,headRefName,mergeable,mergeStateStatus,isDraft,url
```

Exclude Bugbot mirrors from the row list (titles starting `REVIEW:`) — they are
shown as `(+N)` next to their base PR instead. Detect each PR's mirror: PR N+1
titled `REVIEW:*` (confirm via `gh pr view $((N+1)) --json title`).

### Step 2 — per-PR signals (parallelize where possible)

For each PR:

1. **CI** — `gh pr checks <N>`: summarize to ✅ / ❌ / 🔄 (running) / ⚪ none.
2. **Open Bugbot findings** — unresolved review threads on the mirror:
   ```bash
   gh api graphql -f query='query{repository(owner:"<owner>",name:"<repo>"){pullRequest(number:<mirror>){reviewThreads(first:100){nodes{isResolved}}}}}' \
     --jq '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved|not)]|length'
   ```
   Show `🐛N` when >0, `—` when clean or no mirror.
3. **Pipeline badges** — read `/tmp/claude/pipeline-<branch>.json` (branch with
   `/`→`-`). Render `CR✓ SMP✓-2 RPR· JT✓ REV✓` (✓-N = done N commits ago via
   the stamp's `head` anchor + `git rev-list --count`, computable only if the
   branch exists locally). No state file → `(no state — run /pr-state there)`.
4. **Worktree** — match the branch against `git worktree list` to show WHERE
   the PR is checked out (short path or `—`).
5. **Staleness vs main** — `git rev-list --count origin/<branch>..origin/main`
   = commits main is ahead (rebase pressure). Skip if remote branch missing.

### Step 3 — print

Sort: PRs with ❌ CI or 🐛 findings first (need attention), then by number desc.

```
PR fleet · 3 open · 1 needs attention
┌──────────────┬──────────────────────┬────┬────┬──────────────────────────┬─────────────┬───────┐
│ PR           │ branch               │ CI │ 🐛 │ pipeline                 │ worktree    │ ready │
├──────────────┼──────────────────────┼────┼────┼──────────────────────────┼─────────────┼───────┤
│ #1535(+1536) │ card-zone-clamp      │ ✅ │ —  │ CR✓ SMP✓-2 RPR· JT✓ REV✓ │ wt:card-…   │ CLEAN │
└──────────────┴──────────────────────┴────┴────┴──────────────────────────┴─────────────┴───────┘
```

After the table: **per-PR next action** — one bullet each ("#1535: only RPR
pending → /review-pr-eng 1535 or stamp"; "#1540: 🐛2 open → check cursor
bugbot"). Lead with the PR that needs attention most.

End with a Summary block (3–7 bullets, biggest number first).

## Rules

- **Read-only** — never posts, pushes, merges, or stamps. To refresh one PR's
  pipeline state, run `/pr-state` in that branch's worktree.
- Only PRs authored by Mike (`--author "@me"`) — per the only-my-tasks rule.
- Keep it fast: if >5 PRs, fetch checks/threads via one `gh` call per PR max,
  and say so if something was skipped.
