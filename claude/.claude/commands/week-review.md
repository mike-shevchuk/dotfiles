---
description: "Importance-ranked review of everything a person shipped in a week — plain-language what/good/bad per task, a scoreboard, and (for yourself only) a Linear In-Progress→In-Review sync you approve. Works for yourself, a named teammate, or the whole team."
argument-hint: "[empty=you, this week] | <author name> | team | +window: last | W<NN> | <YYYY-MM-DD>..<YYYY-MM-DD>"
---

# Week Review — importance-ranked, plain-language

Describe **everything a person shipped in one work-week, sorted by importance** (not chronologically), in simple words, with an honest **what's good / what's not** per task. End with a scoreboard. For **yourself only**, also reconcile Linear (In Progress → In Review for merged work) — shown first, applied only on explicit "go", never marking Done.

This is the format Mike approved on 2026-08-28. It is the review sibling of `/week-recap` (which is by-day git activity) — this one ranks by product impact and judges quality.

Terminal output only. Never posts to GitHub. The only write is the optional Linear status sync (self only), and only after approval.

## Resolve target + window

The argument is `$ARGUMENTS`. Split it into an optional **author** token and an optional **window** token (either order; either may be omitted).

**Author:**
- **empty** → yourself. `AUTHOR=$(git config user.name)`, and this is the only mode that offers the Linear sync.
- **`team`** / `all` → every contributor with commits in the window; render one ranked section per person, biggest contributor first. No Linear sync in team mode.
- **anything else** → treat as a git author name/substring (match against `git shortlog -sne`). Read-only: describe their shipped work, **no Linear sync** (per `feedback_only_my_tasks.md` — never mutate someone else's tickets).

**Window** (Mike's convention, macOS BSD `date`; identical to `/week-recap`):
- **empty** → current week. `DOW=$(date +%u)`; `START=$(date -v-$((DOW-1))d +%Y-%m-%d)`; `END=now`.
- **`last`** / `минулий` → previous week.
- **`W<NN>`** → **W1 = first Mon–Sun week of January** (first Monday starts W1), NOT ISO-8601. First Monday, then `START = first_monday + (NN-1)*7`.
- **`<YYYY-MM-DD>..<YYYY-MM-DD>`** → explicit, verbatim.

Compute the header week number with the day-of-year method from `/week-recap` (never epoch seconds — DST off-by-ones it; `10#` forces base-10). Sanity: `2026-04-13 → W15`, `2026-08-28 → W34`.

## Gather (in parallel)

```bash
git fetch origin --quiet 2>/dev/null
```

**1. Merged PRs by the author in the window** (this is the spine — most shipped work is a PR):
```bash
gh pr list --author "<login-or-@me>" --state merged --limit 80 \
  --json number,title,mergedAt,additions,deletions,changedFiles \
  --jq ".[] | select(.mergedAt >= \"${START}\" and .mergedAt <= \"${END}T23:59:59Z\") | \"#\(.number) | \(.mergedAt[0:10]) | +\(.additions)/-\(.deletions) | \(.changedFiles)f | \(.title)\""
```
For a teammate whose GitHub login you don't know, resolve it from a recent PR (`gh pr list --search "author:..."`) or fall back to commit-author grouping (step 3).

**2. Open PRs opened in the window** (still in flight — list under "+ у роботі", not in totals).

**3. Per-author commits in the window** (for volume + to catch work not yet in a PR):
```bash
git log --all --author="<AUTHOR>" --since="$START 00:00" --until="$END 23:59" \
  --pretty=format:"%h %ad %s" --date=format:"%m-%d %H:%M"
# team mode: git shortlog -sne --all --since="$START" --until="$END 23:59"
```

**4. Linear (self only, or a teammate whose Linear identity is known):**
- self → `mcp__linear__list_issues` assignee `me`, then match each merged PR's `PUN-\d+` to its issue for status.
- teammate → only if their name maps cleanly to a Linear user; otherwise skip Linear and say so. Never guess.

## Rank by importance

Sort every shipped item by **product impact / severity**, NOT by diff size or date. Rubric, highest first:

1. 🔴 **Production / safety** — a live bug that dropped or corrupted something users depend on (esp. emergency/alert/push paths). Small diffs still rank #1 here.
2. 🟠 **Urgent bug** — privilege/access/data-integrity defect flagged Urgent.
3. 🟠 **Flagship feature** — a new customer-driven capability, especially safety-adjacent (emergency intake, notifications).
4. 🟡 **Feature / ops capability** — requested by the team, real value, not safety-critical.
5. 🟡 **Config / integration toggle.**
6. 🟢 **Small UX / flag / chore.**

State the ranking basis in one line up top ("сортовано за впливом на продукт/безпеку, не за розміром коду"). When two items tie, the one on a hotter path (emergency > device > admin > reporting) wins.

## Output (terminal, Ukrainian default)

Per `feedback_terminal_readable_style.md` (short lines, arrows), `feedback_no_mermaid_in_terminal.md` (no Mermaid — Unicode boxes + ASCII only), `feedback_analysis_summary_at_end.md`. Cite files `path:line`, fence with a language, JSON only via `jq`.

### 1. Banner
```text
╔══════════════════════════════════════════════════════════════════╗
║  WEEK REVIEW — <who> · W<NN> · <Mon> → <Fri>                      ║
║  <N> PR merged · <M> commits · <one-line highlight>              ║
╚══════════════════════════════════════════════════════════════════╝
```

### 2. Ranked task descriptions
One block per task, in importance order (🥇🥈🥉 then 4, 5, …). Each block, in **simple words**:
- **Title** — `PUN-XXXX` · PR(s) · a one-line importance tag (`Важливість: критична (безпека)` etc.)
- **Простими словами:** what it does, in plain language a non-engineer gets.
- **Що зробив:** the concrete work (with `file:line` where it sharpens it).
- **Розмір:** churn (`+X/-Y`, files) — and note when a tiny diff carries big weight.
- **✅ Що добре:** genuine strengths — design choices, review rounds survived, correct invariants.
- **⚠️ Що не ідеально:** honest gaps — reworks, bugs caught by review not the author, **unrun dev-smoke**, missing tests, regressions introduced. Never flattery; never invented faults.

Pull the *why* and the good/bad from the PR body, commit trail, and code-review/Bugbot history when available. Keep a ≤10-line PR to 2–3 sentences.

### 3. Also closed / earlier-coded
One line listing tickets moved to Done in the window whose code landed earlier (don't double-count them as this week's build).

### 4. Scoreboard (sorted by importance)
```text
#  PUN/PR         Що                     Розмір      Важл.
────────────────────────────────────────────────────────────
1  1671 #1981     push no-delivery       +32/-10     🔴 крит
2  1672 #1984     admin no-demote        +115/-76    🟠 Urgent
...
```

### 5. One-line honest verdict
Lead with the single most important fact (`feedback_analysis_summary_at_end.md`): what the week delivered, and the one recurring weak spot (stated plainly, not softened).

## Linear sync — SELF ONLY, approval-gated

Only in self mode. After the description, reconcile Linear against reality and **show a plan, then wait for explicit "go"** (`feedback_never_post_without_explicit_go.md`, `feedback_always_show_draft_before_posting.md`):

- For each merged-this-week PR whose Linear issue is still `In Progress` → propose `In Progress → In Review`.
- **Never propose `Done`** — Mike moves work only to In Review; Done is someone else's call (`feedback_linear_no_done.md`).
- List merged PRs with **no `PUN-\d+`** as a tracking gap. Do **not** create tickets for a slice of an already-tracked/Done feature — offer at most to add the parent PUN to the PR body. Only propose a *new* ticket for a from-scratch feature that has none. Never create anything without "go".

Render the plan as a table (Дія → Чому), label it "нічого ще не зроблено", and ask which parts to apply (A / B / both). Apply with `mcp__linear__save_issue` (state change) only on approval.

## Do not
- Do not post to GitHub, comment on PRs, or mark any Linear issue Done.
- Do not run `git commit` / `git push` / `gh pr` write commands.
- Do not sync or mutate a teammate's Linear tickets — teammate mode is read-only.
- Do not rank by diff size — importance = product/safety impact.
- Do not invent strengths or faults; every ✅/⚠️ must trace to the PR/commits/review.
- Do not create Linear tickets for gaps without an explicit "go".

## Sizing
| Week shape | Ranked blocks | Good/bad depth |
|---|---|---|
| Quiet (<20 commits) | top items only | 1–2 lines each |
| Normal (20–80) | all, grouped by feature | 3–5 lines each |
| Heavy (>80, many PRs) | all, lead with 🔴/🟠 | full ✅/⚠️, ~2 screens |

A well-rendered review fits ~2–3 screens.
