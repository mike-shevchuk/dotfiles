---
description: "Refresh Mike's memory on every open decision (fleet need-mike + teammate waits) — plain words, what was done, the exact question, a recommendation — ending in a one-line-answer box"
argument-hint: "[topic|window|PR]  (no args = all open decisions)"
---

# /decide — освіжи знання і дай відповісти одним рядком

Chat: Ukrainian. Mike has NOT touched these topics for a while — explain from zero, plain words, no jargon without a gloss.
Everything comes from LIVE sources, never from memory of earlier turns.

## Step 1 — collect open decisions
- `~/.claude/fleet-board/w*/need-mike.tsv` (newest week dir) and `LEAD-HANDOFF.md` "Waiting on Mike".
- `progress/*.md` — every `Чекаю на: Mike …` line.
- If `$ARGUMENTS` is given, keep only items matching it (window number, PR, Linear id, word).

## Step 2 — get the facts per item (read, don't guess)
- Progress file of the owning window, its `drafts/*` (proposal / change-map / pr body), the local commit (`git log -1 --format=%B <sha>` + `--stat`).
- Linear ticket via `mcp__linear__get_issue`: who created it (team vs fleet), status, priority, assignee.
- Say where each fact came from when it isn't obvious (file / commit / Linear link).

## Step 3 — one section per item
```
### N. W40:<win> — <ticket/PR> · <short name>: <what to answer>
**Що це.** problem in 2–4 plain lines, one real example if available
**Що зроблено.** sha, files, tests, CR/simplify state — local or pushed
**Питання.** the exact options and what each one triggers
**Раджу: <option>.** one-line why
```
Also flag: fleet-created ticket (not from the team) · low priority · what re-runs (try/train) the answer causes.

## Step 4 — end with the answer box (always LAST)
```
┌─ Mike, достатньо відповісти одним рядком ──────────────┐
│ 1. W40:<N> <teammate> · <topic>: «<A>» (раджу) / «<B>» │
│ ...                                                    │
│ Приклад: «1 так, 2 ні, 3 пауза»                        │
└────────────────────────────────────────────────────────┘
```

## Step 5 — when Mike answers
Every box line MUST start with the owner window W40:<N> (Mike 2026-10-08). Restate each decision in one line, dispatch to the owner windows (tmux send-keys, `LEAD HH:MM — Mike: …`), update need-mike.tsv / LEAD-HANDOFF.md. Never push, open a PR, or write to Linear on his behalf beyond what he said.
