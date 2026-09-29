---
description: "Frontend hand-off trace for a PR: every endpoint the FE needs, called for real on dev, with full request/response, field table, errors, TS types and the screen that uses it → one English PR comment. Mike sends the comment link to the FE dev."
argument-hint: "<PR number> [optional: which endpoints / screens]"
---

# Just-FE: API trace for the frontend → PR comment

Prove and document, for PR #$ARGUMENTS, **only what the frontend needs** — in enough detail that the FE dev can build the screens without asking the backend a single question.
- Chat language: match Mike (UA/EN). The PR comment is ALWAYS English.
- Skip backend-only evidence (DynamoDB rows, worker logs, SQS, alarms) — that is `/just-test`. Here the proof is the **HTTP contract as the browser sees it**.

## just-fe vs just-test

| `/just-fe` | `/just-test` |
|---|---|
| audience: FE dev (Danylo) + Mike | audience: reviewer |
| every endpoint the UI calls, one by one | the end-to-end flow + proof in storage/logs |
| full response bodies, field table, TS types, errors | ✅/❌ per step, key fields |
| "which screen uses it, what to render" | "is the backend correct" |

Run both on big API PRs: `/just-test` proves it works, `/just-fe` explains how to use it.

## How to run it

1. **Plan first, wait for Mike's "go".** List the endpoints you will cover (method + path), per portal/role (org admin · enterprise admin · partner · super admin), the test data you create and delete, and the dev build you will check. Mike trims or adds before anything touches dev.
2. **Check dev runs this PR's build.** Hit something that exists only in the new code (a new field/route). Wrong build → stop.
3. **One orchestrator recipe `<topic>-fe`** in `.just_dir_2/<topic>.just` (never committed), same UX rules as `/just-test`: framed steps, full `xh` command printed before each call (`━━━ xh ━━━`), `yes=1`, `verbose=1..4`, creates and deletes its own data, cleanup on failure. Tokens: `/tmp/audit-env.dev.sh` only.
4. **Per endpoint, capture all of this** (this is the whole point — be exhaustive):
   - **Method + path + who may call it** (role/portal, required headers: `X-Organization-Id`, `X-Enterprise-Id`, …).
   - **Request**: the exact JSON body (+ query params), with an example for every optional field that changes behaviour.
   - **Response**: the REAL body from dev, pretty-printed, not trimmed (long lists: first 2 items + count).
   - **Field table**: `field | type | nullable | meaning | UI hint` — every field the FE might read, incl. ones that are `null` in the example.
   - **Errors**: every status the UI must handle (400/403/404/409/422/5xx) — trigger each for real, show the exact body and say what the UI should do (toast text, disable button, redirect).
   - **TypeScript type** generated from the real response (`interface …`) + a request type.
   - **Where it shows**: the dev frontend route/screen that uses it (full URL on `https://rescue-serverless.dev.back2back.team/…`), and one line on what the screen should render.
   - **Changed vs main**: new / changed / removed fields; mark **BREAKING** anything that changes an existing shape or meaning (e.g. a field that used to be `null` and now isn't).
   - Async/polling: if the call returns 202, show the poll loop (which GET, which field flips, suggested interval/timeout).
5. **Real data only.** Every example body comes from an actual dev call in this run — never hand-written. IDs in the comment are real dev IDs so the FE dev can reuse them.
6. **Blocked by auto-mode?** Give Mike one line for ⌨️mike (tmux `b2b:2`) and read the result back. Don't touch the `deploy` label (lead only).
7. **Show Mike the draft** (terminal preview), post only after his "go", then give him the comment URL.

## Re-runs after new commits (Mike, 2026-09-29 — "швидше")

The comment is **edited in place** (same URL the FE dev already has), never re-posted. On every new push:
1. **Chain without stopping:** wait the deploy run → build-proof (hit something only the new commit has, e.g. a new field or a new 403) → `jb2b <topic>-fe` → the PR's headless demo (`~/.claude/demo-result.sh write …`) → `demo-result.sh check <pr>`.
2. **Pre-approved edit:** if the only differences are SHA, pass count, fresh IDs and rows/fields that the new commit adds, replace the comment yourself and print the URL. Anything else (changed action type, removed rows, changed status codes or shapes) → show the lead the draft first.
3. **Shared dev data:** dev is shared — other people's manual test data can hold the resource you need (e.g. an action type already mapped → your create gets a correct 409 and later steps cascade). Never touch their data: pick a free resource (another action type / name) in the recipe, clear the recipe's cached state, re-run.
4. **Every new guard gets a row:** a new 403/404/409 in the PR = a new asserted call in the recipe (the allowed caller gets 200, the others get the error) and a row in the Errors table.
5. **Badge + index stay truthful:** the shields.io badge shows `N/N` and the dev SHA of THIS run; the index table lists every endpoint, including the new ones.

## Presentation rules (Mike, 2026-09-29 — mandatory)

1. **Two response views per call:**
   - **Compact first** — only what this PR adds or changes (e.g. the 1–3 new/changed fields), extracted with a `jq` projection, shown with `// 🆕` / `// ✏️` markers.
   - **Full second, collapsed** — `<details><summary>Full response 200</summary>` with the whole body pretty-printed by `jq`.
2. **Syntax highlighting everywhere:** fenced blocks with a language (` ```bash `, ` ```json `, ` ```ts `). Never an unfenced body.
3. **Readable requests with global variables.** Put a **Setup** block once at the top that exports `API`, `TOKEN`, `ORG`, `ENT`, … (how to get the token: `jb2b auth-token dev` → `source /tmp/audit-env.dev.sh`). Every request is then a short, copy-paste `xh` block using `$API` / `"Authorization:Bearer $TOKEN"` / `$ORG`, one argument per line with `\` continuations. Never inline a real token or a 40-char id where a variable fits.
4. **Runnable by anyone:** each endpoint section ends with the `jb2b <topic>-fe-<step>` command that re-runs exactly that call, and the header shows `jb2b <topic>-fe` for the whole set.
5. **It is a test, not a doc:** every call asserts the status and the key fields (`✅ 200 · multiOrgAlerting=false`) and the run ends with `N/M passed`. A failing assertion blocks posting.
6. **Preview with glow before posting:** render the draft to a file and open it for Mike (`glow -p <file>` in its own tmux window) — he approves the look, then it is posted.

## Readability layout (Mike, 2026-09-29 — "зроби більш readable")
The comment must be scannable in 30 seconds:
1. **Top: endpoint index table** — `# | method | path | who | success | one line` — each row links to its section anchor. Right under it: **⚠️ BREAKING** block (only if any) and **Changes vs main** as 3 short bullets.
2. **Per endpoint, visible:** one line of purpose + screen URL, the `xh` request block, the **compact** response (🆕/✏️ only), the assertion line `✅ 201 · … · jb2b <topic>-fe-<step>`.
3. **Per endpoint, collapsed** (`<details>`): full response (jq), field table, errors for that endpoint.
4. **End:** ONE `ts` block with all request/response types; ONE consolidated **Errors** table (`status | when | UI should`); test-data/cleanup line.
5. Keep prose to one sentence per section. No repeated explanations.

## Styling for GitHub (Mike, 2026-09-29 — "більше стилю для легкості читання")
- **GitHub alerts** for signal: `> [!WARNING]` BREAKING · `> [!IMPORTANT]` what the FE must do · `> [!NOTE]` Setup · `> [!TIP]` how to re-run.
- **Mermaid**: one `sequenceDiagram` of the main flow (who calls what, what the user sees) + one `flowchart` for any branching behaviour (e.g. 409 → overwrite, resolve all vs subset). Keep each ≤ 15 lines.
- **Method badges** everywhere: 🟢 `GET` · 🟡 `POST` · 🔵 `PUT`/`PATCH` · 🔴 `DELETE`.
- **Tests badge** at the top: `![tests](https://img.shields.io/badge/tests-N%2FM-brightgreen)` (orange when a known bug is marked).
- **Two-level collapse**: each endpoint section is a `<details>` (the most important one `<details open>`); inside it the full response is a nested `<details>`.
- **Secondary text small**: `<sub>` for ids/notes, `<kbd>jb2b …</kbd>` for commands; `---` between sections.
- glow can't render alerts/Mermaid → preview by editing the GitHub comment in place (same URL) and let Mike look there.

## Comment shape

~~~markdown
### API for the frontend — <feature> · `<sha>` on dev

**Setup** (once):
```bash
jb2b auth-token dev && source /tmp/audit-env.dev.sh   # → $SNAPSHOT_AUTH
export API=https://api.rescue-serverless.dev.back2back.team/api/v1
export TOKEN=${SNAPSHOT_AUTH#Bearer }
export ORG=<real org id> ENT=<real enterprise id>
```
Run everything: `jb2b <topic>-fe` → **N/M passed**

<2–3 lines: what the FE can build now, which portals/roles, what is NOT ready yet>

**Changes vs main:** 🆕 new … · ✏️ changed … · ⚠️ BREAKING …

---

#### 1. `POST /api/v1/enterprise/categories` — enterprise admin
Headers: `X-Enterprise-Id` · Screen: `https://rescue-serverless.dev.back2back.team/enterprise/categories` (create dialog)

```bash
xh POST "$API/enterprise/categories" \
  "Authorization:Bearer $TOKEN" "X-Enterprise-Id:$ENT" \
  name='Fire' actionType=button_alert \
  multiOrgAlerting:=true notifyOrgIds:="[\"$ORG\"]"
```
**What's new in the response** (compact):
```json
{
  "multiOrgAlerting": true,        // 🆕
  "notifyOrgIds": ["3df469ef-…"]   // 🆕
}
```
<details><summary>Full response 201</summary>

```json
{ …real body, jq-formatted… }
```
</details>

✅ 201 · multiOrgAlerting=true · `jb2b <topic>-fe-create`

| field | type | nullable | meaning | UI hint |
|---|---|---|---|---|

**Errors**
| status | when | body | UI should |
|---|---|---|---|

```ts
export interface EnterpriseCategory { … }
```

---
#### 2. …

---
**Test data** created → deleted (cleanup ✅). **Re-run:** `jb2b <topic>-fe` (local recipe).
~~~

## Checklist before posting
- [ ] every endpoint in the plan has request, real response, field table, errors, TS type, screen
- [ ] every error the UI must handle was triggered for real
- [ ] BREAKING changes called out at the top
- [ ] no tokens/secrets in the comment (`<TOKEN>`), real dev IDs kept
- [ ] test data cleaned up (other people's dev data untouched)
- [ ] badge SHA = the build-proof SHA of this run; DEMO gate `demo-result.sh check <pr>` ✓ before saying "ready to merge"
