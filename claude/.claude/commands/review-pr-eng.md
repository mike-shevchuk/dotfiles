---
description: "Full code review of a PR: analyze diff, find bugs, post English developer-friendly review on GitHub"
argument-hint: "<PR number>"
---

# Review PR #$ARGUMENTS

Perform a full code review of PR #$ARGUMENTS and post a detailed, educational review comment on GitHub.

## Step 1: Gather context

Run these commands in parallel:

```bash
# Get PR metadata
gh pr view $ARGUMENTS --json baseRefName,headRefName,title,headRefOid,files

# Get the diff
gh pr diff $ARGUMENTS

# Get existing reviews (to see previous feedback and style)
gh api repos/{owner}/{repo}/pulls/$ARGUMENTS/reviews --jq '.[] | {state: .state, body: .body}'

# Get repo owner
gh repo view --json nameWithOwner --jq '.nameWithOwner'
```

## Step 2: Verify branch cleanliness

Fetch and compare the PR branch against the base branch:

```bash
git fetch origin {headRefName}
git diff origin/{baseRefName}..origin/{headRefName}
```

Check for overlapping changes — if the diff contains files or changes that don't belong to this PR's purpose (based on the title), the branch needs a rebase.

## Step 3: Read source files

For every file in the diff, read the FULL file to understand context:
- What functions surround the change?
- Who calls the changed code?
- Are there related files (imports, utilities, models)?

Also check for:
- Remaining instances of bugs/typos the PR claims to fix: `grep -rn "pattern" --include="*.py"`
- Template variables that need matching renames
- Related code that should change together

## Step 4: Analyze for bugs

Look for these categories:
1. Logic errors — wrong conditions, missing returns, off-by-one
2. Dead code — unused variables, unreachable code after early return
3. Type mismatches — comparing enum with string, wrong argument types
4. UX issues — confusing messages, blocking access unnecessarily
5. Naming — typos, misleading names, inconsistent conventions
6. DRY violations — copy-pasted code that should be extracted
7. Missing edge cases — negative numbers, empty strings, None values
8. Overlap with other PRs — changes that don't belong here
9. Debug leftovers — print statements, >>>> markers, temporary logs
10. Security — injection, hardcoded secrets, unsafe deserialization
11. **Readability & professional style** — teach PEP 8 and Pythonic idioms so the author levels up with every review:
    - **PEP 8**: spaces around `=` in assignments (`x = 1`, not `x=1`), 4-space indentation (no 8-space accidental double-indent under `if`), no trailing whitespace, newline at EOF, two blank lines between top-level defs, single-letter names that shadow builtins (`l`, `I`, `O`) — ruff flags E741
    - **Naming**: names describe what the value *is*, not what it was parsed from (`level_name` not `target_new_level` when the value is a string name, not a Level enum). Verbs for functions, nouns for variables.
    - **Control flow**: flatten nested `try/except` when only one line actually raises; scope `try` narrowly. Use early returns / guard clauses instead of deep pyramids.
    - **Idioms**: `if key in Enum.__members__` over `try: Enum[key] except KeyError`; `.isdigit()` over `try: int(x)` for "is it a number" checks; f-strings over `.format()` / `%`; `pathlib.Path` over `os.path`.
    - **Order of operations**: validate cheap things (parsing, enum lookup) *before* expensive things (disk I/O, DB reads). A bad input should fail fast without touching storage.
    - **Concurrency**: independent `await`s (e.g. notifying user + replying to admin) should run concurrently via `asyncio.gather(..., return_exceptions=True)`, not sequentially — and gather lets you isolate per-task failures so one broken side-effect doesn't masquerade as a total failure.
    - **Error handling**: `loguru`'s `.exception()` already captures the traceback — don't duplicate with `f"...: {e}"`. Broad `except Exception` should be the outermost net, not a catch-all that hides specific bugs (e.g. Telegram send errors swallowing a successful DB update).
    - **Consistency with house style**: match patterns already used in sibling handlers (`Level.__members__`, `get_name_from_pydantic`, etc.) instead of inventing new ones.

Frame these as *teaching moments* — the reader should walk away understanding the principle, not just the fix. Cite PEP 8 / PEP 20 (Zen of Python) or the canonical docs where relevant.

