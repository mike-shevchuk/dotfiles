---
name: til
description: "Capture a TIL (Today I Learned) into the zettelkasten wiki — one lesson, verified, linked; browse later with `just -g til` / til-random"
---

# TIL — capture an engineering lesson

Turn a lesson into a permanent, findable wiki note. TILs compound: `just -g til`
(fzf browser), `just -g til-random` (spaced repetition), `just -g til-grep`.

## Input

- `$ARGUMENTS` given → that is the lesson (any language; keep the note in the
  language Mike used).
- Empty → mine THIS session: bugs found and why they happened, patterns
  corrected, tool tricks discovered, review findings that taught something.
  Propose 1-3 candidates, let Mike pick (AskUserQuestion), then write the
  picked ones.

## Note format (vault rules apply — frontmatter, wikilinks, Related)

Path: `~/zettelkasten/claude_code/wiki/til-YYYY-MM-DD-<slug>.md`

```markdown
---
tags: [wiki, til, topic/<area>]
type: wiki
project: <slug — where it was learned; misc if general>
date: YYYY-MM-DD
aliases: []
---
# TIL — <one-line lesson>

**Що вивчив:** 2-4 речення — суть, простими словами.

**Чому це так:** механіка/причина під капотом (не just "so it works").

**Приклад:**
```<lang>
<real code/command from the actual situation — not a toy>
```

**Як застосовувати далі:** конкретне правило на майбутнє (greppable formulation).

## Related
- [[<related wiki page or MOC>]]
```

## Rules

1. **One TIL = one lesson.** Two lessons → two files.
2. **Verify before writing** — if the lesson makes a technical claim, check it
   (run the command, read the doc/source). No folklore in the vault.
3. Use the REAL example from the session (file:line, actual command) — that is
   what makes it stick.
4. Append a line to `~/zettelkasten/claude_code/log.md`:
   `- [[wiki/til-YYYY-MM-DD-<slug>]] \`til\` — <one-liner>  YYYY-MM-DD`
5. Link at least one Related note ([[wikilink]]); orphans are lint failures.
6. If a TIL contradicts an existing wiki page — do NOT overwrite; add
   `#conflict` tag and mention both views (vault rule).
7. Finish by printing: path + `just -g til` reminder.
