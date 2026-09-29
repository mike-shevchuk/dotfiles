#!/usr/bin/env bash
# fleet-sync.sh — mirror ~/.claude/fleet-board/fleet.json onto tmux windows:
#   @need_mike (🙋, from need_mike) · @deploy (🚀/🟢/❌, from deploy.tsv by pr).
# Called from status-left via #() once per status-interval; prints nothing.
# fleet.json is owned by the lead session — read-only here.
d=~/.claude/fleet-board; f=$d/fleet.json; dep=$d/deploy.tsv
[ -r "$f" ] || exit 0
# Refresh the GitHub deploy cache in the background when >60s old (never blocks).
if [ -z "$(find "$dep" -mmin -1 2>/dev/null)" ]; then
    nohup "$(dirname "$0")/fleet-deploy.sh" >/dev/null 2>&1 &
fi
# "<window name>\t<need 1|>\t<deploy badge>" per fleet.json entry.
want=$(jq -r --rawfile dep <(cat "$dep" 2>/dev/null) '
  ($dep | split("\n") | map(select(. != "") | split("\t") | {(.[0]): .[1]}) | add // {}) as $b
  | .windows | to_entries[]
  | "\(.key)\t\(if .value.need_mike then "1" else "" end)\t\($b[(.value.pr // "" | tostring)] // "")"' "$f" 2>/dev/null)
tmux list-windows -a -F '#{window_id}	#{window_name}	#{@need_mike}	#{@deploy}' | while IFS=$'\t' read -r id name cur_need cur_dep; do
    line=$(printf '%s\n' "$want" | awk -F'\t' -v n="$name" '$1 == n' | head -1)
    need=$(printf '%s' "$line" | cut -f2); dp=$(printf '%s' "$line" | cut -f3)
    [ "$need" = "$cur_need" ] || tmux set -w -t "$id" @need_mike "$need"
    [ "$dp" = "$cur_dep" ] || tmux set -w -t "$id" @deploy "$dp"
done