## Step 5: Write and post the review

### CRITICAL: Review style rules

The review MUST follow this exact style:

- **Language:** English ONLY
- **Tone:** You are a **senior engineer mentoring a junior**. Be clear and educational — explain WHY something is wrong, not just WHAT, in plain words with the real-life impact (what breaks for the user/on-call at 3am). Do NOT cite PEP numbers. Show the fix *and* the principle behind it.
- **Visuals:** every MAJOR finding embeds a Mermaid diagram INSIDE the finding (flow of the bug, before/after data path) — GitHub renders Mermaid natively.
- **Structure:**
  - Start with `## Review: {emoji} {Approve/Request Changes}`
  - Use emoji section headers: 🚨 (critical), 🐛 (bug), 🗑️ (dead code), 📉 (perf), 💡 (suggestion), 📋 (style), ✅ (good)
  - Number each finding: `### 1. 🚨 Title`
- **Severity badge + score (0-100)** on EVERY finding — a colored circle and numeric score showing how critical the issue is:
  - 🔴 **Critical (80-100)** — blocker, must not merge (data loss, security, broken build)
  - 🟠 **Serious (60-79)** — bug or issue that will affect production
  - 🟡 **Moderate (30-59)** — not a bug, but may cause problems in the future
  - 🟢 **Minor (0-29)** — style, naming, code quality improvement
  - Format: `### 1. 🚨 Title 🔴 85/100`
  - The score reflects nuance WITHIN the color band (e.g., 🟠 65/100 is less urgent than 🟠 78/100)
- **Code examples:** Show the broken code, explain the problem, show the fix
- **"Note:" blocks** after each finding — teach the underlying programming principle
- **Tables** for comparisons (before/after, different approaches, edge cases)
- **"Action items"** section at the end — numbered checklist of what to fix, sorted by severity (🔴 first)
- **"Summary"** table — status of each finding with severity column:

```markdown
| # | Finding | Type | Severity | Status |
|---|---------|------|----------|--------|
| 1 | Description | 🚨 Critical | 🔴 95/100 | Must fix |
| 2 | Description | 🐛 Bug | 🟠 70/100 | ... |
| 3 | Description | 💡 Suggestion | 🟡 45/100 | ... |
| 4 | Description | 📋 Style | 🟢 15/100 | ... |
```

### Decision logic

- If ALL issues are cosmetic/optional → verdict ✅ Approve (with suggestions)
- If there are real bugs or the branch needs rebase → verdict 🔄 Request Changes
- If fixes from previous review were applied successfully → acknowledge each one with ✅

### Show draft, then post (GATED — never auto-post)

1. Read ALL existing bot comments (Cursor Bugbot, Gemini) FIRST and give each a
   verdict + score before writing your own findings.
2. Render the FULL review body in the terminal. Do NOT post yet.
3. Wait for an explicit affirmative ("go", "post", "пости"). Re-invoking this
   command is NOT approval. Anything else = stay stopped.
4. On go — pick the posting method:
   - **Mike's own PR** → `gh pr comment $ARGUMENTS --body-file <tmp>` — never
     `--approve`/`--request-changes` on self-PRs (GitHub blocks self-review anyway).
   - **Someone else's PR** → `gh pr review $ARGUMENTS --{approve|request-changes} --body-file <tmp>`.
   Use a temp file / HEREDOC for the body to preserve formatting.
5. After a successful post, stamp the pipeline state so the statusline badge
   (`/pr-state` → `RPR`) reflects it:

```bash
~/.claude/pipeline-stamp.sh stamp review-pr pr-comment
```

### Previous review references

If there were previous reviews on this PR, reference them:
- "As I mentioned in my previous review — ..."
- "I can see you fixed {X} from the last review — great work! ✅"
- Don't repeat findings that were already addressed

### Important rules

- ALWAYS read source files before analyzing — never review from diff alone
- Check the FULL codebase for related issues (grep for patterns)
- Be honest — not everything needs fixing, say so explicitly
- Acknowledge good work — if something was done well, say it
- If a finding is about pre-existing code (not changed in this PR), note it explicitly
- One review comment per invocation — don't post multiple reviews
- End with clear action items the developer can follow
