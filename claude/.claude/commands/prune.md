---
description: "Звільнити RAM: закрити тимчасові Claude-вікна своєї tmux-сесії (лід)"
argument-hint: "[tmux-session]"
---
1. Run `just -g mem prune $ARGUMENTS` (default = your own tmux session) and show its table verbatim in a code block.
2. For every `✅ можна закрити` row, one line in Ukrainian: what that window was for and whether its result is already reported/merged (your knowledge of the teammate + its `.status` file). Not reported yet → say so; recommend keeping it.
3. Ask Mike which to close (AskUserQuestion, multiSelect). Never close a window without his answer. Rows with `чернетка`/`працює`/`лід` are not offered.
4. Close: `just -g mem kill "<s:i> …"` — it re-checks each window and prints free memory after. Report that line.

Transcripts stay on disk: `claude --resume` in that project brings a session back.
