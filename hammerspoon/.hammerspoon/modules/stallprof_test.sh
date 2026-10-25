#!/usr/bin/env bash
# stallprof_test.sh — live check (Hammerspoon running with stallprof): a 600 ms timer callback and a 700 ms sync
# hs.execute both land in deck-slow.log with their label; a fast callback does not.
set -u
LOG=~/Library/Logs/deck-slow.log
n0=$(wc -l < "$LOG")
echo "━━━ hs ━━━ hs -q -t 20 -c '<busy doAfter 600 ms, fast doAfter, hs.execute sleep 0.7, slow __gc>'" >&2
hs -q -t 20 -c 'local spin = function(ms) local t = hs.timer.absoluteTime() while (hs.timer.absoluteTime() - t) < ms * 1e6 do end end
  hs.timer.doAfter(0.1, function() spin(600) end)
  hs.timer.doAfter(0.2, function() spin(10) end)
  hs.timer.doAfter(0.3, function() hs.execute("sleep 0.7") end)
  local mt = { __gc = function() spin(550) end }; debug.getregistry()["stallprof.test"] = mt
  local sp = require("modules.stallprof"); sp.wrapGc()
  hs.timer.doAfter(0.5, function() setmetatable({}, mt); collectgarbage(); debug.getregistry()["stallprof.test"] = nil end)
  return "queued"'
sleep 3
new=$(tail -n +"$((n0 + 1))" "$LOG")
echo "$new" | sed 's/^/  log: /' >&2
fails=0
check() { if echo "$new" | grep -qE "$2"; then echo "  ok   $1" >&2; else echo "  FAIL $1" >&2; fails=$((fails+1)); fi; }
check "busy timer logged"      'slow timer\.doAfter .* [6-9][0-9]{2} ms'
check "slow finalizer logged" 'slow gc stallprof\.test [5-9][0-9]{2} ms'
check "sync execute logged"    'slow execute .*«sleep 0\.7» [7-9][0-9]{2} ms'
[ "$(echo "$new" | grep -c 'slow timer\.doAfter')" -le 3 ] && echo "  ok   fast timer not logged" >&2 || { echo "  FAIL fast timer logged" >&2; fails=$((fails+1)); }
[ $fails = 0 ] && echo PASS || { echo "FAIL ($fails)"; exit 1; }
