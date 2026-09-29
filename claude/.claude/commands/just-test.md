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
3. **Name the L2 orchestrator recipe now, and make sure it EXISTS** — `<topic>-smoke`.
   The Reproduce block at the end must be one command, so the orchestrator is not an
   optional nicety you bolt on afterwards; it is the deliverable. If it does not exist
   yet, WRITE IT BEFORE RUNNING THE TRACE. It must seed its own fixtures through the real
   endpoints, carry every generated id between steps in shell variables, assert each
   status code and row count, and delete only what it created.
   *Never document a recipe you have not implemented* — a `<topic>-help` that advertises a
   missing recipe is worse than no help at all.
4. **State which build is under test and how you will prove it.** Local lambdas (`lsof`
   the port) or a deployed environment (name the GH Actions run id that deployed the
   branch). Either way, plan a Step 0 that would FAIL on the old build — e.g. for a new
   route, an unrouted path returns `{"detail":"Not Found"}` while the handler returns its
   own message, so the body tells them apart where the status code cannot.
5. Pick a single transcript path: `/tmp/just-test-PR<n>-$(date +%Y%m%d-%H%M%S).log`.

### Step 3: Run the trace

For each step in order:

1. Echo `━━━ Step N: <recipe-name> (<short purpose>) ━━━` to the transcript.
2. Run `just --justfile justfile.v2 <recipe> <args>` and capture stdout+stderr.
3. If the step has a verification (e.g. `curl GET ...categories | jq 'length'`), run it as a separate sub-step.
4. After each step, decide ✅ / ❌ based on HTTP code, JSON success flag, or expected count.
5. Stop on first ❌ (unless user explicitly asked `keep_going`).

The recipes you call already log their own curl + payload + response — capture that verbatim. Don't re-render output.

### Step 4: Build the PR comment

Use this exact structure (match the user's preferred format).

**Canonical reference:** PR #1992 `issuecomment-5435172030` (PUN-1678 Notify
disable/enable). When in doubt about depth or shape, mirror that comment.

**HTTP client: `xh`, never `curl`.** House rule (CLAUDE.md `# HTTP`). If a recipe
you are about to call still shells out to `curl`, migrate that recipe to `xh`
FIRST, then run the trace — a trace that documents `curl` commands entrenches the
thing we are migrating off. `xh` also earns its place here: it prints the real
HTTP/2 status line, the response headers and the API Gateway request ids
(`x-amzn-requestid`, `x-amz-apigw-id`), all of which belong in the trace.

Useful flags: `-b` body only (scripts/pipes) · `-p hb` headers + body (what a
trace step wants) · `--check-status` to make 4xx/5xx a non-zero exit, since `xh`
exits 0 on them by default · `--ignore-stdin` inside recipes. Body syntax:
`field=value`, `nested:='{"json":true}'`, headers `"Name:Value"`.

**Verbosity rules (non-negotiable — the user asked for these explicitly):**

- **DB records in FULL.** When a step touches DynamoDB, paste the *whole* item,
  not a hand-picked subset. Unwrap the AttributeValue envelope
  (`jq '.Item | with_entries(.value = (.value.S // .value.N // .value.BOOL // .value))'`)
  so it reads as plain JSON. The point of the full record is that a reader can
  diff before/after themselves and see which attributes are **physically absent**
  vs holding `null` — that distinction is usually the whole claim.
- **Requests in FULL.** Show method, path, headers (token redacted) and body. If
  a request has no body, say so and explain what determines the action instead.
- **Response in FULL** — headers block (status, content-length, content-type)
  plus the complete untrimmed body. Do not cherry-pick fields.
- **Server logs as corroboration.** Paste the matching lines from the app log for
  each step (`tmux capture-pane -p -J` to un-wrap, then ANSI-strip). They prove
  the server actually did the work, and carry the real `status=` / `duration=`.
- **Syntax-highlight every block** with the right language tag: ` ```json `,
  ` ```console `, ` ```http `, ` ```log `, ` ```bash `. Never a bare ``` fence.
- **Full justfile invocations** — always `$ just --justfile <file> <recipe> <args>`
  in full, never an abbreviated `just <recipe>`. The reader must be able to
  copy-paste it verbatim.
- **Collapse the scaffolding, not the evidence.** Wrap environment setup, fixture
  seeding, and the reproduce block in `<details><summary>`. Identifiers, the
  numbered steps, and the summary table always stay visible.
- **One ASCII diagram, up front.** After the "what this feature does" paragraph,
  draw the state change the trace is about — the before/after shape of the record
  and the transitions between them. It is what lets a reader who never saw the PR
  follow the numbered steps. ASCII inside a fenced block; never Mermaid (it does
  not render consistently and the terminal rule forbids it anyway).
