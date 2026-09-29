---
description: "LITE smoke trace for a PR: one orchestrator recipe, a short evidence comment, the minimum gates. Use for small or low-risk PRs and re-runs after a small fix."
argument-hint: "<PR number> [optional plan description]"
---

# Just-Test LITE: short smoke trace → PR comment

Run ONE orchestrator recipe as an end-to-end smoke trace for PR #$ARGUMENTS, then draft a SHORT comment.
- Chat language: match Mike (UA/EN). The PR comment is ALWAYS English.

## Lite or full?

| Use **lite** (`/just-test-lite`) | Use **full** (`/just-test`) |
|---|---|
| small / low-risk PR | new endpoint or changed API contract |
| re-run after a small fix | data migration / backfill |
| behaviour already traced once in full | security, auth, tenancy, money |
| | anything a reviewer must reproduce from the evidence alone |

If unsure, use full.

## How to run it

Each rule says what to do, then why, then shows one example.

1. **Show the plan and wait for Mike's "go".** List the steps, what each step checks, and what test data it creates and deletes. That way Mike can stop a bad idea before it touches dev.
   Example: `1) create a test org · 2) create a webhook → expect 201 · … · 6) delete everything it created`
2. **Put all steps into one command, and make every step its own command too.** The one command is a just recipe named `<topic>-smoke`, kept in `.just_dir_2/<topic>.just` and never committed. It creates its own test data, checks every response code, and deletes what it created even if a step fails. Every step inside it is also a recipe you can run alone. That way anyone can repeat the whole test, or just one step, and dev stays clean.
   - **Everything is visible.** Before it runs, each step prints a framed header, then the full `xh`/`aws` command, then a coloured ✅/❌ result. That way a reader always knows where they are and why the step exists.
     - **Sections and steps.** Group the steps into named sections (e.g. build check · seed · the claim · proof in storage/logs · follow-up checks). The header's first line is `Section S/T (name) · Step N/M` plus a small progress bar `▓▓▓▓░░░░ 33%`.
     - **Say what and why.** Under the title go 1–2 plain-language lines: what this step does, and why it matters.
     - **Frame it** with `gum style --border rounded --padding "0 1"`. Colour only when a person watches (`[ -t 1 ]`), so the transcript stays plain.
     - **End with a result box** (`gum style --border double`): `N/M passed`, or the section and step that failed and why; what the run created; whether cleanup deleted it or kept it; the transcript path.
   - **You can approve everything at once.** Every step that writes to dev asks `gum choose` "No" / "Yes" / "Yes to all". "No" comes first, so a blind Enter changes nothing. "Yes to all" is remembered for the rest of the run, and `yes=1` approves everything up front. With no terminal to ask on and no `yes=1`, stop with a clear message instead of hanging.
   - **Detail is adjustable** with `verbose=1..4`:
     - `1` = one ✅/❌ line per step;
     - `2` = + status and key fields (default);
     - `3` = + the full response body, pretty-printed with `jq`/`yq` (long ones in `bat`/`jless`);
     - `4` = + headers and raw output.
     Every step recipe takes `verbose` as its **last** argument, after any optional ones. An env var (`P24_VERBOSE=N` in the reference) sets it for all of them at once.
   - **Missing arguments are picked, not typed.** A `<topic>-step` picker lists the steps in `fzf`. It then asks for each argument: ids come from an `fzf` list of real rows, fixed choices from `gum choose`. Anything that writes asks No / Yes / Yes to all first.
   Examples (the reference implementation is `.just_dir_2/pun1824.just`): whole test `jb2b pun1824-smoke` · no prompts `jb2b pun1824-smoke yes=1` · more detail `jb2b pun1824-smoke verbose=3` · one step `jb2b p24-webhooks <org> true 3` · pick a step `jb2b p24-step` → `fzf` step → `fzf` org/row → No / Yes / Yes to all before anything that writes.
