#!/usr/bin/env bash
# deck_sessions_test.sh — live check of deck.lua's /state.sessions (Hammerspoon running): a window linked into two
# sessions (like W42 / w42) is listed once. Creates and kills its own sessions dedupA / dedupB.
set -u
T=$(grep '^DECK_TOKEN=' ~/.hammerspoon/.env | cut -d= -f2-)
trap 'tmux kill-session -t dedupA 2>/dev/null; tmux kill-session -t dedupB 2>/dev/null' EXIT
id=$(tmux new-session -d -s dedupA -P -F '#{window_id}' sleep 600)
tmux new-session -d -s dedupB sleep 600
tmux link-window -s "$id" -t dedupB:
sleep 4 # deck.lua lists windows every 3 s
echo "━━━ xh ━━━ xh -b GET localhost:7777/state X-Deck-Token:\$T" >&2
n=$(xh -b --ignore-stdin GET localhost:7777/state "X-Deck-Token:$T" | jq --arg id "$id" '[.sessions[] | select(.id == $id)] | length')
dups=$(xh -b --ignore-stdin GET localhost:7777/state "X-Deck-Token:$T" | jq '[.sessions[].id] | length - (unique | length)')
[ "$n" = 1 ] && echo "  ok   linked window once" >&2 || echo "  FAIL linked window listed $n times" >&2
[ "$dups" = 0 ] && echo "  ok   no duplicate ids at all" >&2 || echo "  FAIL $dups duplicate ids" >&2
[ "$n" = 1 ] && [ "$dups" = 0 ] && echo PASS || { echo FAIL; exit 1; }
