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

echo "→ idle prompt: an agent resting at its prompt is not waiting and asks nothing" >&2
echo '{}' | "$here/agent-state.sh" done
echo '{"message":"Claude is waiting for your input","notification_type":"idle_prompt"}' | "$here/agent-state.sh" waiting
check idle-state-kept "$(opt @agent_state)" done
check idle-no-ask "$(opt @agent_ask_kind)$(opt @agent_ask)" ""
echo '{"message":"Need the staging URL","notification_type":"idle_prompt"}' | "$here/agent-state.sh" waiting
check idle-custom-kind "$(opt @agent_ask_kind)" idle
check idle-custom-text "$(opt @agent_ask)" "Need the staging URL"
check idle-custom-state "$(opt @agent_state)" done

echo "→ trailing semicolon survives" >&2
echo '{"message":"run: ls;","notification_type":"permission_prompt"}' | "$here/agent-state.sh" waiting
check semicolon "$(opt @agent_ask)" "run: ls;"

echo "→ other / tabs+newlines / length" >&2
echo '{}' | "$here/agent-state.sh" done
printf '{"message":"a\\tb\\nc %s"}' "$(printf 'x%.0s' $(seq 400))" | "$here/agent-state.sh" waiting
check kind "$(opt @agent_ask_kind)" other
check other-not-waiting "$(opt @agent_state)" done
v=$(opt @agent_ask)
check no-tab-nl "$([[ $v != *$'\t'* && $v != *$'\n'* ]] && echo y)" y
check len-le-300 "$([ ${#v} -le 300 ] && echo y)" y

echo "→ working clears" >&2
echo '{}' | "$here/agent-state.sh" working
check ask-cleared "$(opt @agent_ask)" ""
check kind-cleared "$(opt @agent_ask_kind)" ""
check at-cleared "$(opt @agent_ask_at)" ""

echo "→ permission names the pending tool (the Notification only says 'needs your permission')" >&2
echo '{"tool_name":"Bash","tool_input":{"command":"touch /tmp/x\nsecond line"}}' | "$here/agent-state.sh" working
echo '{"message":"Claude needs your permission","notification_type":"permission_prompt"}' | "$here/agent-state.sh" waiting
check perm-tool "$(opt @agent_ask)" "Bash: touch /tmp/x"
echo '{"tool_name":"Bash","tool_input":{"command":"printf a\tb"}}' | "$here/agent-state.sh" working
check tool-no-tab "$(opt @agent_tool)" "Bash: printf a b"
echo '{"tool_name":"Edit","tool_input":{"file_path":"/a/b.lua"}}' | "$here/agent-state.sh" working
echo '{"message":"Claude needs your permission","notification_type":"permission_prompt"}' | "$here/agent-state.sh" waiting
check perm-file "$(opt @agent_ask)" "Edit: /a/b.lua"
echo '{"message":"Claude is waiting for your input","notification_type":"idle_prompt"}' | "$here/agent-state.sh" waiting
check idle-default-ignored "$(opt @agent_ask)" "Edit: /a/b.lua"
echo '{}' | "$here/agent-state.sh" done
check tool-cleared "$(opt @agent_tool)" ""

echo "→ AskUserQuestion → choice" >&2
cat <<'J' | "$here/agent-state.sh" working
{"tool_name":"AskUserQuestion","tool_input":{"questions":[
 {"question":"Which DB?","header":"DB","multiSelect":false,"options":[{"label":"Postgres","description":"x"},{"label":"SQLite","description":"y"},{"label":"Дуже довга назва варіанту, що точно більша за сорок символів","description":"z"}]},
 {"question":"Second?","header":"S","multiSelect":true,"options":[{"label":"a","description":""},{"label":"b","description":""}]}]}}
J
check state "$(opt @agent_state)" waiting
check kind "$(opt @agent_ask_kind)" choice
check ask "$(opt @agent_ask)" "Which DB?"
check opts-n "$(opt @agent_ask_opts | jq length)" 3
check opt0 "$(opt @agent_ask_opts | jq -r '.[0]')" Postgres
check opt-le-40 "$(opt @agent_ask_opts | jq '.[2] | length <= 40')" true
check multi "$(opt @agent_ask_multi)" false
check nq "$(opt @agent_ask_n)" 2
check at-is-number "$(opt @agent_ask_at | grep -Ec '^[0-9]+$')" 1

echo "→ idle Notification keeps choice" >&2
echo '{"message":"Claude is waiting for your input","notification_type":"idle_prompt"}' | "$here/agent-state.sh" waiting
check kind-kept "$(opt @agent_ask_kind)" choice
check ask-kept "$(opt @agent_ask)" "Which DB?"
check opts-kept "$(opt @agent_ask_opts | jq length)" 3

echo "→ ≤6 options" >&2
jq -nc '{tool_name:"AskUserQuestion",tool_input:{questions:[{question:"q",multiSelect:true,options:[range(9)|{label:"o\(.)"}]}]}}' | "$here/agent-state.sh" working
check opts-max6 "$(opt @agent_ask_opts | jq length)" 6
check multi-true "$(opt @agent_ask_multi)" true

echo '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"q","options":[]}]}}' | "$here/agent-state.sh" working
check opts-empty "$(opt @agent_ask_opts)" "[]"

echo "→ another tool clears choice" >&2
echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | "$here/agent-state.sh" working
check state-working "$(opt @agent_state)" working
for o in @agent_ask @agent_ask_kind @agent_ask_at @agent_ask_opts @agent_ask_multi @agent_ask_n; do check "$o-cleared" "$(opt $o)" ""; done

