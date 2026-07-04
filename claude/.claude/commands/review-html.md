---
description: Render the current branch's changes (or a PR) as an interactive LGTM HTML review page — Claude reads the diff, writes verified findings (bugs, two-sources-of-truth, frontend impact), then the static lgtm.cli engine renders them pinned to the right hunks.
argument-hint: "[eng|ukr|both] [ <base> <head> | <PR#> ] [--help]"
---

# /review-html

Drive the LGTM static review engine (`lgtm.cli`, Milestone 1) end-to-end: collect the
diff, do a deep verified analysis of it, render an HTML page with your findings pinned
to the exact hunks, and open it.

`$ARGUMENTS` may contain: a language (`eng|ukr|both`, default `ukr`), either two git
refs `<base> <head>` or a single integer `<PR#>` (no refs = current branch vs its
merge-base, uncommitted included), and `--help`.

## Step 0 — `--help`
If `--help` or the bare word `help` is present: try `jb2b review-help`. That shell
function currently fails in repos where `justfile.v2` isn't at the git root (rescue-serverless
keeps it at `backend/src/lambdas/api/fast/justfile.v2`) — on `no justfile.v2 at <root>`,
fall back to `just --justfile backend/src/lambdas/api/fast/justfile.v2 review-help`
(adjust the path for other repos). Print the recipe list it outputs and STOP.

## Step 1 — run the CLI once (collect the diff)
`REPO=$(git rev-parse --show-toplevel)`. From `~/dotfiles/claude/.claude/scripts`:

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
3. For each finding, work out its hunk id by parsing `diff.txt` the same way
   `lgtm.diffparse` does: files in top-to-bottom order get `F0`, `F1`, … (0-indexed);
   within a file, hunks (`@@ … @@` blocks) get `H0`, `H1`, … in order. Use the hunk
   that actually contains the flagged code — don't assume it's a file's first hunk.
   `line` = a real line number from that hunk (prefer an added line).
4. Write `$OUT/findings.json` matching `lgtm.model.Finding` **exactly** — flat
   `severity_emoji` + `severity_score`, not nested:
   ```json
   {"meta": {"ref": "…", "base": "…", "mode": "local|refs|pr",
             "generated": "YYYY-MM-DD HH:MM", "repo": "…", "lang": "ukr|eng|both"},
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
   - `meta.ref`/`base`/`mode`/`repo` must match exactly what Step 1 just used (read
     them back from the stderr log or from `$OUT`'s directory name) — the CLI reloads
     this meta verbatim on the next run.
   - No verified findings? Write `"findings": []` — an empty array is a valid result,
     not a failure.

## Step 3 — re-render and open
Re-run the **exact same command** from Step 1 (same `--repo`/`--pr`/`--refs`, same
`--lang` if you want to force it — the CLI logs when `--lang` overrides
`findings.json`'s stored language). It now finds `findings.json` and renders your
findings inline, pinned to their hunks. Open the printed page path (`open` on macOS,
`xdg-open` on Linux). Tell the user it's ready — comment/discuss happens by talking to
you directly in this session (no clipboard loop).

## Notes
- `--reply` / the live comment→Claude loop is **removed** here — it returns as a real
  server-backed live loop in Milestone 2 (SSE, inbox/outbox), not as a static rebuild.
- Engine lives in `~/dotfiles/claude/.claude/scripts/lgtm/` (`cli.py`, `render.py`,
  `diffparse.py`, …). Full contract: `rescue-serverless/.lgtm/design.md`.
