#!/usr/bin/env bash
# test-agent-state.sh — checks agent-state.sh against a throwaway tmux server (-L asktest).
set -u
here=$(cd "$(dirname "$0")" && pwd)
S=asktest
tmux -L $S -f /dev/null new -d -s t
trap 'tmux -L $S kill-server 2>/dev/null' EXIT
export TMUX="$(tmux -L $S display -p '#{socket_path}'),0,0"
export TMUX_PANE="$(tmux -L $S display -p -t t '#{pane_id}')"
fails=0
opt() { tmux -L $S show -wv -t "$TMUX_PANE" "$1" 2>/dev/null; }
check() { if [ "$2" = "$3" ]; then echo "  ok   $1" >&2; else echo "  FAIL $1: got '$2', want '$3'" >&2; fails=$((fails+1)); fi; }

echo "→ permission prompt" >&2
echo '{"message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}' | "$here/agent-state.sh" waiting
check ask "$(opt @agent_ask)" "Claude needs your permission to use Bash"
check kind "$(opt @agent_ask_kind)" permission
check at-is-number "$(opt @agent_ask_at | grep -Ec '^[0-9]+$')" 1
check state "$(opt @agent_state)" waiting

echo "→ idle prompt" >&2
echo '{"message":"Claude is waiting for your input","notification_type":"idle_prompt"}' | "$here/agent-state.sh" waiting
check kind "$(opt @agent_ask_kind)" idle

echo "→ trailing semicolon survives" >&2
echo '{"message":"run: ls;","notification_type":"permission_prompt"}' | "$here/agent-state.sh" waiting
check semicolon "$(opt @agent_ask)" "run: ls;"

echo "→ other / tabs+newlines / length" >&2
printf '{"message":"a\\tb\\nc %s"}' "$(printf 'x%.0s' $(seq 400))" | "$here/agent-state.sh" waiting
check kind "$(opt @agent_ask_kind)" other
v=$(opt @agent_ask)
check no-tab-nl "$([[ $v != *$'\t'* && $v != *$'\n'* ]] && echo y)" y
check len-le-300 "$([ ${#v} -le 300 ] && echo y)" y

echo "→ working clears" >&2
echo '{}' | "$here/agent-state.sh" working
check ask-cleared "$(opt @agent_ask)" ""
check kind-cleared "$(opt @agent_ask_kind)" ""
check at-cleared "$(opt @agent_ask_at)" ""

echo "→ outside tmux" >&2
out=$(echo '{}' | env -u TMUX "$here/agent-state.sh" waiting 2>&1); rc=$?
check silent "$out" ""
check exit0 "$rc" 0

[ $fails -eq 0 ] && echo "PASS" >&2 || { echo "FAIL ($fails)" >&2; exit 1; }
