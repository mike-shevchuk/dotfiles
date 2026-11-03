---
description: "End-of-day recap for the rescue-serverless sprint board — shipped commits/PRs + per-task progress bars (runs the jb2b today-recap justfile recipe)"
argument-hint: "[today|week]  (no arg = today)"
---

# /today-recap — sprint recap in the bar UI

Thin wrapper around the local justfile recipe `jb2b today-recap` (topic
`.just_dir_2/todoist.just`). It reads the current-sprint Todoist section and
prints SHIPPED (commits + PRs merged via git/gh) plus each task's 🏁 pipeline +
✅ checklist progress bars.

## Instructions

1. Pick the recipe from the argument:
   - no arg or `today` → `today-recap`
   - `week` → `week-recap`

2. Run it via Bash (explicit `--justfile` path is the reliable form; the `jb2b`
   alias may not load in a non-interactive shell):

   ```bash
   just --justfile /Users/mikeshevchuk/code/b2b/rescue-serverless/backend/src/lambdas/api/fast/justfile.v2 <recipe>
   ```

3. Print the recipe's output **verbatim** inside a fenced code block — it is
   already a formatted ASCII/emoji terminal view; do not reformat, summarize,
   or re-render it. Add commentary only if the recipe errored (missing
   `TODOIST_TOKEN`, `gh` not authed, disk full) — then say what failed and the
   one-line fix.

4. Terminal language: match Mike (Ukrainian by default). No Mermaid — the view
   is already ASCII.

## Notes

- Read-only. Nothing is written to Todoist or git.
- Data source: `scripts/todoist_recap.py --days 1|7` + `scripts/todoist_today.py`
  parsers. Progress = 🏁 bold pipeline stage + ✅ DONE-WHEN checkboxes.
- Related recipes: `today` / `tomorrow` / `board` / `day` / `week-recap`
  (`jb2b todoist-help` lists all).
