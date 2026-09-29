---
description: "Full code review of a PR: analyze diff, find bugs, post English developer-friendly review on GitHub"
argument-hint: "<PR number>"
---

# Review PR #$ARGUMENTS (English)

First, Read `~/.codex/review-pr-core.md` and follow its full methodology
(Steps 1–5: gather context, verify branch, read sources, analyze, gated
draft-then-post). Then apply this language layer:

## Language layer — English

- **Language:** English ONLY — both the terminal draft and the GitHub post.
- **Labels:**
  - Teaching block after each finding: `**Note:**`
  - Final checklist section: `## Action items`
  - Final table section: `## Summary` (columns: `# | Finding | Type | Severity | Status`)
- **Severity band names:** Critical (80-100) / Serious (60-79) / Moderate (30-59) / Minor (0-29).
- **Previous-review phrasing:**
  - "As I mentioned in my previous review — ..."
  - "I can see you fixed {X} from the last review — great work! ✅"
