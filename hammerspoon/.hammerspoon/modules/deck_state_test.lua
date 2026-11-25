-- lua modules/deck_state_test.lua  (T2: GET /state ETag / 304 / meet.last / meet.pending). No live Hammerspoon:
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
os.date = function() return "12:00" end

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
hs = setmetatable({
  configdir = os.getenv("TMPDIR") or "/tmp", -- flex favourites: never the real config dir
  json = { encode = enc, decode = dec },
  fs = { attributes = function(p) local f = io.popen("stat -f %m '" .. p .. "' 2>/dev/null"); local m = tonumber(f:read("a")); f:close(); return m end,
    dir = function(p) local f = io.popen("ls '" .. p .. "' 2>/dev/null"); local names = {}
    for n in f:lines() do names[#names + 1] = n end; f:close(); local k = 0
    return function() k = k + 1; return names[k] end end },
  timer = { absoluteTime = function() return 0 end },
}, { __index = function() return nop end })
package.preload["modules.env"] = function() return { get = function(k) return k == "DECK_TOKEN" and "tok" or nil end } end
package.preload["modules.sysmonitor"] = function() return setmetatable({ ramPct = function() return 1 end }, { __index = function() return nop end }) end
package.preload["modules.todoist"] = function() return { tasks = {} } end

local function w(p, s) local f = assert(io.open(p, "w")); f:write(s); f:close() end
-- 7 meetings + a voice note last (AC-24: notes never take a meet.last place), oldest first; #1 old format, #7 new format
for n = 1, 7 do
  local e = { id = "m" .. n, at = 1000 + n, title = "Test meeting " .. n, summary = "s" .. n, body = "b" .. n }
  if n == 7 then e.bid = "1767261600-1"; e.kind = "meet"; e.past = true; e.actions = { "ping Bob" } end
  if n == 5 then e.actions = {}; for a = 1, 40 do e.actions[a] = string.rep("я", 400) end end -- 5 of these must not overflow the board's 48 KB
  local f = assert(io.open(MD .. "/index.jsonl", "a")); f:write(enc(e), "\n"); f:close()
end
do local f = assert(io.open(MD .. "/index.jsonl", "a")); f:write(enc({ id = "n1", title = "Нотатка", kind = "note", past = true, summary = "s" }), "\n"); f:close() end
w(MD .. "/p1.stage", "spk"); w(MD .. "/p1.bid", "1767265200-2")
w(MD .. "/d1.stage", "done"); w(MD .. "/d1.bid", "1767265300-3") -- finished: must not stay pending
os.execute("mkdir -p '" .. home .. "/.hammerspoon'") -- picks of a live window (@1) and of one closed long ago (@9)
w(home .. "/.hammerspoon/deck-jobpick.json", '{"@1":"/t/live.jsonl","@9":"/t/gone.jsonl"}')

-- Hammerspoon runs Lua 5.4; here Lua 5.5 makes a for-loop variable const, so deck.lua's assignments to a single-var loop variable are
-- rewritten on load (test-only shim; the file on disk is untouched).
table.insert(package.searchers, 2, function(name)
  if name ~= "modules.deck" then return nil end
  local f = assert(io.open(dir .. "/deck.lua")); local src = f:read("a"); f:close()
  src = src:gsub("(%f[%w]for )(%a%w*)( in [^\n]- do)\n", "%1%2__%3 local %2 = %2__\n")
  return assert(load(src, "@deck.lua"))
end)
local ok, deck = pcall(require, "modules.deck")
if not ok then print("  FAIL load deck.lua: " .. tostring(deck)); os.exit(1) end
local handle = deck._handle
check("deck.lua exposes M._handle", type(handle) == "function")
if type(handle) ~= "function" then os.exit(1) end

local H = { ["X-Deck-Token"] = "tok" }
local function get(inm) local h = { ["X-Deck-Token"] = "tok", ["If-None-Match"] = inm }; return handle("GET", "/state", h, "") end

print("→ AC-02 poll: ETag + 304")
local b1, c1, h1 = get(nil)
check("no If-None-Match → 200 (old firmware)", c1 == 200 and type(b1) == "string" and #b1 > 2)
local etag = h1 and h1["ETag"]
check("200 carries an ETag header", type(etag) == "string" and #etag > 0 and #etag <= 64)
local b2, c2, h2 = get(etag)
check("same ETag → 304", c2 == 304)
check("304 has an empty body", b2 == "" or b2 == nil)
check("304 repeats the ETag", h2 and h2["ETag"] == etag)
local _, c3, h3 = get("stale-etag")
check("different If-None-Match → 200 with the ETag", c3 == 200 and h3 and h3["ETag"] == etag)
local _, c4 = handle("GET", "/state", { ["If-None-Match"] = etag }, "")
check("no token → 403 (never 304)", c4 == 403)

print("→ AC-24 meetings back")
local s = dec(b1)
-- owner 2026-11-10: the board reads only last[0]; the other 4 + actions were ~27 % of every /state
check("meet.last is only the newest", s.meet and #s.meet.last == 1 and s.meet.last[1].id == "m7")
local n1 = s.meet.last[1]
check("the newest keeps id/bid/kind/past/title/at/summary/body, no actions", n1.bid == "1767261600-1" and n1.kind == "meet"
  and n1.past == true and n1.title == "Test meeting 7" and n1.summary == "s7" and n1.body == "b7" and n1.actions == nil)
check("meet.pending lists <id>.stage with bid", s.meet.pending and #s.meet.pending == 1 and s.meet.pending[1].bid == "1767265200-2" and s.meet.pending[1].stage == "spk")
check("no build announced → fw_sig absent/null", s.fw_sig == nil)
check("no `limits` (the board draws `lim`)", s.limits == nil and s.lim ~= nil)

print("→ Claude sessions: their own request (owner 2026-11-10)")
check("/state (old firmware) still carries sessions", type(s.sessions) == "table")
local lean = dec((handle("GET", "/state?s=1", H, "")))
check("/state?s=1: no sessions, a version sv instead", lean.sessions == nil and type(lean.sv) == "string" and #lean.sv > 0)
local sb, sc, sh = handle("GET", "/sessions", H, "")
check("/sessions → 200 {sessions} with an ETag", sc == 200 and type(dec(sb).sessions) == "table" and sh and sh.ETag)
local _, sc2 = handle("GET", "/sessions", { ["X-Deck-Token"] = "tok", ["If-None-Match"] = sh.ETag }, "")
check("/sessions same ETag → 304", sc2 == 304)
local _, sc3 = handle("GET", "/sessions", {}, "")
check("/sessions without the token → 403", sc3 == 403)
local sv = deck._sessVer
local base = { { id = "@1", claude = true, state = "busy", st = "working", doing = "a", ctx = 5, age = 3 } }
local function cp(t, f) local r = {}; for k, v in pairs(t[1]) do r[k] = v end; for k, v in pairs(f) do r[k] = v end; return { r } end
check("sv holds while only doing/ctx/age move", sv(base) == sv(cp(base, { doing = "b", ctx = 9, age = 70 })))
check("sv moves when a session's st moves", sv(base) ~= sv(cp(base, { st = "done" })))
check("sv moves when a window comes or goes", sv(base) ~= sv({}) and sv(base) ~= sv({ base[1], { id = "@2", state = "idle" } }))
local realopen = io.open
io.open = function(p, m) -- an announced build: FW_SHA + the signature `just ota` leaves in /tmp
  if p == "/tmp/deck-ota.sha" then return realopen(home .. "/fw.sha", m) elseif p == "/tmp/deck-ota.sig" then return realopen(home .. "/fw.sig", m) end
  return realopen(p, m)
end
w(home .. "/fw.sha", "abc123"); w(home .. "/fw.sig", "MEUCIQ-test-signature")
local announced = dec((get(nil)))
io.open = realopen
check("announced build → fw and fw_sig from /tmp/deck-ota.sig", announced.fw == "abc123" and announced.fw_sig == "MEUCIQ-test-signature")

print("→ state changes → new ETag")
w(MD .. "/p1.stage", "sum")
local b5, c5, h5 = get(etag)
check("changed state → 200 again", c5 == 200 and b5 ~= "")
check("changed state → different ETag", h5 and h5["ETag"] ~= etag)

print("→ ages tick, ETag holds")
local et = deck._stateEtag
local seed = function(age) return { cpu = age, ram = 2, time = "10:0" .. age % 10, sessions = { { id = "@1", st = "working", age = age } },
  asks = { { id = "@2", kind = "permission", text = "Bash?", age = age } } } end
check("only ages/gauges moved → same ETag", et(seed(3)) == et(seed(33)))
local moved = seed(3); moved.sessions[1].st = "waiting"
check("a session changed state → new ETag", et(moved) ~= et(seed(3)))
local more = seed(3); more.asks[2] = { id = "@3", kind = "choice", age = 1 }
check("a new ask → new ETag", et(more) ~= et(seed(3)))

print("→ a hung Finder / ps never piles up tasks (the board polls /mac and /panel every ~2 s)")
do
  local spawned, realTask = {}, hs.task
  hs.task = { new = function(path, cb, args)
    local t = { path = path, cb = cb, args = args }
    spawned[#spawned + 1] = t
    return setmetatable(t, { __index = function() return function() end end })
  end }
  local none = function() end
  hs.audiodevice = { defaultOutputDevice = none, defaultInputDevice = none }
  hs.brightness, hs.caffeinate, hs.host = { get = none }, { get = none }, { interfaceStyle = none }
  local function count(p) local n = 0; for _, t in ipairs(spawned) do if t.path == p then n = n + 1 end end; return n end
  handle("POST", "/mac", H, "")
  local first = count("/usr/bin/osascript")
  handle("POST", "/mac", H, ""); handle("POST", "/panel", H, ""); handle("POST", "/panel", H, "")
  check("/mac starts its osascripts once", first == 3)
  check("… and not again while they still run", count("/usr/bin/osascript") == first)
  check("/panel's ps starts once while it runs", count("/bin/sh") == 1)
  local n = #spawned
  for k = 1, n do local t = spawned[k]; if t.cb then t.cb(0, "") end end
  handle("POST", "/mac", H, "")
  check("finished → the next /mac refreshes again", count("/usr/bin/osascript") == first * 2)
  hs.task = realTask
end

print("→ Ghostty's flex: the sync tmux list-clients runs once per request burst, not once per lookup")
do
  local calls, realExec, realTimer = 0, hs.execute, hs.timer
  hs.execute = function(cmd) if cmd:find("list-clients", 1, true) then calls = calls + 1 end; return "1 /dev/ttys001 esp\n" end
  local clock = 1000
  hs.timer = setmetatable({ secondsSinceEpoch = function() return clock end }, { __index = realTimer })
  handle("POST", "/flexfav?ctx=Ghostty&g=0&f=1", H, "")
  check("/flexfav asks tmux once (it looks the session up 3 times)", calls == 1)
  clock = clock + 2
  handle("POST", "/flex?ctx=Ghostty&g=0", H, "")
  check("a request 2 s later asks again", calls == 2)
  hs.execute, hs.timer = realExec, realTimer
end

print("→ a closed window's transcript pick is forgotten")
do
  local function line(id) return id .. "\tesp:1\tzsh\t\tzsh" .. ("\t"):rep(13) end
  local function picks() local f = io.open(home .. "/.hammerspoon/deck-jobpick.json"); local d = f and dec(f:read("a")) or {}; if f then f:close() end; return d end
  deck._parseSessions("")
  check("tmux said nothing (not running?) → picks kept", picks()["@9"] == "/t/gone.jsonl")
  deck._parseSessions(line("@1") .. "\n" .. line("@2"))
  local p = picks()
  check("@9 is gone from tmux → its pick dropped", p["@9"] == nil)
  check("@1 still open → its pick kept", p["@1"] == "/t/live.jsonl")
end

print("→ tiki: list, card, reply (fleet_data.py stubbed; never the live board)")
do
  local runs, out = {}, '{"cards":[{"id":"WIN007","t":"x"}],"week":"W45"}'
  local realtask = hs.task
  hs.task = { new = function(_, cb, args)
    runs[#runs + 1] = args
    return { setEnvironment = function() end, start = function() cb(0, out) end }
  end }
  local function post(path, body) local b, c = handle("POST", path, H, body or ""); return c == 200 and dec(b) or nil, c, runs[#runs] end
  local r, _, a = post("/tiki")
  check("/tiki runs fleet_data.py tiki 0 (the newest board)", a and a[#a - 1] == "tiki" and a[#a] == "0" and r and r.cards and r.cards[1].id == "WIN007")
  post("/tiki?b=44")
  check("/tiki?b=44 asks board 44", runs[#runs][#runs[#runs]] == "44")
  local n0 = #runs
  post("/tiki?b=4;4")
  check("a bad board is the newest (cached), nothing run", #runs == n0)
  out = '{"id":"WIN007","blocks":[]}'
  r, _, a = post("/tiki?id=WIN007")
  check("/tiki?id= runs tiki 0 <id>", a and a[#a - 2] == "tiki" and a[#a] == "WIN007" and r and r.id == "WIN007")
  local n = #runs
  r = post("/tiki?id=x;rm")
  check("a bad id is not a card: the cached list, nothing run", #runs == n and r and r.cards)
  out = '{"ok":true,"id":"WIN007"}'
  r, _, a = post("/tikireply?id=WIN007&b=44", "варіант 1")
  check("/tikireply passes board + id + text as argv", a and a[#a - 3] == "tiki-reply" and a[#a - 2] == "44" and a[#a - 1] == "WIN007" and a[#a] == "варіант 1" and r and r.ok)
  out = '{"cards":[],"week":"W45"}'
  r = post("/tiki")
  check("a reply drops the cached list", r and #r.cards == 0)
  n = #runs
  local _, c = post("/tikireply?id=WIN007", "  ")
  check("an empty reply writes nothing", c ~= 200 and #runs == n)
  hs.task = realtask
end

print("→ no meetings dir yet")
os.execute("rm -rf '" .. MD .. "'")
hs.fs.dir = function() error("cannot open") end
local b6, c6 = get(nil)
local s6 = c6 == 200 and dec(b6)
check("missing meetings dir → 200, meet.pending []", s6 and #s6.meet.pending == 0)

os.execute("rm -rf '" .. home .. "'")
print(fails == 0 and "PASS" or ("FAIL " .. fails))
os.exit(fails == 0 and 0 or 1)
