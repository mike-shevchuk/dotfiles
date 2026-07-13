---
description: "Run a sequence of just recipes as an end-to-end smoke trace, capture commands+outputs, and post a clean English markdown comment to the target PR"
argument-hint: "<PR number> [optional plan description]"
---

# Just-Test: end-to-end smoke trace → PR comment

Run an end-to-end smoke trace using `just` recipes against the local lambdas, capture each command + its output, and post a clean markdown trace as a comment on PR #$ARGUMENTS.

**Conversation language:** Ukrainian or English (match the user).
**PR comment language:** ALWAYS English (per project rule). If the user describes the plan in Ukrainian, you translate the descriptions/headings to English before posting.

## Workflow

### Step 1: Establish the test plan

If the user invoked you right after running smoke tests in the conversation, **propose a plan based on the recent context** (which recipes you ran, what they verified). Show the proposed plan as a numbered list and ask for confirmation.

If the conversation has no obvious smoke context, **ask the user**:
- Which justfile recipes to run (in order)
- What to verify between steps (optional `curl GET ...` checks)
- What identifiers / fixtures to use (e.g. `notify_org_id`, `valid_category_id`)
- Whether to seed fresh resources (e.g. fresh org via `notify-create` + `notify-activate`) or reuse existing ones

Wait for explicit "go" / "так" / "запускай" before executing.

### Step 2: Pre-flight

Before running anything:

1. Verify the local lambda(s) are running on the expected ports (e.g. `lsof -ti:8004` for Notify, `:8000` for Admin). If a port is empty, tell the user how to start it (e.g. `jst run_n`, `jst run-all`) and stop.
2. Confirm `just --justfile justfile.v2 --list` resolves the recipe names you plan to call. If a recipe is missing, surface that — DO NOT silently raw-curl as a workaround. Add the recipe to `.just_dir_2/<topic>.just` first if needed (per `feedback_just_not_curl.md`).
3. Pick a single transcript path: `/tmp/just-test-PR<n>-$(date +%Y%m%d-%H%M%S).log`.

### Step 3: Run the trace

For each step in order:

1. Echo `━━━ Step N: <recipe-name> (<short purpose>) ━━━` to the transcript.
2. Run `just --justfile justfile.v2 <recipe> <args>` and capture stdout+stderr.
3. If the step has a verification (e.g. `curl GET ...categories | jq 'length'`), run it as a separate sub-step.
4. After each step, decide ✅ / ❌ based on HTTP code, JSON success flag, or expected count.
5. Stop on first ❌ (unless user explicitly asked `keep_going`).

The recipes you call already log their own curl + payload + response — capture that verbatim. Don't re-render output.

### Step 4: Build the PR comment

