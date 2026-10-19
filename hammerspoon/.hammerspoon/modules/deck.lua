-- ESP32 deck: HTTP endpoint for the Waveshare ESP32-C5 touch board (firmware: ~/code/esp-deck)
-- GET  /state     → JSON: clock, dashboard tiles, todo, button labels
-- POST /press?i=N → runs BUTTONS[N]
-- Every request must carry "X-Deck-Token: $DECK_TOKEN" (~/.hammerspoon/.env).
local M = {}

local env = require("modules.env")
local sysmonitor = require("modules.sysmonitor")
local todoist = require("modules.todoist")

local PORT = 7777
local USAGE_FILE = "/tmp/claude/statusline-usage-cache.json" -- written by claude statusline.sh

local function key(mods, k) return function() hs.eventtap.keyStroke(mods, k, 0) end end
local function media(k) return function()
  hs.eventtap.event.newSystemKeyEvent(k, true):post()
  hs.eventtap.event.newSystemKeyEvent(k, false):post()
end end

-- Edit freely: { label, action }. The board shows up to 12, in order (3 columns × 4 rows).
local BUTTONS = {
  { "Ghostty",  function() hs.application.launchOrFocus("Ghostty") end },
  { "Chrome",   function() hs.application.launchOrFocus("Google Chrome") end },
  { "Pal",      function() require("modules.pal").toggle() end },
  { "Prev",     media("PREVIOUS") },
  { "Play",     media("PLAY") },
  { "Next",     media("NEXT") },
  { "Vol -",    media("SOUND_DOWN") },
  { "Mute",     media("MUTE") },
  { "Vol +",    media("SOUND_UP") },
  { "Shot",     key({ "cmd", "shift" }, "4") },
  { "Todoist",  function() todoist.toggle() end },
  { "Lock",     function() hs.caffeinate.lockScreen() end },
}

-- CPU % from tick deltas between /state calls (cpuUsage() blocks for a second)
local lastTicks
local function cpuPct()
  local t = hs.host.cpuUsageTicks().overall
  local pct = 0
  if lastTicks then
    local active, idle = t.active - lastTicks.active, t.idle - lastTicks.idle
    if active + idle > 0 then pct = math.floor(active / (active + idle) * 100) end
  end
  lastTicks = t
  return pct
end

-- "2026-10-21T18:59:59.7+00:00" → local "Wed 21:59"
local function localReset(iso)
  local y, mo, d, h, mi = (iso or ""):match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
  if not y then return "" end
  local utc = os.time({ year = y, month = mo, day = d, hour = h, min = mi })
  local offset = os.time() - os.time(os.date("!*t"))
  return os.date("%a %H:%M", utc + offset)
end

local function claudeTiles()
  local f = io.open(USAGE_FILE)
  if not f then return {} end
  local ok, u = pcall(hs.json.decode, f:read("a"))
  f:close()
  if not ok or not u or not u.five_hour then return {} end
  local tiles = {}
  for _, w in ipairs({ { "Claude 5h", u.five_hour }, { "Claude 7d", u.seven_day } }) do
    local p = math.floor(tonumber(w[2] and w[2].utilization) or 0)
    tiles[#tiles + 1] = { k = w[1], v = p .. "%", p = p, s = localReset(w[2] and w[2].resets_at) }
  end
  return tiles
end

local function state()
  local tiles = claudeTiles()
  local cpu, ram = cpuPct(), sysmonitor.ramPct()
  tiles[#tiles + 1] = { k = "CPU", v = cpu .. "%", p = cpu, s = "" }
  tiles[#tiles + 1] = { k = "RAM", v = ram .. "%", p = ram, s = "" }

  -- ponytail: reuses the Todoist widget's cache; it only refreshes while that widget is shown
  local todo = {}
  for i, t in ipairs(todoist.tasks or {}) do
    if i > 6 then break end
    -- markdown link → its text; board font is ASCII-only (emoji/dashes would render as boxes)
    local s = t.content:gsub("%[(.-)%]%(.-%)", "%1"):gsub("[^\32-\126]", ""):gsub("%s+", " ")
    todo[#todo + 1] = s:sub(1, 44)
  end

  local labels = {}
  for i, b in ipairs(BUTTONS) do labels[i] = b[1] end

  return { time = os.date("%H:%M"), date = os.date("%a %d %b"), tiles = tiles, todo = todo, buttons = labels }
end

local function handle(method, path, headers, _)
  local token = env.get("DECK_TOKEN")
  if not token or headers["X-Deck-Token"] ~= token then return "forbidden", 403, {} end

  if method == "GET" and path == "/state" then
    return hs.json.encode(state()), 200, { ["Content-Type"] = "application/json" }
  end

  local i = tonumber(path:match("^/press%?i=(%d+)$"))
  if method == "POST" and i and BUTTONS[i] then
    -- run after replying so a slow action never stalls the board
    hs.timer.doAfter(0, BUTTONS[i][2])
    return "ok", 200, {}
  end
  return "not found", 404, {}
end

function M.start()
  M.server = hs.httpserver.new(false, false):setPort(PORT):setCallback(handle):start()
end

return M
