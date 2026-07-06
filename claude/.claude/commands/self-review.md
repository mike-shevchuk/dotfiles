---
description: "Honest self-review of Mike's performance over a window — strengths, problems, patterns, and concrete pro-notes to level up"
argument-hint: "[empty=this week] | last | W<NN> | <YYYY-MM-DD>..<YYYY-MM-DD> | month | quarter"
---

# Self-Review — Honest Performance Analysis

Produce a brutally honest, mentor-quality self-review of Mike's work over a window. Three layers:

1. **What you did well** (strengths) — specific, evidence-backed, not flattery
2. **What's holding you back** (problems) — recurring patterns, debt, missed opportunities
3. **Pro-notes** — concrete, actionable advice to level up. No "you should be better" — actual mechanics

Terminal output only. Never posts anywhere.

This is not a cheerleader summary. Mike wants to improve — surface uncomfortable truths.

## Resolve the window

The argument is `$ARGUMENTS`. Resolve `START`/`END`:

- **empty** → current week (Mon 00:00 → now)
- **`last`** → previous week (Mon-Sun)
- **`W<NN>`** → Mike's week convention (W1 = first Mon-Sun of January). Use the same algorithm as `/week-recap`.
- **`<YYYY-MM-DD>..<YYYY-MM-DD>`** → explicit range
- **`month`** → last 30 days
- **`quarter`** → last 90 days

Header: `🔍 Self-Review — <window-label>  <START → END>`

## Data sources to gather (in parallel)

Run these concurrently — analysis depends on the full picture:

```bash
# 1. Merged PRs in window — your authorship
gh pr list --author "@me" --state merged \
  --search "merged:$START..$END" \
  --json number,title,mergedAt,createdAt,additions,deletions,body \
  --limit 50

# 2. Open PRs — both fresh and aging
gh pr list --author "@me" --state open \
  --json number,title,createdAt,updatedAt,additions,deletions \
  --limit 30

# 3. PRs you reviewed (not authored) — collaboration signal
# (--merged is a boolean flag; the date filter is --merged-at)
gh search prs --reviewed-by "@me" --merged \
  --merged-at ">=$START" --json number,title,author --limit 30

# 4. Linear active issues — assignee:me, status≠Done/Cancelled
# Use mcp__linear__list_issues; if output too large, save and slice

# 5. Sprint notes for context
ls -t ~/zettelkasten/claude_code/rescue-serverless/sprints/*.md | head -5
ls -t ~/zettelkasten/comb-notes/weekly_staff/*.md | head -3
```

## Analysis dimensions

For each merged PR, compute:

- **Days open** (mergedAt - createdAt)
- **Size category**: tiny (<50 lines), small (50-200), medium (200-800), large (800-2000), epic (2000+)
- **Linear linkage**: explicit PUN refs in title/body? Or backfill-needed?
- **Stand-alone vs epic-member**: groupable with sibling PRs?
- **Customer-impact level**: bugfix (negative→neutral) · feature (neutral→positive) · refactor (invisible→positive) · infra (invisible)

For each open PR, compute:

- **Days open right now**
- **Days since last update** (stale signal)
- **Self-pickup signal**: stale > 14 days = personal blocker, not external review

For Linear:

- Count tickets at each status (Todo / In Progress / In Review / Backlog / Done)
- Identify **hygiene debt**: PRs merged but tracking issue still In Progress (the W20-overcount class)
- Identify **carryovers**: tickets sitting in same status > N sprints (3+ weeks = chronic)

## Output format — three sections

### Section 1: ✅ What you did well

3-7 evidence-backed strengths. Each with:
- **One-line strength** (skill, not adjective)
- **Specific evidence** (PR #, ticket ID, line counts, days saved)
- **Why this matters** (impact angle — customer, team, architecture, future-self)

NOT generic praise ("nice job"). Be specific:
- ❌ "Great work this sprint"
- ✅ "Monitoring epic closure: 6 PRs across W21-W23 closed PUN-1358 noise-reduction story. State-fingerprint cooldown in #1521 is an architectural pattern, not just a bugfix — it'll outlive this sprint."

### Section 2: ⚠️ What's holding you back

3-7 honest problems. Each with:
- **The problem** (pattern, not single incident)
- **Frequency / scope** (X weeks running, Y times this month)
- **Cost** (what it actually costs: trust, time, regression risk, mental load)
- **NOT a soft fix** — name the pattern directly

Categories to consider:
- **Aging PR debt** (#1273 = 38 days = pattern)
- **Linear hygiene debt** (PRs merged + tickets stale = overcount risk)
- **Carryovers** (PUN-1061 8 weeks = avoidance pattern)
- **Decision deferral** (PUN-1304 5 weeks "decide" = decision-avoidance)
- **Customer waiting** (PUN-1422 1 week after meeting = response-time signal)
- **Burnout/cadence** (9 PRs / 3 days = unsustainable peak)
- **Communication gaps** (action items unspoken, scope creep silent)

Example wording (use this tone):
- ❌ "Sometimes PRs stay open too long"
- ✅ "PR #1273 is now 38 days / 7th week. I've written 'close it' 5 weeks running. This isn't a code problem — it's your demonstrated inability to close *this specific PR*. Cost: reviewers stop taking your other PRs seriously."

### Section 3: 🎯 Pro-notes — how to level up

3-5 concrete mechanics. Each with:
- **Behavior change** (specific action, not advice)
- **Implementation hook** (when/where to do it — Monday morning ritual, after every PR, etc.)
- **What to measure** (signal that says it's working)
- **Why this beats the alternative** (rationale grounded in actual cost)

NOT motivational. Mechanical.

Examples:
- ❌ "Be more disciplined about closing PRs"
- ✅ "**Weekly stale-PR triage** every Friday before sprint close: `gh pr list --author @me --search 'is:open updated:<7days'`. Any PR > 7 days → merge or close. Make it a calendar item. Measure: count of >7d open PRs at end of each Friday should be 0."

- ❌ "Track your tickets better"
- ✅ "**Monday-morning Linear sync** as 5-minute ritual: every merged PR last week → move ticket to In Review. Stops the W20-overcount class permanently. Measure: at start of /sprint, no stale 'In Progress' tickets for merged PRs."

- ❌ "Don't burn out"
- ✅ "**3-PRs-per-day cap rule.** If you shipped 3 PRs by Wednesday, Thursday is for closing review feedback or 1 small PR max. No 4-PR days. Burnout signals appear 7-10 days after peak; preempt instead of reacting. Measure: PR/day standard deviation across the sprint should be <2."

## Tone for the entire output

- Direct mentor voice — like a senior dev who has earned the right to say uncomfortable things
- No padding ("It's also worth noting that..." → cut)
- No false equivalence (don't balance 1 strength with 1 weakness — match volume to reality)
- Evidence > opinion (cite PR numbers, ticket IDs, day counts)
- End with **one prioritized "next 7 days" action item** — the single highest-leverage change to make
- If `/coaching on` is active THIS session, append the `📚 English coaching` block at the end; otherwise skip (coaching is default-OFF)

## What NOT to include

- Generic motivational language ("believe in yourself", "you've got this")
- Comparisons to other developers (this is Mike's review, not relative ranking)
- Future predictions ("if you keep this up...")
- Excuses for the user ("it's understandable that...")
- Soft-pedaling (if PR #1273 is bad, say so)

## Footer

End with one line:
```
📍 Window: <START>..<END> · PRs: <N> merged / <M> open · Tickets touched: <K>
```