echo "→ transcript: path, ctx, descs, head" >&2
tr_dir=$(mktemp -d); TR="$tr_dir/s.jsonl"
cat > "$TR" <<'J'
{"type":"user","message":{"role":"user","content":"Зроби деплой<system-reminder>ignore me</system-reminder>"}}
{"type":"user","isMeta":true,"message":{"role":"user","content":"meta caveat"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hmm"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Дивлюся конфіг."}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls -la\necho two"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"secret output"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/x/deck.lua"}}]}}
{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"subagent noise"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Два шляхи:\nперший\nдругий"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[{"question":"Куди деплой?"}]}}]}}
J
echo "{\"transcript_path\":\"$TR\",\"tool_name\":\"Bash\"}" | "$here/agent-state.sh" working
check transcript "$(opt @agent_transcript)" "$TR"
echo "{\"transcript_path\":\"$TR\",\"message\":\"Claude needs your permission to use Bash\",\"notification_type\":\"permission_prompt\"}" | "$here/agent-state.sh" waiting
check ctx "$(opt @agent_ask_ctx)" "Два шляхи: · перший · другий"
echo '{"tool_name":"Bash"}' | "$here/agent-state.sh" working
check ctx-cleared "$(opt @agent_ask_ctx)" ""
check transcript-kept "$(opt @agent_transcript)" "$TR"
jq -nc --arg tr "$TR" '{transcript_path:$tr,tool_name:"AskUserQuestion",tool_input:{questions:[{question:"q",header:"Деплой",options:[{label:"a",description:"перший варіант"},{label:"b"},{label:"c",description:("x"*200)}]}]}}' | "$here/agent-state.sh" working
check choice-ctx "$(opt @agent_ask_ctx)" "Два шляхи: · перший · другий"
check head "$(opt @agent_ask_head)" "Деплой"
check descs "$(opt @agent_ask_descs | jq -c '.[0:2]')" '["перший варіант",""]'
check desc-le-80 "$(opt @agent_ask_descs | jq '.[2] | length')" 80
echo '{"tool_name":"Bash"}' | "$here/agent-state.sh" working
check descs-cleared "$(opt @agent_ask_descs)$(opt @agent_ask_head)" ""

echo "→ chat subcommand (works outside tmux)" >&2
chat=$(env -u TMUX "$here/agent-state.sh" chat "$TR" 15)
check chat-roles "$(jq -r '[.msgs[].r] | join("")' <<<"$chat")" "uattat"
check chat-user "$(jq -r '.msgs[0].x' <<<"$chat")" "Зроби деплой"
check chat-bash "$(jq -r '.msgs[2].x' <<<"$chat")" "🔧 Bash: ls -la"
check chat-edit "$(jq -r '.msgs[3].x' <<<"$chat")" "🔧 Edit: /x/deck.lua"
check chat-ask "$(jq -r '.msgs[-1].x' <<<"$chat")" "❓ Куди деплой?"
check chat-no-noise "$(grep -c 'secret output\|subagent noise\|meta caveat\|ignore me' <<<"$chat")" 0
check chat-n "$(env -u TMUX "$here/agent-state.sh" chat "$TR" 2 | jq -c '[.msgs[].r]')" '["a","t"]'
check chat-missing "$(env -u TMUX "$here/agent-state.sh" chat /nope.jsonl 15)" '{"msgs":[],"err":"no transcript"}'

echo "→ info subcommand: doing / sum / tok / model per transcript, one JSON line each" >&2
TR2="$tr_dir/done.jsonl"
cat > "$TR2" <<'J'
{"type":"user","message":{"role":"user","content":"go"}}
{"type":"assistant","isSidechain":true,"message":{"model":"x","usage":{"input_tokens":999999},"content":[{"type":"text","text":"subagent"}]}}
{"type":"assistant","message":{"model":"claude-opus-5-5","usage":{"input_tokens":10,"cache_read_input_tokens":150000,"cache_creation_input_tokens":990,"output_tokens":5},"content":[{"type":"text","text":"Готово: деплой пройшов.\n\n- **Далі** — нічого.\nтретій рядок"}]}}
J
info=$(env -u TMUX "$here/agent-state.sh" info "$TR" "$TR2" /nope.jsonl)
check info-lines "$(wc -l <<<"$info" | tr -d ' ')" 2
i1=$(jq -c --arg f "$TR" 'select(.f == $f)' <<<"$info"); i2=$(jq -c --arg f "$TR2" 'select(.f == $f)' <<<"$info")
check doing-tool "$(jq -r .doing <<<"$i1")" "Куди деплой?"
check doing-text "$(jq -r .doing <<<"$i2")" "Готово: деплой пройшов."
check sum "$(jq -r .sum <<<"$i2")" "Готово: деплой пройшов. · Далі — нічого."
check tok "$(jq -r .tok <<<"$i2")" 151000
check tok-none "$(jq -r .tok <<<"$i1")" 0
check model "$(jq -r .model <<<"$i2")" claude-opus-5-5
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$(printf 'д%.0s' $(seq 300))" > "$TR2"
check doing-le-60 "$(env -u TMUX "$here/agent-state.sh" info "$TR2" | jq '.doing | length')" 60
check sum-le-140 "$(env -u TMUX "$here/agent-state.sh" info "$TR2" | jq '.sum | length')" 140
rm -rf "$tr_dir"

echo "→ @agent_at on every event" >&2
tmux -L $S set -wu -t "$TMUX_PANE" @agent_at
echo '{}' | "$here/agent-state.sh" done
check agent-at "$(opt @agent_at | grep -Ec '^[0-9]+$')" 1

echo "→ outside tmux" >&2
out=$(echo '{}' | env -u TMUX "$here/agent-state.sh" waiting 2>&1); rc=$?
check silent "$out" ""
check exit0 "$rc" 0

[ $fails -eq 0 ] && echo "PASS" >&2 || { echo "FAIL ($fails)" >&2; exit 1; }
