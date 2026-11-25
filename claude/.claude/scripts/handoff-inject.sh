#!/usr/bin/env bash
# SessionStart(clear) hook: inject the last handoff section, only into the lead window W<N>:1.
set -uo pipefail
cat >/dev/null  # hook JSON on stdin, unused
[ -n "${TMUX_PANE:-}" ] || exit 0
target=$(tmux display -p -t "$TMUX_PANE" '#S:#I' 2>/dev/null) || exit 0
[[ "$target" =~ ^W([0-9]+):1$ ]] || exit 0
n="${BASH_REMATCH[1]}"
f="$HOME/.claude/fleet-board/w$n/LEAD-HANDOFF.md"
[ -f "$f" ] || exit 0
# last "## … handoff…" section, up to the next non-handoff "## " heading
section=$(awk '/^## .*handoff/{buf=""; on=1} /^## / && !/handoff/{on=0} on{buf=buf $0 "\n"} END{printf "%s", buf}' "$f")
[ -n "$section" ] || exit 0
ctx="Ти лід W$n (вікно W$n:1), продовжуй з цього handoff.

$section"
jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
