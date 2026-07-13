---
description: Render the current branch's changes (or a PR) as an interactive LGTM HTML review page — Codex reads the diff, writes verified findings (bugs, two-sources-of-truth, frontend impact), then the static lgtm.cli engine renders them pinned to the right hunks.
argument-hint: "[eng|ukr|both] [ <base> <head> | <PR#> ] [--help]"
---

# /review-html

Drive the LGTM static review engine (`lgtm.cli`, Milestone 1) end-to-end: collect the
diff, do a deep verified analysis of it, render an HTML page with your findings pinned
to the exact hunks, and open it.

`$ARGUMENTS` may contain: a language (`eng|ukr|both`, default `ukr`), either two git
refs `<base> <head>` or a single integer `<PR#>` (no refs = current branch vs its
merge-base, uncommitted included), and `--help`.

## Step 0 — `--reply` / `--help`
If `--reply` is present: tell the user this mode is retired — the live
comment→Codex loop now EXISTS as a server-backed feature: run
`jb2b review-serve` (SSE server) + `/lgtm-listen` (Codex watcher), then
comment right on the page. Then STOP.

If `--help` or the bare word `help` is present: try `jb2b review-help`. That shell
function currently fails in repos where `justfile.v2` isn't at the git root (rescue-serverless
keeps it at `backend/src/lambdas/api/fast/justfile.v2`) — on `no justfile.v2 at <root>`,
fall back to `just --justfile backend/src/lambdas/api/fast/justfile.v2 review-help`
(adjust the path for other repos). Print the recipe list it outputs and STOP.

## Step 1 — run the CLI once (collect the diff)
`REPO=$(git rev-parse --show-toplevel)`. From `~/dotfiles/codex/.codex/scripts`:

```bash
python3 -m lgtm.cli review --repo "$REPO" [--pr <N> | --refs <base> <head>] --lang <lang>
```

(Omit `--pr`/`--refs` for local mode.) Don't pass `--out` — the CLI derives it itself
(`$REPO/.lgtm/reviews/<ref>/`, e.g. `pr1651` or the branch name) and prints it as the
**last line of stdout**. Call that path `PAGE`; `OUT=$(dirname "$PAGE")`.

This first run has no `findings.json` yet, so it writes `$OUT/diff.txt` and renders a
findings-less page — expected, not an error.

## Step 2 — deep pass: read the diff, write findings.json
1. Read `$OUT/diff.txt` in full.
2. Analyze for real bugs, two-sources-of-truth (a new literal/set/if-chain duplicating
   an existing enum or helper), and frontend impact. **Verify every claim against the
   codebase** (grep/read the actual file(s) involved) before writing it down — no
   speculative findings.
3. For each finding, get its hunk id from `$OUT/hunks.json` (written by Step 1) —
   don't hand-count `@@ … @@` blocks in `diff.txt` yourself. It lists, per file in
   order, each hunk's `id` (`F#H#`), `header`, and `first_new_line`. Use the hunk
   that actually contains the flagged code — don't assume it's a file's first hunk.
   `line` = a real line number from that hunk (prefer an added line; `first_new_line`
   is a good default when the flagged code is the first changed line). The CLI
   validates every finding's `hunk` against this map on the next run and warns
   (`⚠ невідомий hunk`) if it doesn't match — keep `diff.txt` open for the actual
   before/after content.
4. Write `$OUT/findings.json` matching `lgtm.model.Finding` **exactly** — flat
   `severity_emoji` + `severity_score`, not nested:
   ```json
   {"meta": {"lang": "ukr|eng|both"},
    "findings": [
      {"id": "…", "layer": "claude", "source": "claude-deep",
       "file": "…", "line": N, "hunk": "F#H#",
       "severity_emoji": "🟢|🟡|🟠|🔴", "severity_score": 0,
       "problem": {"<lang>": "…"}, "harm": {"<lang>": "…"},
       "fix": {"<lang>": "…", "code": "…"},
       "agrees_with": [], "coach": null, "status": "open", "thread": []}
    ]}
   ```
   - Fill only the requested language key(s) in `problem`/`harm`/`fix`; for `both`,
     fill both `ukr` and `eng`.
   - `meta` identity fields (`ref`/`base`/`mode`/`repo`/`generated`) are recomputed
     fresh by the CLI on every run — only `lang` is read back from `findings.json`
     (unless `--lang` is passed, which always wins). Don't bother writing the other
     meta fields; the block above is the minimal shape that matters.
   - No verified findings? Write `"findings": []` — an empty array is a valid result,
     not a failure.
5. **Coach layer (design §4):** where a finding maps to a house-rule pattern, fill its
   `coach` field: `{"pattern": "<slug>", "ref": "<existing good example file:line>",
   "read": "<what to read>"}`. Standalone lessons (no bug, just a pattern worth
   knowing) go as separate findings with `"layer": "coach"`.

## Step 2.5 — append the coach stats line (progress between reviews)

Append ONE line to `$REPO/.lgtm/review-stats.jsonl` (create if missing) counting
house-rule patterns among THIS review's findings — **zeroes included**, they are the
win being tracked:

```bash
python3 - "$REPO/.lgtm/review-stats.jsonl" <<'PY'
import json, sys, time
line = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "ref": "<OUT basename, e.g. pr1700>",
        "patterns": {  # count per pattern in THIS review; keep keys stable:
            "two-sources-of-truth": 0, "inline-import": 0, "getattr-hasattr": 0,
            "dynamodb-scan": 0, "truthiness-vs-presence": 0, "missing-log-exception": 0,
            "string-literal-vs-enum": 0}}
open(sys.argv[1], "a", encoding="utf-8").write(json.dumps(line, ensure_ascii=False) + "\n")
PY
```

Add new pattern keys when a new house rule shows up; `lgtm stats` and the page's
🎓 panel aggregate them automatically (`python3 -m lgtm.cli stats --repo "$REPO"`).

## Step 3 — re-render and open
Re-run the **exact same command** from Step 1 (same `--repo`/`--pr`/`--refs`, same
`--lang` if you want to force it — the CLI logs when `--lang` overrides
`findings.json`'s stored language). It now finds `findings.json` and renders your
findings inline, pinned to their hunks. Open the printed page path (`open` on macOS,
`xdg-open` on Linux). Tell the user it's ready — comment/discuss happens by talking to
you directly in this session (no clipboard loop).

## Notes
- The live comment→Codex loop is a separate, real feature now:
  `jb2b review-serve` (LAN SSE server) + `/lgtm-listen` (watcher). This command
  only builds the page; suggest the pair when the user wants to discuss inline.
- Engine lives in `~/dotfiles/codex/.codex/scripts/lgtm/` (`cli.py`, `render.py`,
  `diffparse.py`, …). Full contract: `rescue-serverless/.lgtm/design.md`.
