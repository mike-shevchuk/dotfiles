-- lua modules/deck_meet_test.lua  (T12: /meet past captures, /meet/pcm offsets, /log batches). No live Hammerspoon:
-- deck.lua is loaded against a stubbed `hs`, HOME is a throwaway dir. Needs deck.lua to expose M._handle = handle.
local dir = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = dir .. "/../?.lua;" .. package.path
local fails = 0
local function check(name, ok) print((ok and "  ok   " or "  FAIL ") .. name); if not ok then fails = fails + 1 end end

local home = os.tmpname(); os.remove(home)
os.execute("mkdir -p '" .. home .. "/.local/share/esp-deck/meetings'")
local MD = home .. "/.local/share/esp-deck/meetings"
local real_getenv = os.getenv
os.getenv = function(k) if k == "HOME" then return home end return real_getenv(k) end

-- minimal deterministic JSON (sorted keys; empty table → [])
local function enc(v)
  local t = type(v)
  if t == "nil" then return "null" elseif t == "boolean" or t == "number" then return tostring(v)
  elseif t == "string" then return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
  elseif t == "table" then
    if next(v) == nil or #v > 0 then local o = {}; for i, x in ipairs(v) do o[i] = enc(x) end; return "[" .. table.concat(o, ",") .. "]" end
    local ks = {}; for k in pairs(v) do if type(k) == "string" then ks[#ks + 1] = k end end; table.sort(ks)
    local o = {}; for _, k in ipairs(ks) do o[#o + 1] = enc(k) .. ":" .. enc(v[k]) end
    return "{" .. table.concat(o, ",") .. "}"
  end
  return "null"
end
local function dec(s) -- tiny JSON decoder
  local i = 1
  local function ws() i = s:find("%S", i) or #s + 1 end
  local val
  local function str() local j = i + 1; local o = {}
    while s:sub(j, j) ~= '"' do local c = s:sub(j, j); if c == "\\" then j = j + 1; c = s:sub(j, j) end; o[#o + 1] = c; j = j + 1 end
    i = j + 1; return table.concat(o) end
  function val() ws(); local c = s:sub(i, i)
    if c == "{" then local o = {}; i = i + 1; ws(); if s:sub(i, i) == "}" then i = i + 1; return o end
      while true do ws(); local k = str(); ws(); i = i + 1; o[k] = val(); ws(); local d = s:sub(i, i); i = i + 1; if d == "}" then return o end end
    elseif c == "[" then local o = {}; i = i + 1; ws(); if s:sub(i, i) == "]" then i = i + 1; return o end
      while true do o[#o + 1] = val(); ws(); local d = s:sub(i, i); i = i + 1; if d == "]" then return o end end
    elseif c == '"' then return str()
    else local w = s:match("^[%w%.%-]+", i); i = i + #w
      if w == "true" then return true elseif w == "false" then return false elseif w == "null" then return nil end; return tonumber(w) end
  end
  return val()
end

local nop = setmetatable({}, { __call = function(self) return self end, __index = function(self) return self end })
spawned = {}
local tasks = {} -- every hs.task: .cb (the exit callback), .interrupted
hs = setmetatable({
  task = { new = function(path, cb, args) spawned[#spawned + 1] = path .. " " .. table.concat(args or {}, " ")
    local t = setmetatable({ cb = cb, setCallback = function(self, c) self.cb = c; return self end,
      interrupt = function(self) self.interrupted = true; return self end }, { __index = function() return function(self) return self end end })
    tasks[#tasks + 1] = t
    return t end },
  settings = { get = function(k) return k == "deck.meetBackup" and "0" or nil end },
  json = { encode = enc, decode = dec },
  fs = { attributes = function(p) local f = io.popen("stat -f %m '" .. p .. "' 2>/dev/null"); local m = tonumber(f:read("a")); f:close(); return m end,
    mkdir = function(p) os.execute("mkdir -p '" .. p .. "'"); return true end, dir = function(p) local f = io.popen("ls '" .. p .. "' 2>/dev/null"); local names = {}
    for n in f:lines() do names[#names + 1] = n end; f:close(); local k = 0
    return function() k = k + 1; return names[k] end end },
  timer = { absoluteTime = function() return 0 end },
}, { __index = function() return nop end })
package.preload["modules.env"] = function() return { get = function(k) return k == "DECK_TOKEN" and "tok" or nil end } end
package.preload["modules.sysmonitor"] = function() return setmetatable({ ramPct = function() return 1 end }, { __index = function() return nop end }) end
package.preload["modules.todoist"] = function() return { tasks = {} } end


local function w(p, s) local f = assert(io.open(p, "w")); f:write(s); f:close() end
local function rd(p) local f = io.open(p, "rb"); if not f then return nil end; local s = f:read("a"); f:close(); return s end
local function name(at) return os.date("%Y-%m-%d_%H%M%S", at) end
os.execute("mkdir -p '" .. home .. "/Library/Logs'")
-- FM-6: a capture finished before the "reload" must not be processed again. A real run leaves no .pcm, and archive()
-- moves .stage/.bid into the named folder: only index.jsonl (id, bid, len) stays at the top
local DONE_AT = 1767270000
w(MD .. "/index.jsonl", enc({ id = name(DONE_AT), bid = DONE_AT .. "-1", len = 15, title = "Test meeting" }) .. "\n")

table.insert(package.searchers, 2, function(n) -- Lua 5.5 const loop-var shim (see deck_state_test.lua)
  if n ~= "modules.deck" then return nil end
  local f = assert(io.open(dir .. "/deck.lua")); local src = f:read("a"); f:close()
  src = src:gsub("(%f[%w]for )(%a%w*)( in [^\n]- do)\n", "%1%2__%3 local %2 = %2__\n")
  return assert(load(src, "@deck.lua"))
end)
local ok, deck = pcall(require, "modules.deck")
if not ok then print("  FAIL load deck.lua: " .. tostring(deck)); os.exit(1) end
local handle = deck._handle
local H = { ["X-Deck-Token"] = "tok" }
local function post(path, body) local b, c = handle("POST", path, H, body or ""); local ok2, j = pcall(dec, b or ""); return c, ok2 and type(j) == "table" and j or {}, b end

local AT = 1767261600
local ID = AT .. "-1"
local N = name(AT)

print("→ AC-18 past capture start is idempotent, no Mac room recording")
local c, j = post("/meet?start=1&id=" .. ID .. "&kind=note&past=1&lang=uk")
check("start → 200 Delivery {id, have=0, delivered=false}", c == 200 and j.id and j.have == 0 and j.delivered == false)
c, j = post("/meet?start=1&id=" .. ID .. "&kind=note&past=1&lang=uk")
check("repeated start → 200 again", c == 200 and j.have == 0)
local ff = 0; for _, s in ipairs(spawned) do if s:find("ffmpeg", 1, true) then ff = ff + 1 end end
check("past=1 never starts the Mac recording", ff == 0)
check("sidecar <name>.bid holds the board id", (rd(MD .. "/" .. N .. ".bid") or ""):match("%S+") == ID)

print("→ AC-19 chunks at offsets, resume without duplicates")
c, j = post("/meet/pcm?id=" .. ID .. "&off=0", string.rep("a", 10))
check("chunk 0 → have 10", c == 200 and j.have == 10)
c, j = post("/meet/pcm?id=" .. ID .. "&off=0", string.rep("a", 10))
check("same chunk again → have stays 10", c == 200 and j.have == 10)
check(".pcm named by the real start, 10 bytes", #(rd(MD .. "/" .. N .. ".pcm") or "") == 10)
c, j = post("/meet/pcm?id=" .. ID .. "&off=20", string.rep("b", 5))
check("a hole → 409 details.have=10", c == 409 and j.details and j.details.have == 10)
c, j = post("/meet/pcm?id=" .. ID .. "&off=10", string.rep("c", 5))
check("next chunk → have 15", c == 200 and j.have == 15)
c, j = post("/meet?stop=1&id=" .. ID .. "&len=20&rate=16000&fmt=ulaw", '{"marks":[],"gaps":[]}')
check("stop with a longer len → 409 details.have=15", c == 409 and j.details and j.details.have == 15)
check("409 message fits capture_state.reason (<=47)", type(j.message) == "string" and #j.message <= 47)
local nsp = #spawned
c, j = post("/meet?stop=1&id=" .. ID .. "&len=15&rate=16000&fmt=ulaw", '{"marks":[{"offset":3,"at":1767261603}],"gaps":[]}')
check("stop with the same len → 200 delivered", c == 200 and j.delivered == true and j.have == 15)
check("processing started once (meeting.py)", #spawned == nsp + 1)
c, j = post("/meet?stop=1&id=" .. ID .. "&len=15&rate=16000&fmt=ulaw", "{}")
check("repeated stop → 200 delivered, nothing processed twice", c == 200 and j.delivered == true and #spawned == nsp + 1)

print("→ FM-6 capture finished before a reload")
nsp = #spawned
c, j = post("/meet?stop=1&id=" .. DONE_AT .. "-1&len=15&rate=16000&fmt=ulaw", "{}")
check("stop on an already processed capture → 200 delivered, no reprocess", c == 200 and j.delivered == true and #spawned == nsp)
check("have = the received length after archive (events.md)", j.have == 15)
check("no stray .bid at the top for an archived capture", rd(MD .. "/" .. name(DONE_AT) .. ".bid") == nil)

print("→ same-second capture from another board id")
c, j = post("/meet?start=1&id=" .. AT .. "-2&kind=meet&past=1")
check("second id gets <name>-<seq>", c == 200 and rd(MD .. "/" .. N .. "-2.bid") ~= nil)

print("→ old board: numeric id, no kind")
c = post("/meet?start=1&id=1767265200&lang=uk")
check("legacy numeric id still 200", c == 200)
c = post("/meet?start=1&id=bad;id")
check("a malformed id is refused (4xx)", c >= 400 and c < 500)

print("→ AC-31 /log batches")
local LOG = home .. "/Library/Logs/esp-deck.log"
c, j = post("/log?from=1&to=3", "1 1767261600 first\n2 1767261601 second\n3 1767261602 third")
check("batch → 200 confirmed 3", c == 200 and j.confirmed == 3)
local lg = rd(LOG) or ""
local a, b, d = lg:find("first", 1, true), lg:find("second", 1, true), lg:find("third", 1, true)
check("lines appended in order", a and b and d and a < b and b < d)
check("with the board's real time", lg:find(os.date("%H:%M:%S", 1767261601), 1, true) ~= nil)
check("boardlog.seq updated to 3", ((rd(home .. "/.local/share/esp-deck/boardlog.seq") or ""):match("%d+")) == "3")
c, j = post("/log?from=1&to=4", "1 1767261600 first\n2 1767261601 second\n3 1767261602 third\n4 1767261603 fourth")
lg = rd(LOG) or ""
check("resend → only the new line, confirmed 4", c == 200 and j.confirmed == 4 and select(2, lg:gsub("first", "")) == 1 and lg:find("fourth", 1, true) ~= nil)
c, j = post("/log?from=5&to=4", "x")
check("to < from → 422", c == 422)
c = post("/log", "live line")
check("live /log without from/to still 200", c == 200 and (rd(LOG) or ""):find("live line", 1, true) ~= nil)

local function start(id, q) return post("/meet?start=1&id=" .. id .. (q or "")) end
local function stop(id, n, body) return post("/meet?stop=1&id=" .. id .. "&len=" .. n .. "&rate=16000&fmt=ulaw", body or "") end
local function chunk(id, off, s) return post("/meet/pcm?id=" .. id .. "&off=" .. off, s) end
local function meetState() local b = handle("GET", "/state", H, ""); return dec(b).meet end
local function reload() package.loaded["modules.deck"] = nil; deck = require("modules.deck"); handle = deck._handle end
local function isdir(p) os.execute("mkdir -p '" .. p .. "'") end
local function noprocess() return #spawned end

print("→ AC-21 a live stop with the backup running")
-- 1767265200 is live since «old board» above, its backup ffmpeg running
local LIVE = name(1767265200)
local bk = tasks[#tasks]
nsp = noprocess()
c, j = stop(1767265200, 0)
check("stop accepted → 200 delivered:true at once", c == 200 and j.delivered == true)
check("the backup got its interrupt, processing waits for it", bk.interrupted == true and noprocess() == nsp)
c, j = stop(1767265200, 0)
check("repeated stop while ffmpeg closes → delivered, no second interrupt path", c == 200 and j.delivered == true and noprocess() == nsp)
bk.cb()
check("ffmpeg closed → meeting.py once", noprocess() == nsp + 1)
check(".stage written before the spawn (AC-24: pending from the start)", (rd(MD .. "/" .. LIVE .. ".stage") or ""):match("%a+") == "stt")

print("→ AC-19 a chunk after processing (meeting.py deleted the .pcm)")
local A = AT + 100; local AN = name(A); local AID = A .. "-1"
start(AID, "&kind=meet&past=1"); chunk(AID, 0, string.rep("a", 15)); stop(AID, 15)
os.remove(MD .. "/" .. AN .. ".pcm") -- what meeting.py does
nsp = noprocess()
c, j = chunk(AID, 15, "zzzzz")
check("late chunk → 200 Delivery delivered, have = received", c == 200 and j.delivered == true and j.have == 15)
c, j = chunk(AID, 0, "zzzzz")
check("resend from 0 → the same, nothing written", c == 200 and j.have == 15 and rd(MD .. "/" .. AN .. ".pcm") == nil)
c, j = stop(AID, 15)
check("repeated stop → have = len, delivered", c == 200 and j.have == 15 and j.delivered == true)
c, j = start(AID, "&kind=meet&past=1")
check("repeated start → delivered, no .pcm back", c == 200 and j.delivered == true and j.have == 15 and rd(MD .. "/" .. AN .. ".pcm") == nil)
check("no second processing", noprocess() == nsp)

print("→ FM-6 reload at each stage")
local B = AT + 200; local BN = name(B); local BID = B .. "-1"
start(BID, "&kind=meet&past=1"); chunk(BID, 0, string.rep("b", 15))
reload() -- T12 DoD: a reload between chunks and stop
nsp = noprocess()
c, j = stop(BID, 15)
check("reload between chunks and stop → delivered, kind/past survive", c == 200 and j.delivered == true and noprocess() == nsp + 1 and spawned[#spawned]:find(" meet 1 ", 1, true))
for _, st in ipairs({ "stt", "spk", "sum", "err" }) do
  w(MD .. "/" .. BN .. ".stage", st); os.remove(MD .. "/" .. BN .. ".pcm")
  reload(); nsp = noprocess()
  c, j = stop(BID, 15)
  check("stage " .. st .. ", .pcm gone, reload, repeated stop → 200 have 15, no reprocess", c == 200 and j.delivered == true and j.have == 15 and noprocess() == nsp)
end
reload(); nsp = noprocess()
c, j = post("/meet?stop=1&id=" .. DONE_AT .. "-1&len=15&rate=16000&fmt=ulaw", "")
check("index-only capture after a reload → have 15", c == 200 and j.have == 15 and noprocess() == nsp)
c, j = start(DONE_AT .. "-2", "&kind=meet&past=1")
check("another board id in an archived capture's second gets its own name", c == 200 and j.id == name(DONE_AT) .. "-2" and j.delivered == false)
stop(DONE_AT .. "-2", 0)

print("→ AC-20/23 CaptureClose")
local C = AT + 300; local CN = name(C); local CID = C .. "-1"
start(CID, "&kind=meet&past=1"); chunk(CID, 0, string.rep("c", 15))
nsp = noprocess()
for _, bad in ipairs({ '{"marks":"x"}', '{"gaps":3}', '{"marks":{"a":1}}', '{"gaps":[{"offset":1}]}', '{"gaps":[{"offset":1,"gap_ms":0,"cause":"reboot"}]}',
  '{"gaps":[{"offset":1,"gap_ms":5,"at":1}]}', '{"marks":[{"offset":1}]}', '{"marks":[{"offset":-1,"at":1}]}', '[1', '[1]', '{"marks":[5]}' }) do
  c, j = stop(CID, 15, bad)
  check("malformed " .. bad .. " → 422 meet.damaged", c == 422 and j.code == "meet.damaged" and noprocess() == nsp)
end
c, j = stop(CID, 15, '{"marks":[{"offset":999999,"at":1}],"gaps":[{"offset":999999,"gap_ms":100,"cause":"card"}]}')
check("a bookmark past the end → delivered, meeting.py clamps it", c == 200 and j.delivered == true and noprocess() == nsp + 1)
check("close.json handed over in argv", spawned[#spawned]:find(CN .. ".close.json", 1, true) ~= nil and rd(MD .. "/" .. CN .. ".close.json") ~= nil)

print("→ AC-18 a voice note never enters the live path")
for i, kind in ipairs({ "journal", "agent" }) do
  local n0 = #spawned
  local nid = (AT + 400 + i) .. "-1"
  c = start(nid, "&kind=" .. kind)
  check(kind .. " without past → 200, no recording, no ffmpeg", c == 200 and meetState().state ~= "rec" and #spawned == n0)
  stop(nid, 0)
  check(kind .. " reaches meeting.py as a note", spawned[#spawned]:find(" note ", 1, true) ~= nil)
end

print("→ a past capture during a live meeting")
local L = AT + 500; local LID = L .. "-1"
start(LID, "&kind=meet"); chunk(LID, 0, "live")
local lbk = tasks[#tasks]
check("live start → rec + backup", meetState().state == "rec" and spawned[#spawned]:find("ffmpeg", 1, true) ~= nil)
local P = AT + 600; start(P .. "-1", "&kind=meet&past=1"); chunk(P .. "-1", 0, "past")
c, j = stop(P .. "-1", 4)
check("its stop leaves rec and the backup alone", c == 200 and j.delivered and meetState().state == "rec" and not rawget(lbk, "interrupted"))
local nt = (AT + 650) .. "-1"; start(nt, "&kind=journal"); stop(nt, 0)
check("so does a note's stop (no past flag)", meetState().state == "rec" and not rawget(lbk, "interrupted"))

print("→ AC-16b the past flag changes on a live capture")
c = start(LID, "&kind=meet&past=1")
nsp = noprocess()
c, j = stop(LID, 4)
check("stop → backup interrupted, delivered", c == 200 and j.delivered == true and lbk.interrupted == true)
lbk.cb()
check("still handed over as live (past=0: meeting.py keeps the backup)", noprocess() == nsp + 1 and spawned[#spawned]:find(" meet 0 ", 1, true) ~= nil)
check("rec is over", meetState().state ~= "rec")

print("→ AC-24 a failed run leaves pending")
local F = AT + 700; local FN = name(F); local FID = F .. "-1"
start(FID, "&kind=meet&past=1"); chunk(FID, 0, "ffff"); stop(FID, 4)
local function pending(bid) for _, x in ipairs(meetState().pending) do if x.bid == bid then return x.stage end end end
check("pending from the moment of the stop", pending(FID) == "stt")
tasks[#tasks].cb(1, "Traceback", "")
check("failure → terminal .stage, out of pending", (rd(MD .. "/" .. FN .. ".stage") or ""):match("%a+") == "err" and pending(FID) == nil)
local G = AT + 710; local GN = name(G); local GID = G .. "-1"
start(GID, "&kind=meet&past=1"); stop(GID, 0)
tasks[#tasks].cb = nil; os.execute("touch -t 202001010000 '" .. MD .. "/" .. GN .. ".stage'")
check("meeting.py killed unseen (old .stage) → out of pending", pending(GID) == nil)
local Z = AT + 720; local ZN = name(Z); local ZID = Z .. "-1"
start(ZID, "&kind=meet&past=1"); stop(ZID, 0); os.rename(MD .. "/" .. ZN .. ".stage", MD .. "/z.gone") -- archived
tasks[#tasks].cb(0, "not json", "")
check("no failure mark beside an archived capture", rd(MD .. "/" .. ZN .. ".stage") == nil)
os.remove(MD .. "/" .. ZN .. ".bid") -- archived in this session: the name still belongs to ZID
tasks[#tasks].cb(0, enc({ id = ZN, bid = ZID, title = "Test meeting" }), "")
c, j = start(Z .. "-2", "&kind=meet&past=1")
check("another board id, same second, archived this session → its own name", c == 200 and j.id == ZN .. "-2")
stop(Z .. "-2", 0)

print("→ AC-20 disk errors → 507")
local D = AT + 800; local DN = name(D); local DID = D .. "-1"
isdir(MD .. "/" .. DN .. ".meta")
c, j = start(DID, "&kind=meet&past=1")
check("start, .meta can't be written → 507 meet.disk_full", c == 507 and j.code == "meet.disk_full" and #j.message <= 47)
os.remove(MD .. "/" .. DN .. ".meta")
start(DID, "&kind=meet&past=1"); chunk(DID, 0, "dddd")
isdir(MD .. "/" .. DN .. ".close.json")
nsp = noprocess()
c, j = stop(DID, 4, '{"marks":[],"gaps":[]}')
check("stop, close can't be written → 507, not delivered, nothing spawned", c == 507 and noprocess() == nsp)
os.remove(MD .. "/" .. DN .. ".close.json")
isdir(MD .. "/" .. DN .. ".stage")
c, j = stop(DID, 4, '{"marks":[],"gaps":[]}')
check("stop, .stage can't be written → 507", c == 507 and noprocess() == nsp)
os.remove(MD .. "/" .. DN .. ".stage")
c, j = stop(DID, 4, '{"marks":[],"gaps":[]}')
check("space back: the retry delivers", c == 200 and j.delivered == true and noprocess() == nsp + 1)
local SEQF = home .. "/.local/share/esp-deck/boardlog.seq"
local seq0 = rd(SEQF)
os.rename(LOG, LOG .. ".x"); isdir(LOG)
c, j = post("/log?from=9&to=9", "9 1767261600 lost")
check("/log, the log can't be written → 507", c == 507 and j.confirmed == nil)
os.remove(LOG); os.rename(LOG .. ".x", LOG)
local realopen = io.open
io.open = function(p, m) -- ENOSPC on the write of the log; the seq must stay
  if p == LOG then local f = realopen(p, m); return setmetatable({ write = function() return nil, "No space left" end,
    close = function() f:close(); return true end }, {}) end
  return realopen(p, m)
end
c, j = post("/log?from=9&to=9", "9 1767261600 lost")
io.open = realopen
check("/log, a failed write → 507, seq not advanced", c == 507 and j.confirmed == nil and rd(SEQF) == seq0)
os.rename(SEQF, SEQF .. ".x"); isdir(SEQF)
c, j = post("/log?from=9&to=9", "9 1767261600 kept")
check("/log, seq can't be written → 507, never confirmed", c == 507 and j.confirmed == nil)
os.remove(SEQF); os.rename(SEQF .. ".x", SEQF)

print("→ an unsynced clock: short id, current firmware")
local realtime = os.time
local now = realtime()
os.time = function(t) if t then return realtime(t) end return now end
c, j = post("/meet?start=1&id=57&lang=uk")
check("short numeric id → 200", c == 200 and j.id ~= nil)
local sid = j.id
now = now + 7
c, j = post("/meet/pcm?id=57&off=0", "abcd")
check("chunk seconds later lands in the same capture", c == 200 and j.id == sid and j.have == 4)
now = now + 7
c, j = post("/meet/pcm?id=57&off=4", "ef")
check("next chunk → offsets hold", c == 200 and j.have == 6)
now = now + 7
c, j = post("/meet?stop=1&id=57&len=6&rate=16000&fmt=ulaw")
check("stop → delivered", c == 200 and j.delivered == true and j.id == sid)
tasks[#tasks].cb() -- its backup ffmpeg closed
check("t0 is the Mac's clock, not 1970", tonumber(spawned[#spawned]:match(" uk (%d+) ")) > 1700000000)
now = now + 7
os.execute("sleep 1.1") -- the name comes from os.date's real clock
c, j = post("/meet?start=1&id=57&lang=uk")
check("the same short id after a reboot is a new capture", c == 200 and j.delivered == false and j.id ~= sid)
os.time = realtime

print("→ contract: ids and the error envelope")
os.execute("ls '" .. MD .. "' > '" .. home .. "/before'")
c, j = post("/meet/pcm?id=abc&off=0", "junk")
check("/meet/pcm id=abc → 422 meet.damaged", c == 422 and j.code == "meet.damaged")
os.execute("ls '" .. MD .. "' > '" .. home .. "/after'")
check("nothing written for a bad id", rd(home .. "/before") == rd(home .. "/after"))
c = select(1, post("/meet?start=1&id=123456789012"))
check("an id longer than the contract → 422", c == 422)
local b403, c403 = handle("POST", "/meet?start=1&id=" .. AT, {}, "")
local j403 = dec(b403)
check("403 is an Error", c403 == 403 and j403.code == "auth.forbidden" and type(j403.message) == "string")
c, j = post("/meet/pcm?id=1793298707&off=0", "x")
check("503 is an Error", c == 503 and j.code == "meet.busy")

os.execute("rm -rf '" .. home .. "'")
print(fails == 0 and "PASS" or ("FAIL " .. fails))
os.exit(fails == 0 and 0 or 1)