Use this exact structure (match the user's preferred format):

```markdown
### End-to-end smoke trace (commands + outputs)

Re-ran <short flow description> locally. Lambdas: Notify on `:8004`, Admin on `:8000`.

This run's identifiers:

- `notifyOrgId = <value>`
- `orgId = <value>`
- (any other ids the trace produced)

#### Step 1 — `<recipe-name>` (<purpose>)

```
$ just --justfile justfile.v2 <recipe> <args>
<output, jq-formatted, ANSI stripped>
```

✅ <one-line takeaway: what this proves>

#### Step 2 — `<recipe-name>` (<purpose>)

```
$ just --justfile justfile.v2 <recipe> <args>
<output>
```

**Verify** (<short label>):

```
$ curl GET <url> | jq '<filter>'
<output>
```

✅ <takeaway>

<…repeat for all steps…>

### Summary

| # | Step | Result |
|---|---|---|
| 1 | `<recipe>` | ✅ <one-line> |
| 1a | <verify label> | ✅ <one-line> |
| 2 | `<recipe>` | ✅ <one-line> |
| … |  |  |

<closing narrative — 1–3 sentences explaining what the run proves about the PR>
```

Rules for the comment body:

- **English only** — translate any Ukrainian step descriptions/labels you used internally.
- **Strip ANSI color codes** from all captured output (`perl -pe 's/\e\[[0-9;]*m//g'` or equivalent).
- **Redact secrets** — replace `NOTIFY_API_KEY` value with `<NOTIFY_API_KEY>`, any Bearer tokens with `<TOKEN>`, etc. Default redaction list: API keys, bearer tokens, Cognito tokens, AWS credentials, SNAPSHOT_AUTH.
- **Trim huge JSON arrays** — if a response has >20 items, show the first 10 with `…` and total count.
- **Highlight HTTP code** explicitly (`HTTP 200`, `HTTP 404`) when relevant.
- **Show the recipe invocation literally** (`$ just --justfile justfile.v2 …`) so the reader can copy-paste.
- **Don't echo the curl twice** — the recipe shows its own curl; reuse that, don't add another.
- **Long bodies** — if the full trace exceeds ~50KB, wrap the per-step blocks in `<details>` collapsibles, but keep the identifiers + summary + final takeaway always visible.

### Step 5: Post to PR

1. Write the markdown body to a tmp file (e.g. `/tmp/just-test-PR<n>-comment.md`).
2. Show the body in chat for confirmation BEFORE posting (per `feedback_review_pr_draft_first.md`).
3. On user "go" / "post" / "пости":
   - `gh pr comment <PR> --body-file <tmp>` — main trace comment.
   - NO "review" trigger comment — that workflow was dropped (bugbot auto-runs
     on every push; see `feedback_commit_push_pr_comment.md`).
4. Print the comment URL back to the user.
5. Stamp the pipeline state so the statusline badges (`/pr-state`) stay live:
   - `~/.claude/pipeline-stamp.sh stamp just-test pr-comment <PR>`
   (Only after a successful post — never stamp a step you didn't actually run.)

### Step 6: Save artifacts

Tell the user where the artifacts live:

- Raw transcript: `/tmp/just-test-PR<n>-<timestamp>.log`
- Redacted body posted to PR: `/tmp/just-test-PR<n>-comment.md`
- Per-step JSON response files (if recipes saved them): `/var/folders/.../T/notify-*.json`

## Important rules

- **NEVER raw-curl** when a recipe exists. If a verification needs a `curl GET …`, that's fine — but the action steps must go through `just`. (per `feedback_just_not_curl.md`)
- **Test plan first, run after.** Don't blindly execute. Confirm with the user.
- **Stop on first failure** unless `keep_going` was requested. Show the failure context and the saved response file path.
- **Don't push code, don't merge, don't approve PRs.** This skill posts a comment only. If the trace exposes a bug, surface it and let the user decide.
- **Match the example format exactly** — the user's reference trace is the canonical layout (identifiers section → numbered steps → verify subsections → summary table → closing narrative). Don't invent a new shape.
- **Idempotency** — if the test mutates state (categories, emergencies), seed a fresh org via `notify-create` + `notify-activate` rather than reuse a shared one, unless the user explicitly says otherwise.
- **Redact aggressively.** If unsure whether a value is sensitive, redact it.

## Common flows

### `notify-fallback-smoke` matrix (PUN-1279)

19-scenario fallback smoke (DECLARE / CATEGORIZED / PUT) — covers all sentinel modes + bogus + valid. Use when the PR touches `_get_category_info`, `_is_empty_category_id`, or any endpoint in `notify_routes.py` that resolves a category.

```
just --justfile justfile.v2 notify-fallback-smoke <notify_org_id> <valid_category_id> <valid_category_name>
```

### Uncategorized lifecycle (PUN-1279, PR #1260 + #1266)

1. `notify-create` → pending request
2. `notify-activate` → org + categories (verify Uncategorized present, `isRescue=true`)
3. `notify-replace-many-categories mode=replace` → verify Uncategorized survives
4. `notify-emergency-uncategorized` → DECLARE with `categoryId="0"` → verify HTTP 200 + `name=Uncategorized Emergency`

### Generic categorize/resolve flow

1. `notify-create` + `notify-activate`
2. `notify-emergency` (declare with valid category)
3. `notify-update-category-in-emergency` or `notify-v2-categorize-emergency` (re-categorize)
4. `notify-resolve-emergency`

Verify alert state via Admin API GET endpoints between steps.