3. **First check that dev really runs this PR's code.** Look for something that exists only in the new code. Otherwise you may be testing an old deploy, and the result means nothing.
   Example: `GET /openapi.json` lists the new parameter `includeAutoProvisioned` → ✅. On the old build it is missing → ❌, stop.
4. **Send requests with `xh`, not `curl`, and print each full command before running it.** Our recipes are not in the repo, so the printed line is the only thing a reviewer can copy and run.
   Example: `━━━ xh ━━━  xh POST https://api…/api/v1/webhooks 'Authorization:Bearer <TOKEN>' …`
5. **You may run steps that change dev data yourself.** Only if Claude's auto-mode blocks a command, hand Mike exactly one line for his console window ⌨️mike (tmux `b2b:2`), then read the result back from that window. That way the test still runs even when the safety check stops you, and Mike sees exactly what ran.
   Example: blocked → tell Mike `jb2b pun1824-smoke`, then read the result with `tmux capture-pane -p -J -S -300 -t b2b:2`.
6. **Don't touch the `deploy` label.** Only the lead adds or removes it, because adding it starts a deploy on the shared dev.

## Comment shape (short)

~~~markdown
### Smoke trace (lite) — <one line: what was proven>

<1 paragraph: what flow ran, against which build (deploy run id), what it proves>

| Field | Value |
|---|---|
| orgId / other ids | `…` |

| # | Step | Command | Result |
|---|---|---|---|
| 0 | build proof | `$ just --justfile <abs> <recipe>` | ✅ <one key assertion> |
| 1 | … | … | ✅ HTTP 201, `field=value` |

**Resolved commands** (the portable part — `.just_dir_2` is local):
```console
  xh … (one line per step, token as <TOKEN>)
```

<details><summary>Key evidence — <the record/response that proves the claim></summary>

```json
<ONLY the 1–2 bodies that carry the claim, full and untrimmed (e.g. the DB item)>
```
</details>

**N/N passed.** **Not covered:** <what this trace does not prove, and why>.

<details><summary>Reproduce</summary>

```console
$ just --justfile <abs path>/justfile.v2 <topic>-smoke
```
</details>
~~~

- Only `$TOKEN` (and any one-time plaintext secret) is redacted. Say so once.
- If a first run failed on a harness bug, add one honest line about it.

## Before you show the draft — checklist

Save the draft as `/tmp/just-test-PR<n>-comment.md`. Replace `<n>` and `<topic>` below, then paste the block:

```bash
B=/tmp/just-test-PR<n>-comment.md
grep -cE '^\$ .*(<[a-zA-Z_]+>|…)' "$B"                        # expect 0
grep -cE 'eyJ[A-Za-z0-9_-]{10,}|rk_live_[0-9a-f]{72}' "$B"    # expect 0
grep -c '<topic>-smoke' "$B"                                  # expect 1 or more
```

- [ ] **Every command can be copied as it is.** No `<placeholder>` or `…` inside a `$ …` line. Check: line 1 prints `0`.
- [ ] **No secrets.**
  - No login token: tokens start with `eyJ` and must appear only as `<TOKEN>`.
  - No full API key: `rk_live_` followed by 72 hex characters.

  Check: line 2 prints `0`.
- [ ] **The one-line command that repeats the test is in the comment.** Check: line 3 prints `1` or more.
- [ ] **The output is real.** It was copied from the run you just did, never typed or stitched together by hand. Check: every id in the comment is in the run log; `grep -c <id> /tmp/just-test-PR<n>-*.log` prints `1` or more.

## Post

1. Show the draft to Mike. Post ONLY after his "go". If the lead coordinates, send the lead the path and let them post.
2. `gh pr comment <PR> --body-file "$B"`. To edit a comment: `jq -Rs '{body: .}' "$B" | gh api -X PATCH repos/<owner>/<repo>/issues/comments/<id> --input -`, then re-read it and compare sizes. Never use `gh api -f body=@file`.
3. `~/.claude/pipeline-stamp.sh stamp just-test pr-comment <PR>`