- **ONE self-contained orchestrator, and the Reproduce block is that one command.**
  This is the rule Mike has corrected most often (PUN-1707 twice, PUN-1638 once). A
  Reproduce block that says "copy the id from step 1 into step 2" HAS FAILED IT — the
  whole point is that another dev pastes one line and gets the same run. Build
  `<topic>-smoke`, RUN IT, and paste its real output. Listing the individual L1 recipes
  afterwards is fine as a "step through by hand" extra, never as the primary path.
- **Every step is a recipe.** No raw `xh`/`curl` in the numbered steps — if a step
  needs an HTTP call or a DB read that no recipe covers, ADD the recipe
  (`.just_dir_2/<topic>.just`) and call that. The Reproduce block then lists the
  full invocations, so any step can be re-run standalone. Raw DB reads get recipes
  too (e.g. `<topic>-db <id>`, `<topic>-gsi2 <key>`) — that is what makes the
  storage-level assertions reproducible rather than one-off shell archaeology.

```markdown
### End-to-end smoke trace (commands + outputs)

<one-paragraph framing: what flow ran, against what code, and what class of
assertion this adds that the existing tests do not cover>

**This run's identifiers**

| Field | Value |
|---|---|
| `orgId` | `<value>` |
| `<other id>` | `<value>` |

<details>
<summary><b>Environment — how this was run</b></summary>

<how the server under test was started; any proof it is the branch build and not
the shared stack — e.g. the 404 from the main checkout before the swap; the
startup log lines showing config/table/port>

</details>

<details>
<summary><b>Fixture — how the test data was seeded</b></summary>

<the recipes that created the fixture + their full output. Prefer seeding through
the real production path so the fixture carries everything a real record has>

</details>

---

#### Step 0 — <precondition proving the right build is running>

```console
$ <command>
<output>
```

✅ <what this rules out>

---

#### Step N — `<recipe-name>` (<purpose>)

```console
$ just --justfile <file> <recipe> <args>
<recipe's own ━━━ xh ━━━ banner + timing + HTTP code, ANSI-stripped>
```

**Request**

```http
POST /<path> HTTP/1.1
Host: <host>
Authorization: Bearer <TOKEN>
Content-Type: application/json
```

**Response headers**

```http
HTTP/1.1 200 OK
content-length: <n>
content-type: application/json
```

**Response body — full, untrimmed**

```json
<the entire body>
```

**Server log**

```log
<matching app-log lines with status= and duration=>
```

✅ <takeaway>

---

#### Step N+1 — the full DynamoDB record after <action>

```console
$ aws dynamodb get-item --table-name <table> --region <region> \
    --key '<key json>' \
    --output json | jq '.Item | with_entries(.value = (.value.S // .value.N // .value.BOOL // .value))'
```

```json
<the entire item>
```

✅ <the claim>. Diffed against the baseline record:

| Attribute | Before | After |
|---|---|---|
| `<attr>` | `<value>` | **absent** |
| `<attr>` | `<value>` | `<new value>` |

<prose naming what the diff proves, and what the failure mode would have looked
like instead>

**Verify — <the index/query assertion>**

```console
$ aws dynamodb query --index-name <gsi> ...
```

```json
{ "Count": <n>, ... }
```

✅ <takeaway>

<…repeat for all steps…>

### Summary

| # | Step | Expected | Result |
|---|---|---|---|
| 0 | <precondition> | <expected> | ✅ <one-line> |
| 1 | <step> | <expected> | ✅ <one-line> |
| 1a | <verify> | <expected> | ✅ <one-line> |

**<n>/<n> assertions passed.**

<closing narrative — what properties are now demonstrated end-to-end rather than
inferred, in the reviewer's terms>

<details>
<summary><b>Reproduce</b></summary>

```console
$ just --justfile <file> <recipe> <args>
```

<any notes on why these recipes exist / how they differ from the shared ones>

</details>
```

Rules for the comment body:

- **English only** — translate any Ukrainian step descriptions/labels you used internally.
- **Strip ANSI color codes** from all captured output (`perl -pe 's/\e\[[0-9;]*m//g'` or equivalent).
- **Redact secrets** — replace `NOTIFY_API_KEY` value with `<NOTIFY_API_KEY>`, any Bearer tokens with `<TOKEN>`, etc. Default redaction list: API keys, bearer tokens, Cognito tokens, AWS credentials, SNAPSHOT_AUTH.
- **Trim huge JSON arrays** — if a response has >20 items, show the first 10 with `…` and total count.
- **Highlight HTTP code** explicitly (`HTTP 200`, `HTTP 404`) when relevant.
- **Show the recipe invocation literally** (`$ just --justfile justfile.v2 …`) so the reader can copy-paste.
- **The resolved command MUST appear in the comment — it is the only portable thing there.**
  `.just_dir_2/` recipes are LOCAL and never committed, so `just <recipe>` does not exist in
  the reviewer's checkout. Paste the recipe's own `━━━ xh ━━━` / `━━━ aws ━━━` banner (the
  fully resolved `xh` / `aws dynamodb` / `aws logs` line it echoes before executing) under
  every step's `just` invocation. "Don't echo it twice" means do not hand-write a SECOND
  copy next to the recipe's own banner — it never meant omit it. Dropping the banners
  produced a PUN-1638 comment with 26 `just` lines and zero runnable commands.
