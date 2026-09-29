---
description: "Terminal-friendly BEFORE/AFTER recap for a PR or a commit — what was done, what was found, what's left"
argument-hint: "<PR number> | <commit hash>"
---

# PR / Commit Recap

Show a readable terminal view of what changed, organised as side-by-side BEFORE / AFTER blocks, plus a DONE vs TODO action table. Works for either a GitHub PR (e.g. `1379`) or a git commit hash (e.g. `5683fc8b` or `5683fc8b0edaf00e6367cb9df7649c9b3bb7bc7c`).

## Detect input type

The argument is `$ARGUMENTS`. Detect:

- If it matches `^\d{1,5}$` and `gh pr view $ARGUMENTS --json number` succeeds → **PR mode**
- Else if it matches `^[0-9a-f]{7,40}$` and `git cat-file -e $ARGUMENTS^{commit}` succeeds → **COMMIT mode**
- Else: print `failed: argument is neither a PR number nor a reachable commit hash` and stop.

## Gather data

Run in parallel:

**PR mode:**
```bash
gh pr view $ARGUMENTS --json number,title,author,baseRefName,headRefName,state,mergeable,additions,deletions,changedFiles,headRefOid,body,commits
gh pr diff $ARGUMENTS
gh api repos/{owner}/{repo}/pulls/$ARGUMENTS/comments --jq '[.[] | select((.user.login == "cursor[bot]") or (.user.login | contains("bot"))) | {author: .user.login, path: .path, line: .line, body: .body}]'
gh api repos/{owner}/{repo}/pulls/$ARGUMENTS/reviews --jq '[.[] | {author: .user.login, state: .state, body: .body}]'
```

**COMMIT mode:**
```bash
git show --stat $ARGUMENTS
git show $ARGUMENTS
git log -1 --pretty=fuller $ARGUMENTS
```

## Output structure

Render to **terminal stdout** (no posting anywhere). Markdown rendered by the Codex TUI gives you syntax highlighting on code fences with a language tag, so always tag fences (`python`, `bash`, `diff`, `json`, `yaml`).

Follow this exact section order. Skip a section only if it has no content.

### 1. Header banner

Show identity, scope, state. Use Unicode box-drawing (`╔═╗║╚╝`). Mode-specific:

**PR mode:**
```
╔══════════════════════════════════════════════════════════════════════════════╗
║  PR #1379 — feat(devicelink): compact photo URL storage                      ║
║  Author: mike-shevchuk · State: OPEN · Mergeable: ✅                         ║
║  9 commits · 2 files · +98/-7 · base: main ← worktree-photo-url-compact      ║
║  Bot reviews: 1 (Cursor BugBot — 1 medium finding)                           ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

**COMMIT mode:**
```
╔══════════════════════════════════════════════════════════════════════════════╗
║  Commit 5683fc8b — perf(legacy-fields): scope model_dump to fields-to-update ║
║  Author: Mike · Date: 2026-05-19 17:42:31 +0300                              ║
║  Branch: worktree-photo-url-compact · 1 file · +19/-13                       ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### 2. ✅ DONE blocks

For every substantial change in the diff, render ONE BEFORE/AFTER block. Use side-by-side ASCII boxes for short snippets (≤6 lines each side) and stacked markdown code fences for long snippets.

**Decision rule — pick the right layout per change:**

