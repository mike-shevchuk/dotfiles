#!/usr/bin/env bash
# fleet-board.sh — prefix F popup: fleet.json as a compact board.
# Usage: fleet-board.sh            → whole board (+ keypress to close)
#        fleet-board.sh <window>   → one window's detail card (fzf preview)
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
f=~/.claude/fleet-board/fleet.json
[ -r "$f" ] || die "no $f"
need jq "brew install jq"

dep=~/.claude/fleet-board/deploy.tsv
# deploy.tsv ("<pr>\t<badge>", from fleet-deploy.sh) → $b map; dpl = label text.
bar='($dep | split("\n") | map(select(. != "") | split("\t") | {(.[0]): .[1]}) | add // {}) as $b |
def dpl: {"🚀":"🚀 deploying","🟢":"🟢 on dev","❌":"❌ deploy failed"}[.] // "";
def bar: (. // 0) as $p | ($p/10|floor) as $n | ("█"*$n) + ("░"*(10-$n)) + " \($p)%";'

if [ -n "${1:-}" ]; then
    jq -r --arg w "$1" --rawfile dep <(cat "$dep" 2>/dev/null) "$bar"'
      .windows[$w] // empty |
      "\u001b[1mPR #\(.pr // "—")\u001b[0m" + (if .mirror then "  mirror #\(.mirror)" else "" end) + "   \(.linear // "")   " + ($b[(.pr // "" | tostring)] // "" | dpl),
      "\u001b[36m\(.title // "")\u001b[0m",
      (.what // ""), "",
      (.progress | bar), "",
      (.steps // [] | .[] | "  " + (if .done then "✅" else "⬜" end) + " " + .name), "",
      "\u001b[33m→ next:\u001b[0m \(.next // "")",
      (if .need_mike then "\u001b[1;41m 🙋 MIKE \u001b[0m \(.need_mike_what)" else empty end),
      (if .paused then "⏸ paused" else empty end)' "$f"
    exit 0
fi

jq -r --rawfile dep <(cat "$dep" 2>/dev/null) "$bar"'
  .updated as $u | "fleet board · updated \($u)\n",
  (.windows | to_entries[] | .value as $v |
    (if $v.need_mike then "🙋" elif $v.paused then "⏸ " else "  " end) + " " +
    (.key | .[0:34]) + "\t#\($v.pr // "—")\t\(if ($v.linear // "") == "" then "—" else $v.linear end)\t" + ($v.progress | bar) + "\t" + ($b[($v.pr // "" | tostring)] // "—") + "\t→ \($v.next // "")" +
    (if $v.need_mike then "\n     \u001b[1;31m🙋 \($v.need_mike_what)\u001b[0m" else "" end))' "$f" \
  | column -t -s $'\t'
printf '\npress any key…'; read -rsn1 _
