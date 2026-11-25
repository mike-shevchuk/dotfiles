#!/usr/bin/env bash
# win-split.sh [session] — pick the last window of status row 0 by display WIDTH, not by index:
# indexes have gaps once renumber-windows is off, so the global index-halving @win_split piles windows onto row 1.
# Sets the session-level @win_split (overrides the global formula). Run from hooks in .tmux.conf.local.
s=${1:-$(tmux display -p '#S')}
tmux has -t "$s" 2>/dev/null || exit 0
split=$(tmux list-windows -t "$s" -F '#I	#W' | python3 -c '
import sys, unicodedata as u
LEFT, PAD = 14, 12  # row-0 status-left width · per-item state icons + "N:" + separator
w = lambda t: sum(2 if u.east_asian_width(c) in "WF" else 0 if u.combining(c) or c == "️" else 1 for c in t)
rows = [l.rstrip("\n").split("\t", 1) for l in sys.stdin if l.strip()]
sizes = [w(n) + PAD for _, n in rows]
half, acc = (sum(sizes) + LEFT) / 2 - LEFT, 0
for (i, _), sz in zip(rows, sizes):
    acc += sz
    if acc >= half:
        print(i); break
')
[ -z "$split" ] || tmux set -t "$s" @win_split "$split"
