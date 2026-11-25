---
description: Explain a fleet/justfile term in plain Ukrainian (what it is, why it exists, exact command, trap) — e.g. /glossary runtime-swap
argument-hint: "<term>"
---

# /glossary

`$ARGUMENTS` = one term from the fleet/justfile vocabulary (`runtime-swap`, `train`, `preflight`, `devcheck`, `try-lint`, `pull-main`, `JT`, `DEMO gate` …).

Answer in Ukrainian, terms stay English, max ~12 lines, in this shape:

1. **Що це** — one plain sentence.
2. **Навіщо** — the real incident/rule behind it (check memory `MEMORY.md` and `~/.claude/fleet-board/missions/_rules-*.md` first; grep the recipe in `backend/src/lambdas/api/fast/.just_dir_2/` for the actual behaviour — never answer from guess).
3. **Команда** — the exact `jb2b …` invocation with a real example.
4. **Пастка** — the one mistake people make with it.

Unknown term → say so and list the 3 closest names found by `rg -il "<term>" ~/.claude/fleet-board ~/.claude/projects/*/memory`. No term → list all terms you can find, one line each.