- **CloudWatch and DynamoDB reads are steps too** — they get recipes (`<topic>-logs`,
  `<topic>-partition`) and their resolved `aws` command shown, exactly like HTTP steps. A
  log excerpt with no command behind it is an unverifiable claim.
- **Say what is redacted, once.** State up front that `$TOKEN` is a dev JWT and that it is
  the only redacted value; then nothing else in the comment may be abbreviated.
- **Long bodies** — if the full trace exceeds ~50KB, wrap the per-step blocks in `<details>` collapsibles, but keep the identifiers + summary + final takeaway always visible.

### Step 4.5: Verify the comment BEFORE showing it (mechanical, not by eye)

Reading your own draft does not catch these — run the checks. Any non-zero count is a
blocker; fix it and re-check.

```bash
BODY=/tmp/just-test-PR<n>-comment.md

# HARD blockers — every one of these must print 0 (or >=1 for the orchestrator)
grep -cE '^\$ .*(<[a-zA-Z_]+>|…)' "$BODY"     # placeholder/ellipsis in a COMMAND -> 0
grep -c 'copy the\|copying the' "$BODY"       # admits a manual step             -> 0
grep -c '<topic>-smoke' "$BODY"               # orchestrator is present          -> >=1
grep -cE '(^  |━━━ xh ━━━  )xh ' "$BODY"   # resolved xh commands shown       -> >=1 per HTTP step
grep -c 'aws logs\|aws dynamodb' "$BODY"      # resolved aws commands shown      -> >=1 if logs/DDB cited

# ADVISORY — angle-bracket tokens inside fenced blocks, HTML excluded by construction
awk '/^[`]{3}/{f=!f; next} f' "$BODY" | grep -oE '<[a-zA-Z_][a-zA-Z_0-9 x-]*>' | sort -u
```

Scope the placeholder check to **command lines** (`^$ `), not the whole body: the format
mandates `<details>` / `<summary>` / `<b>`, so a naive `grep -cE '<[a-zA-Z_]+>'` fires on
every correct comment — a gate that is always red is a gate nobody reads. (Verified: it
reported 6 "placeholders" on a clean PUN-1638 comment, all of them required HTML.)
A deliberately labelled data trim inside a fence — `"z": "<7 rows x 24 columns, full body
in the transcript>"` — is allowed and is what the advisory line is for: eyeball it, don't
auto-block it.

And prove the tooling's own docs are honest — the failure mode on PUN-1638 was a header
and a `-help` advertising an orchestrator that was never implemented:

```bash
grep -E '^#   <topic>' .just_dir_2/<topic>.just | awk '{print $2}' | sort -u > /tmp/hdr.txt
just --justfile justfile.v2 --list | grep -oE '<topic>[a-z-]*' | sort -u > /tmp/real.txt
diff /tmp/hdr.txt /tmp/real.txt   # must be empty
```

Finally: the orchestrator must have been **actually executed** in this session, and the
output pasted must be that run's. Never paste output you assembled by hand from the
individual steps.

### Step 5: Post to PR

1. Write the markdown body to a tmp file (e.g. `/tmp/just-test-PR<n>-comment.md`).
2. Show the body in chat for confirmation BEFORE posting (per `feedback_review_pr_draft_first.md`).
3. On user "go" / "post" / "пости":
   - `gh pr comment <PR> --body-file <tmp>` — main trace comment.
   - NO "review" trigger comment — that workflow was dropped (bugbot auto-runs
     on every push; see `feedback_commit_push_pr_comment.md`).
4. Print the comment URL back to the user.
   - To EDIT an already-posted comment, never `gh api -f body=@file` — `-f` does not read
     the file, it posts the literal `@/path` string and silently destroys the comment
     (hit on PUN-1638; a 16KB trace became 60 bytes). Use:
     `jq -Rs '{body: .}' "$BODY" | gh api -X PATCH repos/<owner>/<repo>/issues/comments/<id> --input -`
     then re-read the comment and check its byte size before claiming it is fixed.
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
