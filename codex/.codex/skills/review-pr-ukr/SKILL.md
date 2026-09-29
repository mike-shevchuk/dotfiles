---
name: review-pr-ukr
description: "Full code review of a PR: analyze diff, find bugs, post Ukrainian beginner-friendly review on GitHub"
---

# Review PR #$ARGUMENTS (Ukrainian)

First, Read `~/.codex/review-pr-core.md` and follow its full methodology
(Steps 1–5: gather context, verify branch, read sources, analyze, gated
draft-then-post). Then apply this language layer:

## Language layer — Ukrainian

- **Language:** Ukrainian ONLY for the terminal draft (the user mentors
  beginner programmers — прості слова, реальний вплив, без жаргону).
- **GitHub post:** ALWAYS English — after the "go", translate the approved
  Ukrainian draft to English before `gh pr comment` / `gh pr review`
  (GitHub-пости — English-only, house rule).
- **Labels (у драфті):**
  - Teaching block after each finding: `**Порада:**`
  - Final checklist section: `## Що робити?`
  - Final table section: `## Підсумок` (колонки: `# | Знахідка | Тип | Severity | Статус`; статуси: "Потрібно виправити" тощо)
- **Severity band names:** Критично (80-100) / Серйозно (60-79) / Помірно (30-59) / Мінорно (0-29).
- **Previous-review phrasing:**
  - "Як я вже писав у попередньому рев'ю — ..."
  - "Бачу, що ти виправив {X} з минулого рев'ю — чудово! ✅"
