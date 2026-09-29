#!/usr/bin/env bash
# agent-state.sh <working|waiting|done> — Claude Code hook: tag this pane's
# tmux window with @agent_state (⏳/✋/✅ in the window list). No-op outside tmux.
[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] && tmux set -w -t "$TMUX_PANE" @agent_state "$1" 2>/dev/null
exit 0
