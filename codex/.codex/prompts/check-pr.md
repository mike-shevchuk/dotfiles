---
description: "Monitor PR for Cursor Bugbot review comments, analyze and recommend fixes"
argument-hint: "<PR number>"
---

# Check PR Bugbot Review

Monitor PR #$ARGUMENTS for new Cursor Bugbot review comments. Analyze each finding and provide actionable recommendations.

## Workflow

### Step 1: Get current state

Run this command to get ALL existing bugbot comments and track which commits have been reviewed:

```
gh api repos/{owner}/{repo}/pulls/{PR}/comments --jq '[.[] | select(.user.login == "cursor[bot]")] | group_by(.original_commit_id[:8]) | map({commit: .[0].original_commit_id[:8], count: length, findings: [.[].body | split("\n") | map(select(startswith("###"))) | .[0]]})'
```

Also get the latest commit on the PR:
```
gh pr view {PR} --json headRefOid --jq '.headRefOid[:8]'
```

Store the total count of bugbot comments as `known_count`.

### Step 2: Check for new comments

Query bugbot comments and compare count to `known_count`.

If count > known_count: **new findings detected** -- go to Step 3.
If count == known_count: **no new findings** -- go to Step 4.

### Step 3: Deep analysis of new findings

For each NEW bugbot comment (ones not in the known set):

#### 3a. Read the actual source code

Before analyzing, ALWAYS:
1. Read the full file where the finding is located (not just the diff)
2. Read any related files (imports, callers, tests) to understand the full context
3. Check git blame -- is this new code from this PR or pre-existing?

```
gh pr view {PR} --json files --jq '.files[].path'
```

#### 3b. Contextual analysis

For each finding, answer these questions internally before presenting:
- Does this finding apply to the ACTUAL code, or is bugbot hallucinating?
- Is the surrounding code already handling this case (e.g., try/except upstream)?
- Are there existing tests that cover this scenario?
- Does this pattern exist elsewhere in the codebase? If so, is it a systemic issue?
- What's the blast radius if this bug triggers in production?

#### 3c. Present findings

Present each finding with this format:

---

#### {number}. {title}

**Importance: {0-100}/100** 🔴/🟡/🟢
- 0-30 🟢 = noise, cosmetic, style nit
- 31-60 🟡 = code smell, potential issue, worth noting
- 61-85 🔴 = real bug, will cause problems
- 86-100 🔴🔴 = critical, data loss / security / crash in prod

**Severity:** {Critical/High/Medium/Low/False Positive}
**File:** `{file_path}:{line}`
**Introduced in:** {this PR / pre-existing code}

**What's wrong:**
{Clear explanation of the problem in 2-3 sentences. Explain the actual failure mode -- what breaks, when, and what the user would observe.}

**Deep context:**
{What does the surrounding code do? Who calls this function? What data flows through here? Is there already error handling nearby that bugbot missed?}

**When this breaks — real scenarios:**
{Give 2-3 concrete examples of when this bug will trigger:}
1. {Scenario 1: e.g., "User uploads a file > 10MB while on slow 3G connection, the timeout fires before upload completes → silent data loss"}
2. {Scenario 2: e.g., "Two admins edit the same record simultaneously → race condition overwrites changes"}
3. {Scenario 3 if applicable}

**Expert opinion:**
{Write as a senior engineer with 10+ years of experience. Be honest and direct. Examples:}
{- "This is a textbook race condition. I've seen this exact pattern cause production incidents at scale. Fix it now."}
{- "Bugbot is being paranoid here. This path only triggers during init, and the caller already validates input. Skip."}
{- "Technically correct finding, but the probability is extremely low and the impact is a retry. I'd file a tech debt ticket, not block the PR."}

**Why it matters:**
{Explain the real-world impact. Is this a silent data loss? A crash? A security issue? A code smell that makes maintenance harder?}

**Existing coverage:**
{Are there tests for this? Does the codebase handle this elsewhere? Is there a pattern we should follow?}

**Verdict:** {YES fix / NO skip / OPTIONAL / FALSE POSITIVE -- with brief justification}

**Recommended fix:**
{Show the specific code change needed. If there are multiple approaches, show the recommended one first, then mention alternatives.}

