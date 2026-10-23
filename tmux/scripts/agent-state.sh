#!/usr/bin/env bash
# agent-state.sh <working|waiting|done> — Claude Code hook: tag this pane's
# tmux window with @agent_state (⏳ working / 💤 waiting for the lead / ✅ in the window list). No-op outside tmux.
# On waiting it also keeps the Notification's question for the deck: @agent_ask (one line, ≤300 chars),
# @agent_ask_kind (permission|idle|other), @agent_ask_at (epoch s); any other state drops all three.
[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || exit 0
w=(-w -t "$TMUX_PANE")
tmux set "${w[@]}" @agent_state "$1" 2>/dev/null
if [ "$1" = waiting ]; then
  { IFS= read -r kind; IFS= read -r ask; } < <(jq -r '
      (.notification_type // "" | if . == "permission_prompt" then "permission" elif . == "idle_prompt" then "idle" else "other" end),
      (.message // "" | gsub("[\t\n\r]"; " ") | .[:300])' 2>/dev/null)
  # tmux eats a trailing ';' as a command separator — escape it
  [[ $ask == *';' ]] && ask="${ask%;}\\;"
  tmux set "${w[@]}" @agent_ask "$ask" 2>/dev/null
  tmux set "${w[@]}" @agent_ask_kind "${kind:-other}" 2>/dev/null
  tmux set "${w[@]}" @agent_ask_at "$(date +%s)" 2>/dev/null
else
  tmux set -u "${w[@]}" @agent_ask \; set -u "${w[@]}" @agent_ask_kind \; set -u "${w[@]}" @agent_ask_at 2>/dev/null
fi
exit 0
