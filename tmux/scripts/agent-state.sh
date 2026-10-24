#!/usr/bin/env bash
# agent-state.sh <working|waiting|done> — Claude Code hook: tag this pane's
# tmux window with @agent_state (⏳ working / 💤 waiting for the lead / ✅ in the window list). No-op outside tmux.
# On waiting it also keeps the Notification's question for the deck: @agent_ask (one line, ≤300 chars),
# @agent_ask_kind (permission|idle|other), @agent_ask_at (epoch s); any other state drops all of them.
# Only a permission dialog (or AskUserQuestion, below) sets @agent_state waiting; the default idle_prompt is ignored.
# PreToolUse of AskUserQuestion ("working" + that tool_name) is a question too: kind choice, plus
# @agent_ask_opts (JSON array of ≤6 labels, ≤40 chars each), @agent_ask_multi (true|false), @agent_ask_n (questions),
# @agent_ask_descs (JSON array parallel to opts, ≤80 chars each), @agent_ask_head (questions[0].header).
# Every call keeps @agent_transcript (the session JSONL); a question also gets @agent_ask_ctx = the assistant's
# last text (≤600 chars, newlines → " · "). PreToolUse keeps @agent_tool ("Bash: <cmd>"): a permission ask shows it.
# agent-state.sh chat <transcript> [n] → {"msgs":[{r:u|a|t, x}]} for the deck's chat panel (no tmux needed).
# agent-state.sh info <transcript>... → what each agent is doing / its last summary / context tokens (deck's sessions).
# Every event also stamps @agent_at (epoch s).

# a tool call {name, input} in one line: "Bash: <first line ≤80>" / "Edit: <file_path>" / "Name"
TOOL='if .name == "Bash" then "Bash: " + ((.input.command // "") | split("\n")[0] | .[:80])
  elif .input.file_path then "\(.name): \(.input.file_path)" else .name end'
