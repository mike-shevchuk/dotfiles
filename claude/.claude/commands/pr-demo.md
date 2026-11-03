---
description: "Build a hands-on, self-verifying demo for a PR — a narrated justfile walkthrough (or a browser click-through where the feature is UI-only) plus a shareable guide, so anyone can try what the PR ships and SEE the evidence"
argument-hint: "<PR number | branch> [feature notes]"
---

# PR-Demo: make a PR verifiable by hand

Turn PR **$ARGUMENTS** into something a person can *try* and *believe*: an interactive
`just` walkthrough that exercises each feature against dev with real narration and
visible evidence, a browser click-through for anything that's UI-only, and one
readable guide others can follow. The goal is not a test log — it's "run this, watch
it happen, understand why."

## Try rules are the single source (Mike 2026-10-14)
Every `jb2b <topic>-try` follows `~/.claude/fleet-board/missions/try-rules.md` (format v3, rules V1–V19; template `jb2b try-new`, lint `jb2b try-lint`). Read it before writing or changing a try. Since 2026-10-14 that includes:
- **V17** a short Ukrainian recap per PR for `jb2b sprint-try` (`w<N>/recaps/<PR>.md` from `_TEMPLATE.md`): Було · Стало · ASCII schema ≤ 56 chars, БУЛО above СТАЛО · Де побачити · Перевірити окремо (every `jb2b` command) · Не доведено · Після мерджу;
- **V18** say each thing once — recap = the PR, intro box = this run; no reprints, no empty sections;
- **V19** every step runnable alone: `jb2b <try> list`, `step=N`, `steps=A-B`, `▶ окремо` on each card; every action is an existing `jb2b` recipe.

**Conversation language:** match the user (Ukrainian or UA/EN mix is fine).
**Anything posted or shared (guide, PR comment):** English.

## What you produce

1. **A justfile demo set** in the MAIN console — an interactive `<topic>-try` menu that
   dispatches to `<topic>-demo` (a narrated, paced walkthrough) and, if useful,
   `<topic>-smoke` (the automated end-to-end from `/just-test`). Every feature that has
   an HTTP or CLI surface gets a hands-on path.
2. **A browser click-through** for any feature that only exists in the portal/UI —
   numbered steps + exactly what to look for, since you (Mike) don't implement FE.
3. **A shareable guide** — a published HTML artifact (dark, 🤖 favicon, EN/UA toggle,
   copy buttons, responsive) that explains what the PR does in plain words and gives
   1–3 ways to verify each feature (just · raw xh · browser). This is the thing others
   open to check the work themselves.

Draft-first for everything outward; never post to the PR or publish without an explicit go.

## Workflow

### 1 — Understand what the PR ships, and split it

Read the PR: `gh pr view <n> --json title,body,files` and the diff. Bucket every change:

- **HTTP-testable** (a route, an endpoint, a status flip you can GET) → a live demo step.
- **Browser-only** (a screen, a button, a chart) → a click-through, not a fake HTTP call.
- **Not directly testable** (an SQS worker, a CloudWatch alarm, a guard the dev token
  bypasses, a migration) → a short "how it's proven" note (unit tests, CDK, code), never
  a staged HTTP step pretending to exercise it.

