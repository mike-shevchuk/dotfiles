---
description: "Build Mike's own verification checklist for a PR — the exact commands and UI click-paths HE runs to convince himself the change works, with expected results and what a failure would mean"
argument-hint: "[PR number | branch]  (no args = the current branch's PR)"
---

# PR-Tests: what Mike should do to verify this PR himself

`/just-test` proves the change works by running it. **This command is the opposite**: it hands Mike
a checklist HE executes. Nothing here is run for him — the deliverable is the list.

Two different readers must both be served:
- **Mike at a terminal** — copy-paste commands, real values, no thinking required.
- **Mike in a browser** — a click-path through the portal, because some claims only show up in the UI.

**Terminal language:** match Mike (Ukrainian or English). **No Mermaid** — ASCII only.

`$ARGUMENTS`

## Step 1 — establish what actually changed

Never write a checklist from the PR description; descriptions drift from code. Derive it:

```bash
gh pr view <PR> --json number,title,headRefName,body,state,isDraft
gh pr diff <PR> --name-only
git --no-optional-locks log --oneline origin/main..<branch>
```

Then classify every changed area into a **claim** — one sentence a reader could disagree with:

| Change shape | The claim to test |
|---|---|
| new/changed route | this endpoint answers, with this status and this body shape |
| auth or scope guard | the wrong caller is refused, and refused the right way |
| DB model / key change | the stored row really looks like that |
| async worker path | the job completes, not just enqueues |
| agent / LLM tool | the assistant can now answer a question it previously could not |
| frontend surface | the thing is visible and does something when clicked |
| removal / deprecation | the old path is gone AND nothing else broke |

A PR with no testable claim is a PR with no user-visible effect — say so plainly instead of inventing
steps.

## Step 2 — the precondition (always first, never skip)

Every checklist opens with **"am I even testing the right build?"** A whole session of "it doesn't
work" usually ends here.

- Which environment carries the change, and how Mike confirms the branch is the one deployed —
  a route that does not exist on `main`, a field only this branch returns, a log line.
- **Shared-dev warning where it applies**: dev is one environment and a `main` auto-deploy overwrites a
  feature-branch deploy. Say what the symptom of being clobbered looks like (a 404 on a new route, a
  field coming back null) so Mike does not chase it as a bug.
- The redeploy command, so recovery is one line.

## Step 3 — write the checklist

One block per claim, numbered, ordered so each step's output feeds the next. For each:

```
### N. <the claim in plain words>

<one line: why this matters — what breaks for a user if it is false>

$ <the exact command, copy-paste ready>

Очікувано: <the specific observable result — a status code, a field, a count, a phrase>
Якщо не так: <what that failure would mean, and the single most likely cause>
```

Hard rules for the commands:

- **`xh`, never `curl`** (house rule). Show status and headers where they carry the proof (`xh -p hb`).
- **A `just` recipe beats a raw HTTP call** whenever one exists — check `just --justfile <path> --list`
  first. If a recipe is missing for something worth testing repeatedly, say which recipe should exist
  rather than falling back to raw calls silently.
- **No placeholders. No ellipsis.** Real ids, real URLs, real tokens-by-reference. If a value comes from
  a previous step, show the step that produces it and how to capture it — never `<chat_id>` with no
  instruction on where it comes from. This is the rule Mike has flagged twice; a checklist he has to
  fill in himself is a checklist he will not run.
- Token handling by reference (`just auth-token dev`, or the env file it writes) — never a pasted JWT.

## Step 4 — the UI path, when the PR touches something visible

Backend-only PRs skip this. Otherwise give the click-path as steps a person follows:

```
### N. <what should be visible>

1. Відкрий <url>
2. <click / select / type>
3. <what to look at>

Очікувано: <what appears>
Якщо не так: <most likely cause — wrong portal, wrong role, stale build, feature gated off>
```

Name the **role** required (org admin, enterprise admin, super admin) and the portal, because the same
page behaves differently per role and that is a common false alarm.

## Step 5 — negatives and edges (this is where the value is)

A checklist of happy paths proves almost nothing. Always include, where they apply:

- **The refusal cases.** A caller from another tenant, a missing required header, an id that does not
  exist. State the expected status AND that the message must not distinguish "exists but not yours"
  from "does not exist" when that matters.
- **The honest-failure cases.** What the feature says when a dependency is down or empty. A wrong-but-
  confident answer is worse than an error, so if the PR added a disclosure or a caveat, test that it
  appears.
- **The unchanged path.** Whatever the PR did NOT mean to touch but sits next to it — the org flow beside
  a new enterprise flow, the existing page beside a new one. Regressions land here far more often than
  in the new code.

## Step 6 — close with a compact table and the cleanup

```
| # | Що перевіряємо | Очікувано | ✓ |
|---|---|---|---|
| 0 | правильний білд        | <precondition>         |   |
| 1 | <claim>                | <expected>             |   |
```

Then:
- **Cleanup** — anything the checklist creates (test chats, orgs, devices) and how to remove it. Mike's
  standing rule: never delete existing data, only what this run created.
- **How long it takes**, honestly. A ten-minute checklist gets run; an hour-long one does not.
- If any claim **cannot** be checked by hand (a race, a TTL expiry weeks out, a rare retry path), say so
  and name what covers it instead. Do not pad the list with steps that cannot really be performed.

## Do not

- Do not run the checklist yourself — that is `/just-test`. This command produces the list.
- Do not test what the PR did not change; scope the list to the diff.
- Do not write a step whose expected result you have not derived from the code.
- Do not claim something is verified because a unit test covers it — this list is for behaviour the
  tests cannot show.
