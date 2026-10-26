#!/usr/bin/env bash
# sysmonitor_test.sh — live check (Hammerspoon running): the menu is built on open from the async refresh — its RAM %
# matches the title's, the process list is filled; a refresh leaves the menu-building to the open.
set -u
echo "━━━ hs ━━━ hs -q -t 20 -c '<sysmonitor.menu()>'" >&2
# one hs call (each extra one is a chance for the CLI to hang): the 10 s timer's async refresh fed the cache
out=$(hs -q -t 20 -c 'local s = require("modules.sysmonitor")
  local m = s.menu(); local ram, procs = "", 0
  for _, it in ipairs(m) do
    local t = tostring(it.title and (type(it.title) == "string" and it.title or it.title:getString()) or "")
    if t:match("^RAM:") then ram = t end
    if t:match("^%d+%.%s") then procs = procs + 1 end
  end
  return string.format("%d|%s|%d|%d", s.ramPct(), ram, procs, #m)')
echo "  got: $out" >&2
IFS='|' read -r pct ram procs n <<<"$out"
fails=0
check() { if [ "$2" = 1 ]; then echo "  ok   $1" >&2; else echo "  FAIL $1" >&2; fails=$((fails+1)); fi; }
check "ram % > 0"                   "$([ "${pct:-0}" -gt 0 ] && echo 1)"
check "menu RAM line = title %"     "$(echo "$ram" | grep -q "(${pct}%)" && echo 1)"
check "process list filled (≥5)"    "$([ "${procs:-0}" -ge 5 ] && echo 1)"
[ $fails = 0 ] && echo PASS || { echo "FAIL ($fails)"; exit 1; }