```python
# recommended approach
```

{If there's an alternative:}
> Alternative: {brief description of another valid approach}

---

#### 3d. Prepare PR review comments

For each finding, prepare a GitHub PR review comment:

**Draft comment for finding #{number}:**
```
{Concise, professional comment for the PR. Include:
- What the issue is (1-2 sentences)
- Importance score (X/100)
- Suggested fix (short code snippet if applicable)
- Whether it's blocking or non-blocking}
```
**Post this comment?** ⬜ YES / ⬜ NO
{Recommend YES if importance >= 50, NO if < 50 or false positive}

IMPORTANT: Do NOT post any comments automatically. Present ALL draft comments first and wait for explicit approval on which ones to post. When approved, post using:
```
gh api repos/{owner}/{repo}/pulls/{PR}/comments -f body="{comment}" -f commit_id="{sha}" -f path="{file}" -F line={line}
```

#### 3e. Summary table

After all findings, show a summary:

| # | Finding | Importance | Severity | Verdict | Post comment? | Effort |
|---|---------|-----------|----------|---------|---------------|--------|
| 1 | {title} | 85/100 🔴 | High | FIX | ⬜ YES | ~5 min |
| 2 | {title} | 20/100 🟢 | Low | SKIP | ⬜ NO | - |

**Score: {X}/{total} findings need fixing**
**Comments to post: {Y}/{total} (awaiting your approval)**

Then ask: "Want me to fix these? I can fix all/specific ones, or skip any you disagree with. Also — which PR comments should I post? (all / none / specific numbers)"

### Step 4: Independent code review (beyond bugbot)

Do NOT rely only on bugbot findings. Perform your OWN review of all changed files in the PR:

```
gh pr diff {PR}
```

Analyze the diff independently and look for issues bugbot MISSED:

#### What to look for:
1. **Logic errors** — wrong conditions, off-by-one, inverted checks, missing early returns
2. **Error handling** — unhandled exceptions, swallowed errors, missing try/catch, no fallback
3. **Security** — SQL injection, XSS, hardcoded secrets, unsafe deserialization, open redirects
4. **Performance** — N+1 queries, unnecessary loops, missing indexes, large payloads without pagination
5. **Race conditions** — shared state without locks, TOCTOU bugs, concurrent writes
6. **Data integrity** — missing validation, nullable fields used without checks, no transaction where needed
7. **API contract** — breaking changes in request/response, missing fields, wrong status codes
8. **Dead code / unused imports** — leftover from refactoring
9. **Missing tests** — new logic paths without test coverage
10. **Naming / readability** — confusing variable names, overly complex functions that should be split

#### Present own findings using the SAME format as Step 3c (with importance score, scenarios, expert opinion, etc.)

Mark these findings clearly:
> 🔍 **Source: Independent review** (not from bugbot)

#### Compare with bugbot:
- If bugbot missed something important (importance >= 50), highlight: "⚠️ Bugbot missed this"
- If your finding overlaps with bugbot, note: "✅ Confirmed bugbot finding #{N}"
- If you disagree with a bugbot finding, note: "❌ Disagree with bugbot — {reason}"

Add own findings to the same summary table (Step 3e) with source column.

### Step 5: Retry loop

If no new bugbot findings found (own review still runs every cycle):
1. Log: "No new bugbot findings. Checking again in 4 minutes... ({retry_number}/4)"
2. **First check immediately** (don't sleep before the first check)
3. Sleep 4 minutes
4. Check again (Step 2)
5. Repeat up to 4 retries total

If after 4 retries still no new findings:
- Log: "No new bugbot findings after 4 retries. PR #N looks clean on commit {hash}."
- Show summary: total findings across all rounds, how many fixed, how many acknowledged

### Important rules

- **Check FIRST, sleep AFTER** -- never sleep before the first check
- When checking, always compare comment count to detect new ones (don't rely on commit hash alone -- bugbot can post late)
- Present findings in a readable format with real analysis, not just parroting the bugbot text
- Give honest recommendation on each finding -- not everything needs fixing
- If a finding is about pre-existing code not changed in this PR, note that explicitly
- Use `f'{variable=}'` style in any code examples (project preference)
