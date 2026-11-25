---
description: "Що змерджено за N днів (за замовчуванням — вчора) і що лишилось: таблиці + на паузі + що від тебе"
argument-hint: "[N днів: 1 2 3 4 5]"
---
Run exactly one command from the fast dir and print its stdout VERBATIM in a code block (already formatted, live data — never re-gather with gh):
`cd ~/code/b2b/rescue-serverless/backend/src/lambdas/api/fast && just --justfile justfile.v2 merged $ARGUMENTS`
(= `jb2b merged [N]`; N = days back, default 1 = since yesterday 00:00; script `~/.claude/fleet-board/bin/merged.py`, short names `w<N>/pr-short.tsv`, plain words = first sentence of the card's «Що це»).

Then (Mike 13.11 format):
- one line: «<період>: змерджено N PR · лишилось M · на паузі K»;
- a box «Для тебе» with exactly what waits on Mike now (tries / approvals / GitHub reviews), each try with its exact `jb2b …-try` command (copyable, outside the box), or «🟢 ТИ ВІЛЬНИЙ ~N хв (до ≈HH:MM)» + hourglass when nothing waits.
Never a bare PR number — always `#N PUN-x · short meaning`.
