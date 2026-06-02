---
description: Render the current branch's changes (prefix-v diff) as an interactive HTML review page with per-hunk explanations (ukr/eng/both) and a comment-back-to-Claude loop.
argument-hint: "[eng|ukr|both] [ <base> <head> | <PR#> ] [--reply] [--help]"
---

# /review-html

Turn the changes under review into a self-contained HTML page the user can browse,
collapse, comment on, and discuss with you.

`$ARGUMENTS` may contain: a language (`eng|ukr|both`, default `ukr`), either two
git refs `<base> <head>` or a single integer `<PR#>`, and the flags `--reply` / `--help`.

## Step 0 — `--help`
If `--help` or the bare word `help` is present, print the contents of the
"Usage examples" section of
`docs/superpowers/specs/2026-06-02-review-html-skill-design.md` (§11) and STOP.

## Step 1 — resolve paths
- `GEN=~/dotfiles/claude/.claude/scripts/review_html.py`
- `DIR=.claude-review` (create it). All artifacts go here.
- Confirm you are inside a git repo (`git rev-parse --is-inside-work-tree`); if not,
  tell the user and STOP.

## Step 2 — `--reply` mode
If `--reply` is present:
1. Obtain the comments, trying in order until non-empty:
   `pbpaste` (macOS) → `xclip -selection clipboard -o` / `wl-paste` (Linux) →
   `.claude-review/comments.md` → newest `~/Downloads/comments.md`.
2. Save them verbatim to `.claude-review/comments.md`.
3. Read the existing `.claude-review/explanations.json`. For each comment (it carries
   `file:` and `hunk:` lines), find the matching file+hunk and append to that hunk's
   `replies` array an object: `{"comment": "<user text>", "reply": {"<lang>": "<your answer>"}, "status": "addressed"}`.
   Answer in the same language the page was generated with (read `meta.lang`).
4. Re-run the generator (Step 4) to regenerate the page, then open it (Step 5). STOP.

## Step 3 — compute the diff (normal mode)
Decide the mode from `$ARGUMENTS`:
- **PR number** (a lone integer, e.g. `28`): `gh pr diff <N> > .claude-review/diff.txt`
  (if `gh` is missing or the PR is invalid, tell the user and STOP). meta.mode=`pr`,
  head=`pr<N>`, base=`(github)`.
- **Two refs** `<base> <head>`: `git diff "<base>...<head>" > .claude-review/diff.txt`.
  meta.mode=`refs`.
- **No refs** (default): detect the base like git-compare.sh
  (`git symbolic-ref refs/remotes/origin/HEAD` → else `origin/main`→`origin/master`→`origin/develop`),
  then `BASE=$(git merge-base <default> HEAD)` and
  `git diff "$BASE" > .claude-review/diff.txt` (includes uncommitted work, = `prefix v`).
  meta.mode=`local`, head=current branch, base=the default ref.
If `.claude-review/diff.txt` is empty, still proceed — the generator renders a clear
"Nothing to review" page.

## Step 4 — write explanations + generate
1. Read `.claude-review/diff.txt`. Split it into files → hunks **in the same order
   `review_html.py` does** (hunks counted top-to-bottom per file; hunk ids `F<fileIdx>H<hunkIdx>`).
2. Write `.claude-review/explanations.json`:
   ```json
   {"meta":{"head":"…","base":"…","mode":"…","generated":"<YYYY-MM-DD HH:MM>","repo":"<basename of toplevel>","lang":"<ukr|eng|both>"},
    "files":[{"path":"…","summary":{"<lang>":"…"},
      "hunks":[{"description":{"<lang>":"…"},"problems":[{"severity":"warn|info","text":{"<lang>":"…"}}]}]}]}
   ```
   - Fill only the requested language key(s); for `both`, fill both `ukr` and `eng`.
   - `summary`: one line per file. `description`: what changed & why, per hunk.
   - `problems`: ONLY when you actually see a risk/bug/smell; otherwise omit the key.
   - Keep order aligned with the diff so hunk ids match.
3. Generate:
   ```bash
   python3 "$GEN" --diff .claude-review/diff.txt \
     --explanations .claude-review/explanations.json \
     --lang <lang> --meta .claude-review/explanations.json \
     --out ".claude-review/review-<ref>.html"
   ```
   `<ref>` = head ref with `/`→`-`, or `pr<N>`. (`--meta` reads the `meta` block from the
   same JSON.)

## Step 5 — open
`open .claude-review/review-<ref>.html` (macOS) or `xdg-open …` (Linux). Print the path.
Tell the user: comment in the page, then either "Copy for Claude" (paste here) or
"Export for Claude" → `/review-html --reply`.
