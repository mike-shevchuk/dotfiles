---
description: Пояснити статуслайн вікна — кожен блок словами, без обрізання, плюс деталі (черга на dev, нагадування, /who). /sl [3 | W46:3 | lead]
---
# /sl — що зараз у статуслайні (Mike 19.11: «мод, який повністю пояснює, що зараз у статуслайні, і більше інфи»)

Run exactly one command and print its stdout VERBATIM in a code block:
`python3 ~/.claude/scripts/lead.py sl $ARGUMENTS`

No argument = the window this command runs in; `3` or `W46:3` = that teammate window; `lead` = the lead's line.
It prints every block of that window's statusline with its current value and what it means, the shared last line, then «ДЕТАЛЬНІШЕ» (full state text, all reminders, who is in the dev queue and why) and the /who groups.

Then at most 3 lines in Ukrainian: what in this window needs Mike now, what waits on the lead, what waits on dev. Never re-gather with tmux/gh — a missing fact belongs in `~/.claude/scripts/statusline_role.py`.
