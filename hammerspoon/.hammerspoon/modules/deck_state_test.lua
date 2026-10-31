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
  json = { encode = enc, decode = dec },
  fs = { dir = function(p) local f = io.popen("ls '" .. p .. "' 2>/dev/null"); local names = {}
    for n in f:lines() do names[#names + 1] = n end; f:close(); local k = 0
    return function() k = k + 1; return names[k] end end },
  timer = { absoluteTime = function() return 0 end },
}, { __index = function() return nop end })
package.preload["modules.env"] = function() return { get = function(k) return k == "DECK_TOKEN" and "tok" or nil end } end
package.preload["modules.sysmonitor"] = function() return setmetatable({ ramPct = function() return 1 end }, { __index = function() return nop end }) end
package.preload["modules.todoist"] = function() return { tasks = {} } end

local function w(p, s) local f = assert(io.open(p, "w")); f:write(s); f:close() end
-- 7 meetings, oldest first; #1 old format (no bid/kind/past/actions), #7 new format
for n = 1, 7 do
  local e = { id = "m" .. n, at = 1000 + n, title = "Test meeting " .. n, summary = "s" .. n, body = "b" .. n }
  if n == 7 then e.bid = "1767261600-1"; e.kind = "note"; e.past = true; e.actions = { "ping Bob" } end
  local f = assert(io.open(MD .. "/index.jsonl", "a")); f:write(enc(e), "\n"); f:close()
end
w(MD .. "/p1.stage", "spk"); w(MD .. "/p1.bid", "1767265200-2")
w(MD .. "/d1.stage", "done"); w(MD .. "/d1.bid", "1767265300-3") -- finished: must not stay pending

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
check("meet.last has at most 5", s.meet and #s.meet.last == 5)
check("meet.last newest first", s.meet and s.meet.last[1] and s.meet.last[1].id == "m7" and s.meet.last[5].id == "m3")
local n1 = s.meet.last[1]
check("new-format entry keeps bid/kind/past/actions", n1.bid == "1767261600-1" and n1.kind == "note" and n1.past == true and n1.actions[1] == "ping Bob")
local old = s.meet.last[2]
check("old-format entry defaults actions [] kind meet past false", old and type(old.actions) == "table" and #old.actions == 0 and old.kind == "meet" and old.past == false)
check("meet.pending lists <id>.stage with bid", s.meet.pending and #s.meet.pending == 1 and s.meet.pending[1].bid == "1767265200-2" and s.meet.pending[1].stage == "spk")
check("no build announced → fw_sig absent/null", s.fw_sig == nil or real_getenv("NONE") ~= nil)

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

print("→ no meetings dir yet")
os.execute("rm -rf '" .. MD .. "'")
hs.fs.dir = function() error("cannot open") end
local b6, c6 = get(nil)
local s6 = c6 == 200 and dec(b6)
check("missing meetings dir → 200, meet.pending []", s6 and #s6.meet.pending == 0)

os.execute("rm -rf '" .. home .. "'")
print(fails == 0 and "PASS" or ("FAIL " .. fails))
os.exit(fails == 0 and 0 or 1)
