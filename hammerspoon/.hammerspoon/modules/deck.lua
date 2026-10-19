-- ESP32 deck: HTTP API for the Waveshare ESP32-C5 touch board (firmware + web simulator: ~/code/esp-deck)
-- GET  /state               → dashboard, tmux sessions, recipes, voice state (JSON)
-- GET  /pane?t=@ID          → last lines of that tmux window
-- POST /send?t=@ID&enter=1  → request body typed into the window (then Enter)
-- POST /key?t=@ID&k=Enter   → one whitelisted tmux key
-- POST /run?r=N             → RECIPES[N] in a new tmux window → {"t":"@ID"}
-- POST /mic?down=1&lang=uk  → hold-to-talk: 1 starts DeckHelper.app, 0 stops it → text in /state.voice
-- POST /mic?clear=1         → forget the last transcript
-- /state.fw = sha256 of a firmware `just ota` is serving on :7778 (hs.httpserver can't stream big binaries)
-- Every request needs "X-Deck-Token: $DECK_TOKEN" (~/.hammerspoon/.env); CORS is open for the simulator.
local M = {}

local env = require("modules.env")
local sysmonitor = require("modules.sysmonitor")
local todoist = require("modules.todoist")

local PORT = 7777
local HOME = os.getenv("HOME")
local TMUX = "/opt/homebrew/bin/tmux"
local STATUSLINE = HOME .. "/.claude/statusline.sh"
local REMINDERS = HOME .. "/.claude/reminders.sh"
local HELPER_APP = HOME .. "/code/esp-deck/helper/DeckHelper.app" -- `just permissions` once
local VOICE_FILE = "/tmp/deck-voice.txt"
local CAL_FILE = "/tmp/deck-cal.json"
local FW_SHA = "/tmp/deck-ota.sha" -- written by `just ota`; the board updates when it differs from its own
local PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" .. HOME .. "/.local/bin"

-- Typed into the open session (row on the session screen)
local SLASH = { "/mine", "/fleet", "/stuck", "/trylog", "/devnow", "/brief" }

-- Recipes tab: { label, shell command } — each runs in a new tmux window the board then opens
local RECIPES = {
  { "fleet",      "just -g fleet plain=1" },
  { "rem",        "just -g rem" },
  { "pr-stale",   "just -g pr-stale" },
  { "git all",    "just -g git-status-all" },
  { "tokens",     "just -g tokens" },
  { "disk hogs",  "just -g disk-hogs" },
}

-- tmux key names the board may send: named keys, F1–F12, or one ASCII char, each optionally C-/M- prefixed
local NAMED = { Enter = 1, Escape = 1, Tab = 1, BTab = 1, BSpace = 1, Space = 1, Up = 1, Down = 1, Left = 1, Right = 1,
  Home = 1, End = 1, PageUp = 1, PageDown = 1, DC = 1 }
local function validKey(k)
  local base = (k or ""):gsub("^C%-", ""):gsub("^M%-", ""):gsub("^C%-", "")
  return NAMED[base] or base:match("^F%d%d?$") or (base:match("^[%g]$") and base ~= ";") -- tmux: ; splits commands
end

-- ── text cleanup: board fonts carry ASCII + Cyrillic + a few symbols, drop the rest ──
local KEEP = { [0x25CB] = true, [0x25CF] = true, [0x26A1] = true, [0x2192] = true, [0x2713] = true, [0xB7] = true }
local function keepCp(cp, mono)
  return (cp >= 0x20 and cp < 0x7F) or (cp >= 0x400 and cp < 0x500) or (cp >= 0x2010 and cp <= 0x2026)
    or KEEP[cp] or (mono and cp >= 0x2500 and cp < 0x25A0)
end

local function clean(s, mono)
  local out = {}
  for _, cp in utf8.codes(s or "") do
    if cp == 10 and mono then out[#out + 1] = "\n"
    elseif keepCp(cp, mono) then out[#out + 1] = utf8.char(cp) end
  end
  local r = table.concat(out)
  if not mono then r = r:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "") end
  return r
end

local function task(cmd, args, cb)
  local t = hs.task.new(cmd, function(_, out) if cb then cb(out or "") end end, args)
  t:setEnvironment({ PATH = PATH, HOME = HOME, LANG = "en_US.UTF-8" })
  t:start()
  return t
end

-- ── slow sources, refreshed in the background ──
local limits, rem = {}, {}
local slowTick = 0

local function refreshSlow()
  slowTick = slowTick + 1
  if slowTick % 5 == 1 then -- calendar: DeckHelper writes CAL_FILE, state() reads it
    task("/usr/bin/open", { "-g", "-n", "-a", HELPER_APP, "--args", "calendar", CAL_FILE })
  end
  -- the statusline itself renders "⏱ 5h ○○… 3% 62k ~0.04x ⚡0.10x @22:50 | 📅 7d …" — reuse it verbatim
  task("/bin/bash", { "-c", "echo '{\"workspace\":{\"current_dir\":\"/tmp\"}}' | bash " .. STATUSLINE }, function(out)
    out = out:gsub("\27%[[%d;]*m", "")
    for line in out:gmatch("[^\n]+") do
      if line:find(" 5h ") then
        local l = {}
        for part in line:gmatch("[^|]+") do
          if part:find(" 5h ") or part:find(" 7d ") then l[#l + 1] = clean(part) end
        end
        limits = l
      end
    end
  end)
  task(REMINDERS, { "list" }, function(out)
    local r = {}
    for line in out:gmatch("[^\n]+") do
      local name, text = line:match("^(%S+)%s+%[active%]%s+(.*)$")
      if name then r[#r + 1] = { n = clean(name), t = clean(text):sub(1, 140) } end
    end
    rem = r
  end)
end

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

local function sessions()
  local out = hs.execute(TMUX .. " list-windows -a -F "
    .. "'#{window_id}\t#{session_name}:#{window_index}\t#{window_name}\t#{@agent_state}\t#{pane_current_command}'") or ""
  local list = {}
  for line in out:gmatch("[^\n]+") do
    local id, idx, name, st, cmd = line:match("^(@%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    if id then
      -- Claude Code shows up as its version ("2.1.301") in pane_current_command
      local claude = st ~= "" or cmd:match("^%d+%.%d+%.%d+$") ~= nil or cmd == "claude"
      list[#list + 1] = { id = id, idx = idx, name = clean(name), state = st, claude = claude }
    end
  end
  return list
end

-- ── voice: DeckHelper.app records until SIGINT, then writes the transcript to VOICE_FILE ──
local voice = { state = "idle", text = "" }
local voiceTimer

local function micDown(lang)
  os.remove(VOICE_FILE)
  voice = { state = "rec", text = "" }
  task("/usr/bin/open", { "-g", "-n", "-a", HELPER_APP, "--args", "listen", lang == "en" and "en-US" or "uk-UA", VOICE_FILE })
end

local function micUp()
  voice.state = "busy"
  task("/usr/bin/pkill", { "-INT", "-x", "DeckHelper" })
  local tries = 0
  if voiceTimer then voiceTimer:stop() end
  voiceTimer = hs.timer.doEvery(0.3, function()
    tries = tries + 1
    local f = io.open(VOICE_FILE)
    if f or tries > 50 then
      voice = { state = "done", text = f and clean(f:read("a")) or "" }
      if f then f:close() end
      voiceTimer:stop()
    end
  end)
end

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("a")
  f:close()
  return data
end

-- Claude windows as numbers for the board's gauges: used %, elapsed % of the window, pace, tokens, reset
local USAGE_CACHE = "/tmp/claude/statusline-usage-cache.json" -- written by statusline.sh
local TOKENS_CACHE = "/tmp/claude/tokens-usage.txt"           -- line 1 = 5h tokens, line 2 = 7d
local function isoEpoch(iso) -- "2026-10-21T18:59:59.7+00:00" (UTC) → epoch
  local y, mo, d, h, mi, sec = (iso or ""):match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return nil end
  local t = { year = y, month = mo, day = d, hour = h, min = mi, sec = sec }
  return os.time(t) + (os.time() - os.time(os.date("!*t")))
end

local function limitGauges()
  local ok, u = pcall(hs.json.decode, readFile(USAGE_CACHE) or "")
  if not ok or not u then return {} end
  local tok = {}
  for line in (readFile(TOKENS_CACHE) or ""):gmatch("[^\n]+") do tok[#tok + 1] = line:gsub("%s", "") end
  local out, now = {}, os.time()
  for i, w in ipairs({ { "5h", u.five_hour, 5 * 3600, "%H:%M" }, { "7d", u.seven_day, 7 * 86400, "%a %H:%M" } }) do
    local reset = w[2] and isoEpoch(w[2].resets_at)
    while reset and reset < now do reset = reset + w[3] end -- stale cache: that window already rolled over
    local used = math.floor(tonumber(w[2] and w[2].utilization) or 0)
    local e = reset and math.max(0, math.min(100, math.floor((1 - (reset - now) / w[3]) * 100))) or 0
    out[i] = { k = w[1], u = used, e = e, pace = e > 1 and math.floor(used / e * 100 + 0.5) / 100 or 0,
               tok = tok[i] or "", reset = reset and os.date(w[4], reset) or "" }
  end
  return out
end

-- next meetings: "● now 10:00 Standup", then "Tue 14:00 Review · in 25 min" for the next one
local function calendarLines()
  local f = io.open(CAL_FILE)
  if not f then return {} end
  local ok, events = pcall(hs.json.decode, f:read("a"))
  f:close()
  local now, lines, next = os.time(), {}, false
  for _, e in ipairs(ok and events or {}) do
    if e["end"] > now then
      local line = e.hm .. "  " .. clean(e.title)
      if e.start <= now then line = "● " .. line
      elseif not next then
        local m = math.floor((e.start - now) / 60)
        line = line .. " · in " .. (m < 60 and (m .. " min") or string.format("%dh %02dm", m // 60, m % 60))
        next = true
      end
      lines[#lines + 1] = line
    end
    if #lines == 5 then break end
  end
  return lines
end

-- ── endpoints ──
local function state()
  local todo = {}
  for i, t in ipairs(todoist.tasks or {}) do
    if i > 6 then break end
    -- ponytail: reuses the Todoist widget's cache; it only refreshes while that widget is shown
    todo[#todo + 1] = clean(t.content:gsub("%[(.-)%]%(.-%)", "%1")):sub(1, 70)
  end
  local recipes = {}
  for i, r in ipairs(RECIPES) do recipes[i] = r[1] end
  return {
    time = os.date("%H:%M"), date = os.date("%a %d %b"),
    limits = limits, lim = limitGauges(), cpu = cpuPct(), ram = sysmonitor.ramPct(),
    rem = rem, todo = todo, cal = calendarLines(), sessions = sessions(),
    recipes = recipes, slash = SLASH, voice = voice, fw = readFile(FW_SHA), board = M.boardVer,
  }
end

-- a TUI ─── rule (box-drawing + spaces only): wider than the board, so it would wrap into several lines
local function isRule(line)
  if not utf8.len(line) then return false end
  for _, cp in utf8.codes(line) do
    if cp ~= 32 and (cp < 0x2500 or cp > 0x257F) then return false end
  end
  return line ~= ""
end

-- ── terminal colors: tmux SGR → LVGL label recolor ("#rrggbb text#", a literal # is "##") ──
local ANSI16 = { [0] = "4d4d4d", "f14c4c", "23d18b", "f5f543", "3b8eea", "d670d6", "29b8db", "cccccc",
  "808080", "ff6e6e", "5af78e", "f4f99d", "6eb5ff", "ff92df", "9aedfe", "ffffff" }
local function xterm256(n)
  if n < 16 then return ANSI16[n] end
  if n >= 232 then local v = 8 + (n - 232) * 10; return string.format("%02x%02x%02x", v, v, v) end
  n = n - 16
  local function c(x) return x == 0 and 0 or 55 + x * 40 end
  return string.format("%02x%02x%02x", c(n // 36), c((n // 6) % 6), c(n % 6))
end

local function sgr(params, fg)
  local p = {}
  for n in (params .. ";"):gmatch("(%d*);") do p[#p + 1] = tonumber(n) or 0 end
  local i = 1
  while i <= #p do
    local v = p[i]
    if v == 0 or v == 39 then fg = nil
    elseif v >= 30 and v <= 37 then fg = ANSI16[v - 30]
    elseif v >= 90 and v <= 97 then fg = ANSI16[v - 82]
    elseif v == 38 and p[i + 1] == 5 then fg = xterm256(p[i + 2] or 0); i = i + 2
    elseif v == 38 and p[i + 1] == 2 then fg = string.format("%02x%02x%02x", p[i + 2] or 0, p[i + 3] or 0, p[i + 4] or 0); i = i + 4
    elseif v == 48 then i = i + (p[i + 1] == 5 and 2 or 4) end -- background: skip its arguments
    i = i + 1
  end
  -- near-black text would vanish on the black terminal
  if fg and tonumber(fg:sub(1, 2), 16) + tonumber(fg:sub(3, 4), 16) + tonumber(fg:sub(5, 6), 16) < 120 then fg = nil end
  return fg
end

local function recolor(line, fg)
  local out, pos = {}, 1
  local function emit(text)
    text = clean(text, true)
    if text == "" then return end
    if fg then out[#out + 1] = "#" .. fg .. " " .. text:gsub("#", "####" .. fg .. " ") .. "#"
    else out[#out + 1] = (text:gsub("#", "##")) end
  end
  while true do
    local s, e, params = line:find("\27%[([%d;]*)m", pos)
    if not s then break end
    emit(line:sub(pos, s - 1))
    fg = sgr(params, fg)
    pos = e + 1
  end
  emit(line:sub(pos))
  return table.concat(out), fg
end

local function pane(id, colors)
  local out = hs.execute(TMUX .. " capture-pane -p -e -J -S -120 -t '" .. id .. "'") or ""
  out = out:gsub("\27%]8;[^\27]*\27\\", "") -- OSC 8 hyperlinks
  local lines, blank, fg = {}, false, nil
  for line in (out .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("%s+$", "")
    local plain = line:gsub("\27%[[%d;]*m", "")
    if isRule(plain) and utf8.len(plain) > 64 then line = plain:sub(1, utf8.offset(plain, 65) - 1) end
    local empty = plain:match("^%s*$") ~= nil
    if not empty or not blank then
      if colors then
        local colored
        colored, fg = recolor(line, fg)
        lines[#lines + 1] = colored
      else
        lines[#lines + 1] = clean(plain:gsub("   +", "  "), true)
      end
    end
    blank = empty
  end
  while #lines > 100 do table.remove(lines, 1) end
  return { t = id, text = table.concat(lines, "\n") }
end

M.pane = pane -- debug: hs -c to inspect one window

local function currentSession()
  local s = hs.execute(TMUX .. " list-clients -F '#{client_session}' | head -1"):gsub("%s+", "")
  if s == "" then s = hs.execute(TMUX .. " list-sessions -F '#{session_name}' | head -1"):gsub("%s+", "") end
  return s
end

local function runRecipe(r)
  local id = hs.execute(TMUX .. " new-window -d -P -F '#{window_id}' -t '" .. currentSession() .. ":' -n 'deck:"
    .. r[1] .. "' \"" .. r[2] .. "; echo; read -sk '?done, any key closes'\" "):gsub("%s+", "")
  return id
end

local function query(qs)
  local p = {}
  for k, v in (qs or ""):gmatch("([^&=]+)=([^&]*)") do
    p[k] = v:gsub("+", " "):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  end
  return p
end

local CORS = {
  ["Access-Control-Allow-Origin"] = "*",
  ["Access-Control-Allow-Headers"] = "X-Deck-Token",
  ["Access-Control-Allow-Methods"] = "GET, POST",
}
local function reply(body, code, json)
  local h = {}
  for k, v in pairs(CORS) do h[k] = v end
  if json then h["Content-Type"] = "application/json; charset=utf-8" end
  return json and hs.json.encode(body) or body, code, h
end

local function handle(method, path, headers, body)
  if method == "OPTIONS" then return reply("", 204) end
  local token = env.get("DECK_TOKEN")
  if not token or headers["X-Deck-Token"] ~= token then return reply("forbidden", 403) end

  if headers["X-Deck-Ver"] then M.boardVer = headers["X-Deck-Ver"] end
  local route, qs = path:match("^([^?]*)%??(.*)$")
  local p = query(qs)
  local id = p.t and p.t:match("^@%d+$")

  if method == "GET" and route == "/state" then return reply(state(), 200, true) end
  if method == "GET" and route == "/pane" and id then return reply(pane(id, p.c == "1"), 200, true) end
  if method == "POST" and route == "/send" and id then
    task(TMUX, { "send-keys", "-t", id, "-l", "--", body or "" }, function()
      if p.enter == "1" then task(TMUX, { "send-keys", "-t", id, "Enter" }) end
    end)
    return reply("ok", 200)
  end
  if method == "POST" and route == "/key" and id and validKey(p.k) then
    task(TMUX, { "send-keys", "-t", id, p.k })
    return reply("ok", 200)
  end
  local r = RECIPES[tonumber(p.r or "")]
  if method == "POST" and route == "/run" and r then return reply({ t = runRecipe(r) }, 200, true) end
  if method == "POST" and route == "/mic" then
    if p.clear == "1" then voice = { state = "idle", text = "" }
    elseif p.down == "1" then micDown(p.lang)
    else micUp() end
    return reply("ok", 200)
  end
  return reply("not found", 404)
end

function M.start()
  refreshSlow()
  M.slowTimer = hs.timer.doEvery(20, refreshSlow)
  M.server = hs.httpserver.new(false, false):setPort(PORT):setCallback(handle):start()
end

return M