Name the topic (`<topic>` = the PR's theme, e.g. `onboarding`). Confirm the build under
test: is the branch deployed to dev? If not, offer to trigger the deploy
(`gh workflow run <deploy-id> --ref <branch>`) and wait, or run against the local stack.
Plan a **Step 0 build-proof** that fails on the old build (a new route: an unrouted path
returns `{"detail":"Not Found"}` while the handler returns its own message).

### 2 — Present the plan, get a go

Show, in the terminal: the feature buckets, which get a just demo vs a browser
click-through vs a proof-note, the fixture strategy (seed-and-delete vs reuse), and any
real side effect (a real email, dev writes). Wait for "go" before building or running.

### 3 — Build the justfile demo (in the MAIN console — read the golden rules first)

Put recipes in `<topic>.just` and follow the **Golden rules** below to the letter — they
are the difference between "it works when Mike runs it" and "it prints nulls." Reuse the
**Recipe skeleton** so you don't re-derive the helpers.

The `<topic>-demo` walkthrough MUST:
- Open with **WHY this matters** (the goal, in the user's words) and a **numbered PLAN**
  of exactly what it will do, then a `gum confirm "Ready to start?"` gate — the reader
  understands the whole arc before anything runs.
- Narrate each step: *what* it's doing and *why*, in plain language.
- **Show evidence, not just narration.** After an action, display the real change:
  the progress counter before→after (`1/6 → 2/6 done`, the step `null → true`), the
  actual audit-log / DynamoDB row that caused it (pretty-printed), and a final trail of
  everything the demo produced. "✔ it worked" with nothing shown is a failure of this
  command.
- **Self-clean:** seed throwaway fixtures through the real endpoints, delete them on exit
  via a bash `trap`. Only reuse existing data for non-mutating reads.

### 4 — Build the browser click-through (for UI-only features)

For each browser-only feature, write numbered steps a non-author can follow: which portal,
which screen, what to click, and **what to look for** as the proof (a value changes, a
checklist ticks, a toast appears). If the backend endpoint exists but the FE button
doesn't yet, state the FE contract (method, path, body, response) as the hand-off.

### 5 — Publish the shareable guide

Load `artifact-design`, then build ONE HTML page (dark-first, theme-aware, 🤖 favicon,
EN/UA toggle, `<pre>` copy buttons, responsive at 400px). Structure: what the PR does
(plain words) → prerequisites (install recipes + mint token) → the one command
(`jb2b <topic>-try`) → per feature: ① via just, ② via raw xh (full literal commands,
only the token redacted), ③ via browser → the non-HTTP changes as a proof table.
Publish it; hand back the link. This is what "others can verify it too" means.

### 6 — Offer the PR comment (optional)

If the demo doubles as a smoke trace, offer to post it to the PR via `/just-test`
conventions (draft-first, English, one self-contained orchestrator). Never auto-post.

## Golden rules (hard-won — violate none)

- **Reuse the already-tested local recipes; do NOT reinvent them.** Before writing any
  picker, lister, or auth step, grep `.just_dir_2/` for one that exists: org picker =
  `_pick-org <env>` (returns `orgId`; handles the top-level array + preview), also
  `_pick-user`/`_pick-partner`/`_pick-enterprise`, token = `auth-token <env>`,
  env/base+auth = `_env-resolve <env>`. Call them via `just --justfile "{{justfile()}}" <recipe> …`.
  A hand-rolled `jq '(.organizations // …)'` on `/admin/organizations` errors — the API
  returns a **bare array**, and the tested `_pick-org` already gets this right. Writing
  your own is how demos break in front of the user.
- **TEST the recipe before handing it over.** Never present a recipe you have not run.
  For interactive (fzf/gum) recipes you can't drive headless, at least verify the
  non-interactive data path they consume (e.g. the org list is a non-empty array with
  `orgId`+`name`) so you KNOW the picker will populate. Silent breakage the user finds
  first is the failure this rule prevents.
- **Justfiles live in the MAIN checkout, NEVER the worktree.** Write the recipe body to a
  tmp file, then via Bash (`cp`/`printf >>` are not sandbox-blocked):
  `cp <tmp> /Users/mikeshevchuk/code/b2b/rescue-serverless/backend/src/lambdas/api/fast/.just_dir_2/<topic>.just`
  and `grep -q "<topic>.just" <main>/justfile.v2 || printf "\nimport '.just_dir_2/<topic>.just'\n" >> <main>/justfile.v2`,
  then verify `just --justfile <main>/justfile.v2 --list | grep <topic>`. THE TRAP: the
  Write/Edit tools refuse to write to the main checkout from a worktree session — do NOT
  take the bait and author into the worktree; `jb2b` reads the main console and won't see
  it. See [[feedback_justfiles_must_survive_worktree]].
- **xh: send JSON via field syntax + `--ignore-stdin`, never `--raw @-`.** Match the
  tested `onboarding-smoke` invocation exactly:
  `xh -b --check-status --ignore-stdin POST "$URL" "Authorization:$SNAPSHOT_AUTH" audience=test test_emails:='["…"]' day:=3`.
  `--raw @-` is httpie syntax, not xh, and errors ("body from stdin and --raw cannot be
  mixed"); and any xh call with `field=value` data run non-interactively also needs
  `--ignore-stdin` or it errors ("body from stdin and request data cannot be mixed").
- **gum draws its TUI on stderr.** NEVER `2>/dev/null` a `gum choose`/`gum confirm` — it
  makes the menu invisible and the recipe looks dead. Keep `</dev/tty` for input; guard
  gum's absence with `command -v gum` instead of suppressing stderr.
- **Auto-heal the token; never swallow errors.** Source `/tmp/audit-env.sh`; if
  `$SNAPSHOT_AUTH` is missing or a call returns 401, re-mint with
  `just --justfile "{{justfile()}}" auth-token dev` (non-interactive, ~10s, no MFA) and
  retry once. Every HTTP call captures the real status + body; on failure print
  "the server said: …" and stop. A silent `null` id (expired token swallowed by
  `2>/dev/null` + `jq -r`) is the #1 way these demos "don't work."
- **macOS bash 3.2:** no `set -u` (it errors on `"$@"`/`${*}` with zero args). Use
  `set -o pipefail`.
- **Pick the route that actually exercises the feature.** For audit→onboarding, the
  TENANT route (`/api/v1/users/{id}` + `X-Organization-Id`) emits an org-scoped event
  that auto-closes; the global `/admin/users` route emits an org-less event and does not.
  Grep the emit site for `org_id=` before choosing.
- **Style for reading:** gum `style` headers, colored ✔/✖, a single self-updating wait
  line (`printf "\r … %ss"`), not 24 spammed poll lines. Section rules between steps.
- **Never post/publish without an explicit go.** Draft-first. English for shared output.

## Recipe skeleton (reuse verbatim, adapt the steps)

```just
[group('<topic>')]
[doc('L2 · interactive: try PR #<n> by hand')]
<topic>-try:
    #!/usr/bin/env bash
    set -o pipefail
    G(){ command -v gum >/dev/null 2>&1; }
    title(){ G && gum style --border double --border-foreground 214 --foreground 214 --bold --padding "1 3" --margin "1 0" "$@" || { echo; echo "==== $* ===="; echo; }; }
    note(){  G && gum style --foreground 245 "$@" || echo "    $*"; }
    title "PR #<n> — try it by hand (dev)"
    note "<one line: what this PR does you can watch live>"
    CH=$(gum choose "1 · <feature A> (watch it)" "2 · <feature B>" "Quit" </dev/tty)   # NO 2>/dev/null
    JF="{{justfile()}}"
    case "$CH" in 1*) just --justfile "$JF" <topic>-demo ;; 2*) just --justfile "$JF" <topic>-other ;; *) note "Bye." ;; esac

[group('<topic>')]
[doc('L2 · guided, narrated demo of <feature A>')]
<topic>-demo:
    #!/usr/bin/env bash
    set -o pipefail
    BASE="https://api.rescue-serverless.dev.back2back.team"; EPOCH=$(date +%s)
    G(){ command -v gum >/dev/null 2>&1; }
    title(){ G && gum style --border double --border-foreground 214 --foreground 214 --bold --padding "1 3" --margin "1 0" "$@" || { echo; echo "== $* =="; }; }
    step(){ G && gum style --bold --foreground 39 "$@" || echo ">>> $*"; }
    note(){ G && gum style --foreground 245 "$@" || echo "    $*"; }
    good(){ G && gum style --foreground 42 --bold "$@" || echo "  OK $*"; }
    bad(){ G && gum style --foreground 196 --bold "$@" || echo "  ERR $*"; }
    rule(){ printf '    \033[38;5;240m%s\033[0m\n' "────────────────────────────────────────"; }
    RC=""; RB=""
    req(){ local m="$1" u="$2"; shift 2; local out; out=$(xh --ignore-stdin -p hb "$m" "$u" "Authorization:$AUTH" "$@" 2>&1)
        RC=$(printf '%s\n' "$out" | grep -m1 -oE 'HTTP/[0-9.]+ [0-9]{3}' | awk '{print $2}')
        RB=$(printf '%s\n' "$out" | awk 'b{print} /^\r?$/{b=1}'); }
    die(){ echo; bad "$1"; [[ -n "$RB" ]] && printf '%s\n' "$RB" | (jq . 2>/dev/null||cat) | sed 's/^/      /'; exit 1; }
    mint(){ note "Minting a fresh dev token…"; just --justfile "{{justfile()}}" auth-token dev >/dev/null 2>&1||true; { . /tmp/audit-env.sh; } 2>/dev/null||true; AUTH="${SNAPSHOT_AUTH:-}"; }
    title "<title>"; step "Why this matters"; note "<goal>"; step "The plan"; note "1. … 2. … 3. …"
    if G; then gum confirm "Ready to start?" </dev/tty || { note "Cancelled."; exit 0; }; fi
    { [[ -f /tmp/audit-env.sh ]] && . /tmp/audit-env.sh; } 2>/dev/null||true; AUTH="${SNAPSHOT_AUTH:-}"; [[ -z "$AUTH" ]] && mint
    req <seed…>; [[ "$RC" == "401" || -z "$RC" ]] && { mint; req <seed…>; }; [[ "$RC" == 2?? ]] || die "seed failed (HTTP ${RC})"
    trap 'req DELETE <user>; req DELETE <org>' EXIT   # self-clean
    # … show baseline evidence → do the action → watch → SHOW the audit row + progress before→after
```

Notes: `{{justfile()}}` resolves to the running console (main under `jb2b`), so cross-recipe
calls (`auth-token`, sibling demos) work. Show progress with
`jq '[.steps[]|select(.==true)]|length'` over `.steps|length`; show the row that caused it
with `GET /api/v1/audit-logs/org?category=<CAT>&event_type=<EVT>` (the `event_type` filter
needs `category`). Dev host, table `dev-rescue-serverless-data`, log groups
`/aws/lambda/dev-rescue-serverless-<fn>`.