# main-thread turns only: no subagents, no meta caveats, no tool results, no reminders
TURNS='select((.isSidechain // false | not) and (.isMeta // false | not))
  | if .type == "user" then
      (.message.content | if type == "string" then . else [.[]? | select(.type == "text") | .text] | join("\n") end)
      | gsub("(?s)<system-reminder>.*?</system-reminder>"; "") | gsub("^\\s+|\\s+$"; "")
      | select(. != "" and (startswith("<") | not)) | {r: "u", x: .}
    elif .type == "assistant" then .message.content[]? |
      if .type == "text" then {r: "a", x: .text}
      elif .type == "tool_use" then {r: "t", x: (
        if .name == "AskUserQuestion" then "❓ " + (.input.questions[0].question // "")
        else "🔧 " + ('"$TOOL"') end)}
      else empty end
    else empty end'

if [ "$1" = chat ]; then
  [ -r "${2:-}" ] || { echo '{"msgs":[],"err":"no transcript"}'; exit 0; }
  # ponytail: last 4000 lines only — a huge session's early turns never reach the board
  tail -n 4000 "$2" | jq -nc --argjson n "${3:-15}" "[inputs | $TURNS | .x |= .[:500]] | {msgs: .[-\$n:]}" 2>/dev/null \
    || echo '{"msgs":[],"err":"bad transcript"}'
  exit 0
fi

if [ "$1" = info ]; then # info <transcript>... → per readable file {f, doing ≤60, sum ≤140, tok, model} on one line
  shift
  for f; do
    [ -r "$f" ] || continue
    tail -n 300 "$f" | jq -nc --arg f "$f" '
      def lines: [splits("\n") | gsub("\\*\\*|`"; "") | sub("^#+\\s*"; "") | gsub("^\\s+|\\s+$"; "") | sub("^([-*•]|\\d+\\.)\\s+"; "") | select(. != "")];
      [inputs | select((.isSidechain // false | not) and (.isMeta // false | not))] as $l
      | ([$l[] | select(.type == "assistant" and .message.usage)] | last | .message) as $m
      | [$l[] | '"$TURNS"' | select(.r != "u")] as $t
      | {f: $f,
         doing: ($t | last // {r: "a", x: ""} | if .r == "t" then .x | sub("^(🔧|❓) "; "") else (.x | lines | .[0] // "") end | .[:60]),
         sum: ([$t[] | select(.r == "a")] | last | .x // "" | lines | .[:2] | join(" · ") | .[:140]),
         tok: ($m.usage // {} | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)),
         model: ($m.model // "")}' 2>/dev/null
  done
  exit 0
fi

[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || exit 0
w=(-w -t "$TMUX_PANE")
ASK=(@agent_ask @agent_ask_kind @agent_ask_at @agent_ask_opts @agent_ask_multi @agent_ask_n
     @agent_ask_ctx @agent_ask_descs @agent_ask_head @agent_tool)
put() { # tmux eats a trailing ';' as a command separator — escape it
  local v=$2; [[ $v == *';' ]] && v="${v%;}\\;"
  tmux set "${w[@]}" "$1" "$v" 2>/dev/null
}
clear_ask() { for o in "${ASK[@]}"; do tmux set -u "${w[@]}" "$o" 2>/dev/null; done; }
ctx() { # the assistant's last text before the question
  [ -r "$tr" ] || return 0
  tail -n 400 "$tr" | jq -nr "[inputs | $TURNS | select(.r == \"a\") | .x] | last // \"\"
    | gsub(\"\\\\s*\\n\\\\s*\"; \" · \") | gsub(\"\\t\"; \" \") | .[:600]" 2>/dev/null
}

in=$(cat)
state=$1
tr=$(jq -r '.transcript_path // ""' <<<"$in" 2>/dev/null)
[ -n "$tr" ] && put @agent_transcript "$tr"
# resting at the prompt (idle_prompt's default text, ~1 min after Stop) is no event: not waiting, asks nothing
[ "$state" = waiting ] && [ "$(jq -r '.notification_type + "|" + .message' <<<"$in" 2>/dev/null)" = \
  "idle_prompt|Claude is waiting for your input" ] && exit 0
put @agent_at "$(date +%s)" # last event: the deck's age
if [ "$state" = working ] && [ "$(jq -r '.tool_name // ""' <<<"$in" 2>/dev/null)" = AskUserQuestion ]; then
  q='.tool_input.questions'
  put @agent_state waiting
  put @agent_ask "$(jq -r "$q[0].question // \"\" | gsub(\"[\\t\\n\\r]\"; \" \") | .[:300]" <<<"$in")"
  put @agent_ask_kind choice
  put @agent_ask_opts "$(jq -c "[$q[0].options[]? | .label // \"\" | gsub(\"[\\t\\n\\r]\"; \" \") | .[:40]][:6]" <<<"$in")"
  put @agent_ask_descs "$(jq -c "[$q[0].options[]? | .description // \"\" | gsub(\"[\\t\\n\\r]\"; \" \") | .[:80]][:6]" <<<"$in")"
  put @agent_ask_head "$(jq -r "$q[0].header // \"\" | gsub(\"[\\t\\n\\r]\"; \" \") | .[:40]" <<<"$in")"
  put @agent_ask_multi "$(jq -r "$q[0].multiSelect // false" <<<"$in")"
  put @agent_ask_n "$(jq -r "$q | length" <<<"$in")"
  put @agent_ask_ctx "$(ctx)"
  put @agent_ask_at "$(date +%s)"
  exit 0
fi

if [ "$state" = waiting ]; then
  # a Notification while an AskUserQuestion is open must not overwrite its options
  [ "$(tmux show -wv -t "$TMUX_PANE" @agent_ask_kind 2>/dev/null)" = choice ] && exit 0
  { IFS= read -r kind; IFS= read -r ask; } < <(jq -r '
      (.notification_type // "" | if . == "permission_prompt" then "permission" elif . == "idle_prompt" then "idle" else "other" end),
      (.message // "" | gsub("[\t\n\r]"; " ") | .[:300])' <<<"$in" 2>/dev/null)
  # permission_prompt's message is just "Claude needs your permission" — the PreToolUse before it says what for
  [ "$kind" = permission ] && tool=$(tmux show -wv -t "$TMUX_PANE" @agent_tool 2>/dev/null) && [ -n "$tool" ] && ask=$tool
  # only an open dialog is "waiting"; an idle / other Notification keeps its text as an ask, the state stays
  [ "$kind" = permission ] && put @agent_state waiting
  put @agent_ask "$ask"
  put @agent_ask_kind "${kind:-other}"
  put @agent_ask_ctx "$(ctx)"
  put @agent_ask_at "$(date +%s)"
else
  put @agent_state "$state"
  clear_ask
  # the tool about to run: a permission prompt that follows names it
  [ "$state" = working ] && t=$(jq -r "select(.tool_name) | {name: .tool_name, input: .tool_input} | $TOOL | gsub(\"[\\t\\r]\"; \" \")" <<<"$in" 2>/dev/null) \
    && [ -n "$t" ] && put @agent_tool "$t"
fi
exit 0
