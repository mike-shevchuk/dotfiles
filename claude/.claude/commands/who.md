---
description: Хто на кого чекає — тімейти поточної tmux-сесії, згруповані за блокером (на тобі · на ліді · на dev · на іншому вікні · пауза · вільні)
---
# /who — хто кого блокує (Mike 18.11: «заблоковані — це мною чи кимось ще, треба краще показувати»)

Run exactly one command and print its stdout VERBATIM in a code block:
`LEAD_SESSION=$(tmux display -p '#S') python3 ~/.claude/scripts/lead.py who`

It prints the one-line badge (`👥N · 🔄 працюють · 🙋 на тобі · 🧭 на ліді · 🚂 на dev · ⏳ на іншому вікні · ⏸ пауза · 💤 вільні`, zero groups hidden), then one block per group: window · name · the reason from its «Чекаю на».

Then at most 3 lines in Ukrainian:
1. 🙋 на тобі — what exactly each one needs from Mike (one line each, with the command or the decision).
2. 🧭 на ліді — what the lead does next for each, with ≈HH:MM counted from `date` (never from memory).
3. 🚂 / ⏳ — what they wait for and when it clears (≈HH:MM).
Never re-gather with tmux/gh — a missing fact belongs in `lead.py` (`blocked_by`, `cmd_who`).
