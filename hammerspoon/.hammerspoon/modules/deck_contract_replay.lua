-- lua modules/deck_contract_replay.lua <requests>  (T31): real deck.lua answers for esp-deck's test/test_contract.py, which
-- checks them against contracts/openapi.yaml. No live Hammerspoon: deck.lua is loaded against a stubbed `hs`; HOME comes from
-- the caller (a throwaway dir, seeded by it). <requests>: "METHOD\tPATH\tIF-NONE-MATCH\tTOKEN\tHEX-BODY" lines.
-- Each reply is one JSON line on stdout: {status, headers, body}. Needs deck.lua to expose M._handle = handle.
local dir = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = dir .. "/../?.lua;" .. package.path
local home = assert(os.getenv("HOME"))

local function enc(v) -- minimal deterministic JSON (sorted keys; empty table → [])
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
    while s:sub(j, j) ~= '"' do local c = s:sub(j, j); if c == "" then error("bad JSON") end; if c == "\\" then j = j + 1; c = s:sub(j, j) end; o[#o + 1] = c; j = j + 1 end
    i = j + 1; return table.concat(o) end
  function val() ws(); local c = s:sub(i, i)
    if c == "{" then local o = {}; i = i + 1; ws(); if s:sub(i, i) == "}" then i = i + 1; return o end
      while true do ws(); local k = str(); ws(); i = i + 1; o[k] = val(); ws(); local d = s:sub(i, i); i = i + 1; if d == "}" then return o end end
    elseif c == "[" then local o = {}; i = i + 1; ws(); if s:sub(i, i) == "]" then i = i + 1; return o end
      while true do o[#o + 1] = val(); ws(); local d = s:sub(i, i); i = i + 1; if d == "]" then return o end end
    elseif c == '"' then return str()
    else local w = assert(s:match("^[%w%.%-]+", i), "bad JSON"); i = i + #w
      if w == "true" then return true elseif w == "false" then return false elseif w == "null" then return nil end; return tonumber(w) end
  end
  return val()
end

local nop = setmetatable({}, { __call = function(self) return self end, __index = function(self) return self end })
hs = setmetatable({
  configdir = os.getenv("TMPDIR") or "/tmp", -- flex favourites: never the real config dir
  task = { new = function() return setmetatable({ setCallback = function(self) return self end }, { __index = function() return function(self) return self end end }) end },
  settings = { get = function(k) return k == "deck.meetBackup" and "0" or nil end },
  json = { encode = enc, decode = dec },
  fs = { attributes = function(p) local f = io.popen("stat -f %m '" .. p .. "' 2>/dev/null"); local m = tonumber(f:read("a")); f:close(); return m end,
    mkdir = function(p) os.execute("mkdir -p '" .. p .. "'"); return true end, dir = function(p) local f = io.popen("ls '" .. p .. "' 2>/dev/null"); local names = {}
    for n in f:lines() do names[#names + 1] = n end; f:close(); local k = 0
    return function() k = k + 1; return names[k] end end },
  timer = { absoluteTime = function() return 0 end, doAfter = function(_, f) f(); return {} end },
}, { __index = function() return nop end })
package.preload["modules.env"] = function() return { get = function(k) return k == "DECK_TOKEN" and "tok" or nil end } end
package.preload["modules.sysmonitor"] = function() return setmetatable({ ramPct = function() return 1 end }, { __index = function() return nop end }) end
package.preload["modules.todoist"] = function() return { tasks = {} } end
local realopen = io.open
io.open = function(p, m) return realopen((p:gsub("^/tmp/deck%-ota", home .. "/deck-ota")), m) end -- a running `just ota` must not leak in

table.insert(package.searchers, 2, function(n) -- Lua 5.5 const loop-var shim (see deck_state_test.lua)
  if n ~= "modules.deck" then return nil end
  local f = assert(realopen(dir .. "/deck.lua")); local src = f:read("a"); f:close()
  src = src:gsub("(%f[%w]for )(%a%w*)( in [^\n]- do)\n", "%1%2__%3 local %2 = %2__\n")
  return assert(load(src, "@deck.lua"))
end)
local realprint = print
print = function() end -- deck.lua's own prints are not replies
local deck = require("modules.deck")
local handle = deck._handle

for line in io.lines(arg[1]) do
  local method, path, inm, token, hex = line:match("^(%u+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(%x*)$")
  local body = hex:gsub("%x%x", function(b) return string.char(tonumber(b, 16)) end)
  local h = { ["X-Deck-Token"] = token ~= "" and token or nil, ["If-None-Match"] = inm ~= "" and inm or nil }
  if method == "WINDOWS" then -- "@5 @6!": tmux's list, ! = no longer Claude
    local rows = {}
    for w in body:gmatch("%S+") do rows[#rows + 1] = w:gsub("!", "") .. "\t0:1\tw\t\t" .. (w:find("!", 1, true) and "zsh" or "claude") .. string.rep("\t", 15) end
    deck._parseSessions(table.concat(rows, "\n") .. "\n")
  end
  local b, code, headers = handle(method, path, h, body)
  realprint(enc({ status = code, headers = headers or {}, body = b or "" }))
end