| Snippet size | Layout | Syntax highlighting |
|---|---|---|
| Both sides ≤6 lines | Side-by-side ASCII box | Plain (TUI doesn't tokenize box content) |
| Either side >6 lines | Stacked markdown fences (BEFORE then AFTER) | ✅ Full (use ```python / ```bash / ```diff) |
| Pure diff with small additions | Single ```diff fence (no BEFORE/AFTER split) | ✅ Red/green |

**Side-by-side template** (use Unicode `┌┬┐├┼┤└┴┘│─`):

```
## ✅ DONE #N — <one-line title>

┌──────────────────────────────────────────┬──────────────────────────────────────────┐
│ BEFORE (<source>)                        │ AFTER (<source>)                         │
├──────────────────────────────────────────┼──────────────────────────────────────────┤
│ <code line>                              │ <code line>                              │
│ ...                                      │ ...                                      │
├──────────────────────────────────────────┼──────────────────────────────────────────┤
│ <impact line — what this state means>    │ <impact line — what this state means>    │
└──────────────────────────────────────────┴──────────────────────────────────────────┘
```

Columns are 44 chars wide (matches 90-col terminal). Inside the box use plain text — no markdown rendering.

**Stacked template** (for longer snippets — keeps syntax highlighting):

````
## ✅ DONE #N — <one-line title>

**File:** `<path>:<line>`

BEFORE:
```python
<code>
```

AFTER:
```python
<code>
```

**Why:** <one or two sentences on what this state proves / saves / unlocks>
````

**Pure-diff template** (when the change is a single hunk and BEFORE/AFTER would be redundant):

````
## ✅ DONE #N — <one-line title>

```diff
<diff hunk straight from `git show`>
```

**Why:** <one or two sentences>
````

**What counts as a DONE block:**

- A new function / class / decorator
- A behaviour-changing refactor (e.g. `getattr` → `model_dump`)
- A performance fix (call out before-cost vs after-cost)
- A storage / schema change (call out byte savings, WCU shift)
- A migration strategy (call out self-healing, no-deploy-step)
- A cleanup that reduces footprint (call out lines removed)
- House-rule compliance (commit message format, cost section, test-file-local)

Aim for 4–8 DONE blocks for a typical PR. For a single-commit recap, 1–3 blocks is usually right.

### 3. 🔍 FINDINGS blocks

If the PR has bot review comments (Cursor BugBot, CodeRabbit, Gemini) OR human reviews with `state == "CHANGES_REQUESTED"`, surface them. Skip this section in COMMIT mode unless the commit is on a branch with an open PR — then optionally peek at that PR's reviews.

Use BEFORE/AFTER framing where natural:

- **THEORETICAL CONCERN vs EMPIRICAL TEST** — when a bot raises a hypothesis. Run the test if possible, show both.
- **CURRENT vs SUGGESTED** — when the finding proposes a code change. Show both states.
- **WRONG vs RIGHT** — for clear bugs.

Each FINDING gets a severity badge: 🔴 80-100 critical · 🟠 60-79 serious · 🟡 30-59 moderate · 🟢 0-29 minor.

```
## 🔍 FINDING #N — <title> (<emoji> <score>/100)

┌──────────────────────────────────────────┬──────────────────────────────────────────┐
│ THEORETICAL CONCERN (BugBot says)        │ EMPIRICAL TEST (verified just now)       │
├──────────────────────────────────────────┼──────────────────────────────────────────┤
│ <bot's claim, paraphrased)               │ <actual test output, with ✅ or ❌>      │
├──────────────────────────────────────────┼──────────────────────────────────────────┤
│ Risk: <impact>                           │ Risk: <actual>                           │
│ Action: <what bot recommends>            │ Action: <what you'll do instead>         │
└──────────────────────────────────────────┴──────────────────────────────────────────┘
```

Engage with every existing bot finding — explicit verdict (valid / invalid / optional) and severity score. Don't quietly downgrade. Per project rule `feedback_review_pr_read_bot_comments.md`.

### 4. 📋 ACTION ITEMS table

A single Markdown table — TUI renders this nicely. Two zones: Done (top) and TODO (bottom).

```markdown
| #  | Item                                          | Status        | When        |
|----|-----------------------------------------------|---------------|-------------|
| 1  | <DONE item>                                   | ✅ committed  | —           |
| 2  | <DONE item>                                   | ✅ inherited  | —           |
|----|-----------------------------------------------|---------------|-------------|
| F1 | <Finding #1 follow-up>                        | ⚪ TODO opt    | now         |
| F2 | <Finding #2 follow-up>                        | 🆕 next PR    | follow-up   |
| M  | Merge PR #N                                   | ⚪ READY       | unblocked   |
```

Use a horizontal rule (`|---|`) row between Done and TODO so the eye separates them.

### 5. 🎯 NEXT (what you, the assistant, will do)

Final box stating the immediate action available and what input unblocks it. Always end with the gate per `feedback_never_post_without_explicit_go.md`.

```
╔══════════════════════════════════════════════════════════════════════════════╗
║ Suggested next action: <one-line command or decision>                        ║
║                                                                              ║
║ Waiting for one of:                                                          ║
║   "go" / "пости" / "yes"   → execute                                         ║
║   "<feedback>"             → adjust and re-render                            ║
║   "no"                     → stop                                            ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

## Rendering rules — keep terminal readable

| Rule | Why |
|---|---|
| 90-col total width (44-col columns when side-by-side) | Fits standard terminal without wrap |
| Unicode box-drawing (`╔═╗┌─┐│├┼┤`) | Renders identically across terminals; no GitHub Mermaid (per `feedback_no_mermaid_in_terminal.md`) |
| Code fences ALWAYS tagged (```python, ```bash, ```diff, ```json) | TUI syntax highlighting only fires with language tag |
| `bat --color=always --paging=never --language=python` for ad-hoc highlighted output | When TUI doesn't pick up the fence (rare); never `bat --paging=always` per `feedback_no_paging_default.md` |
| Each BEFORE/AFTER block ends with an impact line | Reader sees the why, not just the what |
| Finding sections include severity badge inline `(🟡 50/100)` | Reader scans severity without re-reading text |
| Comments preserved in code samples | Per `feedback_simplify_keep_comments.md` — don't strip "why" context when showing diffs |
| Files cited as `path:line` (clickable in TUI) | Per project tone rule |
| No raw JSON dumps | If you need JSON, pipe through `jq --color-output .` per `feedback_jq_format_all_json.md` |

## Detection heuristics for "what counts as DONE"

When walking the diff:

1. **New function / method / class** → DONE block. BEFORE: "n/a" (or pre-existing manual approach if grep-able). AFTER: the function signature + docstring.
2. **Loop / branch refactor** → DONE block. BEFORE: the old loop body. AFTER: the new one. Impact line: what the refactor saves (cycles, allocations, branches).
3. **New decorator on a class** (`@field_serializer`, `@model_validator`, `@cached_property`) → DONE block. Frame as "manual caller code BEFORE" vs "Pydantic auto-runs AFTER" or similar.
4. **Field addition with `serialization_alias` / `validation_alias` / `default`** → DONE block. Show old `Field(None, ...)` vs new `Field(None, ..., serialization_alias=...)`. Impact line: byte savings, schema migration cost.
5. **Comment block addition** (>5 lines of `# ...`) → mention as a sub-bullet under the relevant DONE block (don't dedicate a whole block to comments).
6. **Test file added / removed** → DONE block IF the change reflects a house-rule (e.g. test moved to `test_local_*.py` per `feedback_no_tests_in_branch.md`).
7. **Commit-level changes:** rebase, force-push, history rewrite — DONE block with BEFORE: commit count / file count, AFTER: same metrics after cleanup.

Heuristic for ordering: most impactful first. Perf optimizations and behaviour changes before pure refactors. House-rule compliance last.

## Do not

- Do not post anywhere. This skill renders to terminal only.
- Do not call `gh pr review` / `gh pr comment` / `git commit` / `git push`.
- Do not run code from the PR (just read it).
- Do not propose code edits without the user asking. The recap describes; the user decides.
- Do not include emoji in code samples unless the original code had them.
- Do not use Mermaid in this skill — terminal only. (Mermaid is fine elsewhere, just not here.)
- Do not invent findings the bots didn't raise. If reviewers said nothing, the FINDINGS section is empty or a single ✅ "No bot findings" line.

## Examples — typical sizing

| PR scope | Header | DONE blocks | FINDINGS | Action items |
|---|---|---|---|---|
| Single-commit hotfix | 1 line | 1–2 | 0 (unless reviewed) | 2–3 |
| Feature PR (5–10 commits, ≤5 files) | 3-4 lines | 4–6 | 0–3 | 6–10 |
| Big refactor (>10 commits, >10 files) | 4-5 lines + GSI / cost callout | 6–10 | depends | 10–15 |
| Commit hash | 1 line | 1 | n/a | 1 (back to branch) |

A well-rendered recap should fit on 1.5–2 screens of terminal output.
