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

### Step 3: Analyze new findings

For each NEW bugbot comment (ones not in the known set):

Present each finding with this format:

---

#### {number}. {title}

**Severity:** {Low/Medium/High}
**File:** `{file_path}:{line}`

**What's wrong:**
{Clear explanation of the problem in 2-3 sentences. Explain the actual failure mode -- what breaks, when, and what the user would observe.}

**Why it matters:**
{Explain the real-world impact. Is this a silent data loss? A crash? A security issue? A code smell that makes maintenance harder?}

**Should we fix it?**
{YES / NO / OPTIONAL -- with brief justification}

**Recommended fix:**
{Show the specific code change needed. If there are multiple approaches, show the recommended one first, then mention alternatives.}

```python
# recommended approach
```

{If there's an alternative:}
> Alternative: {brief description of another valid approach}

---

After presenting all findings, ask: "Want me to fix these? I can fix all/specific ones, or skip any you disagree with."

### Step 4: Retry loop

If no new findings found:
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
