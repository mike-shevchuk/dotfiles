# `/review-html` skill — Design Spec

**Date:** 2026-06-02
**Branch:** `feat-review-html`
**Scope:** A Claude Code slash command that produces the same diff as tmux `prefix v`, has Claude explain the changes, and renders an interactive, self-contained HTML review page with collapsible explanations and a comment-back-to-Claude loop.

---

## 1. Goal

Give a single command, `/review-html`, that turns "the changes on my branch" into a browsable HTML review page:

- The same diff selection as tmux `prefix v` (current branch vs origin's default base, incl. uncommitted work), plus optional explicit refs or a PR number.
- Per-file collapsible sections; per-hunk diff + collapsible **Description** and **Problems** written by Claude in Ukrainian, English, or both.
- A comment loop so the user can discuss changes with Claude: per-hunk "Copy for Claude" (clipboard) **and** an "Export for Claude" round-trip via a file + `/review-html --reply`.

## 2. Non-goals (YAGNI)

- No live local server (the comment loop is file + clipboard, not a daemon).
- No full syntax highlighting — diff red/green line coloring only (offline, dependency-free, matches GitHub's PR look).
- No multi-PR dashboard, no hosting/sharing, no auth.

## 3. Architecture

Three pieces with clear boundaries:

| Unit | Responsibility | Interface |
|---|---|---|
| `claude/.claude/commands/review-html.md` | Orchestration prompt (the "skill"): resolve mode, get diff, drive Claude's analysis, run the generator, open the browser, handle `--reply`. | Invoked as `/review-html …`; runs Bash + Write + the generator. |
| `claude/.claude/scripts/review_html.py` | Pure generator: `(diff text, explanations.json, lang, meta) → self-contained .html`. No network, no deps beyond python3 stdlib. | CLI: `review_html.py --diff <f> --explanations <f> --lang <ukr|eng|both> --out <f> [--meta <f>]`. |
| `.claude-review/` (in repo, git-ignored) | Artifacts: `review-<ref>.html`, `explanations.json`, `comments.md`. | Files on disk. |

**Why a generator script + Claude-authored JSON** (not Claude hand-writing the HTML): consistent output, far fewer tokens, robust on large diffs, and the HTML structure lives in one testable place.

## 4. Command flow

```
/review-html [eng|ukr|both] [ <base> <head> | <PR#> ] [--reply] [--help]
```

Defaults: language = **ukr**; diff = current branch vs origin's default base.
`--help` (or `help`) prints the usage examples in §11 and exits without generating anything.

1. **Resolve the diff** (Bash):
   - no refs → `git diff "$(git merge-base <origin-default> HEAD)"` (= `prefix v` default; includes uncommitted work).
   - `<base> <head>` → `git diff "<base>...<head>"` (committed three-dot).
   - `<PR#>` (single integer arg) → `gh pr diff <PR#>`.
   - default base detection reuses the order in `tmux/scripts/git-compare.sh`: `origin/HEAD → origin/main → origin/master → origin/develop`.
2. **Analyze** (Claude): read the diff, split into files → hunks, write `.claude-review/explanations.json`:
   ```json
   {
     "meta": {"head": "...", "base": "...", "mode": "local|refs|pr", "generated": "<ts>", "lang": "ukr"},
     "files": [
       {"path": "...", "summary": {"ukr": "...", "eng": "..."},
        "hunks": [{"id": "F0H1", "header": "@@ … @@",
                   "description": {"ukr": "...", "eng": "..."},
                   "problems": [{"severity": "warn|info", "text": {"ukr": "...", "eng": "..."}}]}]}
     ]
   }
   ```
   Only the requested language key(s) are filled (`both` fills both; otherwise one).
3. **Generate** (Bash): `python3 review_html.py …` → `.claude-review/review-<ref>.html` (temp file + atomic rename). `<ref>` = sanitized head ref (`/`→`-`) for local/refs modes, or `pr<N>` for PR mode.
4. **Open**: `open` (macOS) / `xdg-open` (Linux); print the path as a fallback.

## 5. HTML page anatomy (self-contained, offline)

- **Top bar:** expand/collapse all · UK/EN toggle (only rendered in `both` mode) · "Export for Claude" · diff metadata (base → head, mode, timestamp).
- **Per file:** a `<details>` section — path + added/removed counts; collapsed by default for large sets.
- **Per hunk (inside the file):**
  - hunk `@@` header,
  - the diff body with dual line numbers and red/green line coloring (inline CSS; no external libs),
  - **📝 Description** — collapsible `<details>`, Claude's "what & why",
  - **⚠️ Problems** — collapsible `<details>`, only rendered if the hunk has problems; severity badge per item,
  - a **comment box** + **"Copy for Claude"** button.
- **Hunk anchor id** (e.g. `F0H1`) is stable per (file index, hunk index) so comments and Claude replies bind to the right hunk.

### Styling
Catppuccin-ish dark palette to match the user's tmux/editor theme; everything inline (one `<style>` block). Minimal vanilla JS (one `<script>` block): collapse-all, language toggle, clipboard copy, localStorage persistence, export.

## 6. Comment loop (A + C)

State: comments live in `localStorage`, keyed by `repo + ref + hunkId`, surviving reloads.

- **C — clipboard (instant):** "Copy for Claude" on a hunk copies a precise block:
  ```
  [review-html] <repo> @ <head> vs <base>
  file: <path>  hunk: <id> (<@@ header>)
  comment: <your text>
  ```
  User pastes into the Claude chat; Claude answers.
- **A — file round-trip:** "Export for Claude" writes all non-empty comments to `.claude-review/comments.md` (grouped by file → hunk, each with the hunk header + the user's comment). Then:
  - `/review-html --reply` → Claude reads `comments.md`, answers each comment, writes the answers back into `explanations.json` (a `replies` array per hunk), and **regenerates the HTML** so each thread shows the user's comment, Claude's reply, and a status (💬 open / ✅ addressed).

## 7. Error handling

- **Empty diff** → generator emits a page with a clear "Nothing to review" panel (mirrors `prefix v`'s message), not a blank page.
- **Not a git repo / bad `<PR#>` / missing `gh`** → the command prints a friendly message and stops; no half-written artifacts.
- **Generator** writes to `*.tmp` then renames (atomic); never leaves a blank/partial `.html`.
- **`--reply` with no `comments.md`** → message telling the user to Export from the page first.

## 8. Files touched

- `claude/.claude/commands/review-html.md` — new command.
- `claude/.claude/scripts/review_html.py` — new generator.
- `.gitignore` — add `.claude-review/`.
- `docs/superpowers/specs/2026-06-02-review-html-skill-design.md` — this spec.

## 9. Testing

1. **Generator unit:** feed a sample diff + explanations.json for each `lang` (ukr/eng/both); assert the HTML contains the expected sections, hunk anchors, language toggle (only in `both`), and that an empty diff yields the "Nothing to review" panel. `python3` only; no browser needed.
2. **Diff resolution:** assert the three modes produce the right `git diff`/`gh pr diff` invocation (no-refs = merge-base→worktree, refs = three-dot, PR# = gh).
3. **Round-trip:** export sample comments → `comments.md`; run `--reply` path; assert replies appear in regenerated HTML with correct hunk binding and status.
4. **Smoke:** `ruff check` the python; open a generated page manually and verify collapse, toggle, copy, export.

## 10. Deliverable

A PR from `feat-review-html` → `master` adding the command, the generator, the `.gitignore` entry, and this spec, with the testing above green.

## 11. Usage examples (`--help` output)

`/review-html --help` (or `help`) prints exactly this:

```text
/review-html — turn your branch's changes into an interactive HTML review page.

USAGE
  /review-html [eng|ukr|both] [ <base> <head> | <PR#> ] [--reply] [--help]

  language   eng | ukr | both     (default: ukr)
  <base> <head>  two refs to compare, PR-style (base ← head)
  <PR#>          a GitHub PR number (uses `gh pr diff`)
  --reply        read .claude-review/comments.md and answer, regenerate the page
  --help         show this help

EXAMPLES
  # Review the CURRENT branch vs origin's default base (main/master),
  # including uncommitted work — same diff as tmux `prefix v`. Ukrainian.
  /review-html

  # Same, but explanations in English / in both languages (UK·EN toggle in page)
  /review-html eng
  /review-html both

  # Compare two explicit branches, PR-style (changes of <head> over <base>)
  /review-html ukr origin/master feat-tmux-review-diff
  /review-html eng origin/develop origin/feature/payments

  # Review a specific GitHub PR by number (exactly what GitHub shows)
  /review-html ukr 28
  /review-html both 28

  # Continue the discussion after you click "Export for Claude" in the page:
  /review-html --reply
  #   → I read your comments, answer each one, and regenerate the page with
  #     my replies threaded under your comments (💬 open / ✅ addressed)

TYPICAL FLOW
  1. /review-html              → page opens in your browser
  2. expand a file → read 📝 Description / ⚠️ Problems per hunk
  3. either: "Copy for Claude" on a hunk → paste into chat (instant), or
     add comments → "Export for Claude" → /review-html --reply (threaded)
  4. iterate until ✅

NOTES
  • Runs on the CURRENT pane's repo (like `prefix v`); for PR# it uses `gh`.
  • Artifacts go to .claude-review/ (git-ignored): the .html, explanations.json,
    comments.md.
  • Empty diff → a clear "Nothing to review" page, never a blank one.
```
