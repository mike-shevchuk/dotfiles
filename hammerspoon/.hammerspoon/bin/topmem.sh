#!/bin/bash
# Top-10 processes by memory FOOTPRINT (top MEM: counts compressed + swapped pages; ps RSS hides
# them — a claude session showed 168 MB in RSS while holding ~450 MB).
# A claude process is named after its tmux window; a prewarmed one as "bg-spare".
# Output per line (sysmonitor.lua parses it): pid user kb cpu etime name
panes=$(tmux list-panes -a -F '#{pane_pid} #S:#I #W' 2>/dev/null)
top -l 1 -o mem -n 10 -stats pid,mem 2>/dev/null |
awk '$1 ~ /^[0-9]+$/ { v = $2; sub(/[+-]$/, "", v); u = substr(v, length(v)); n = v + 0
    if (u == "G") n *= 1048576; else if (u == "M") n *= 1024; else if (u == "B") n /= 1024
    print $1, int(n) }' |
while read -r pid kb; do
    read -r user cpu etime comm < <(ps -o user=,%cpu=,etime=,comm= -p "$pid") || continue
    name=${comm##*/}
    if [[ $name == 2.1.* || $name == claude ]]; then
        if [[ $(ps -o args= -p "$pid") == *bg-spare* ]]; then
            label="bg-spare (запасний)"
        else
            p=$pid label=""
            while [ "${p:-1}" -gt 1 ]; do
                label=$(awk -v p="$p" '$1 == p { $1 = ""; print substr($0, 2); exit }' <<<"$panes")
                [ -n "$label" ] && break
                p=$(ps -o ppid= -p "$p" | tr -d ' ')
            done
        fi
        name="claude ${label:-(не в tmux)}"
    fi
    echo "$pid $user $kb $cpu $etime $name"
done
