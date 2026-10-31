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
hs = setmetatable({
  task = { new = function(path, _, args) spawned[#spawned + 1] = path .. " " .. table.concat(args or {}, " ")
    return setmetatable({}, { __index = function() return function(self) return self end end }) end },
  settings = { get = function(k) return k == "deck.meetBackup" and "0" or nil end },
  json = { encode = enc, decode = dec },
  fs = { mkdir = function(p) os.execute("mkdir -p '" .. p .. "'"); return true end, dir = function(p) local f = io.popen("ls '" .. p .. "' 2>/dev/null"); local names = {}
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
-- FM-6: a capture finished before the "reload" (stage done) must not be processed again
local DONE_AT = 1767270000
w(MD .. "/" .. name(DONE_AT) .. ".pcm", string.rep("x", 15)); w(MD .. "/" .. name(DONE_AT) .. ".stage", "done"); w(MD .. "/" .. name(DONE_AT) .. ".bid", DONE_AT .. "-1")

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

os.execute("rm -rf '" .. home .. "'")
print(fails == 0 and "PASS" or ("FAIL " .. fails))
os.exit(fails == 0 and 0 or 1)
