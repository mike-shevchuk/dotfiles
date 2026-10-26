-- ESP32 deck: HTTP API for the Waveshare ESP32-C5 touch board (firmware + web simulator: ~/code/esp-deck)
-- GET  /state               → dashboard, tmux sessions, recipes, voice state (JSON)
-- GET  /pane?t=@ID[&m=clean] → last lines of that tmux window (clean: no Claude chrome, turns marked \1u / \1a)
-- POST /send?t=@ID&enter=1  → request body typed into the window (then Enter)
-- POST /key?t=@ID&k=Enter   → one whitelisted tmux key (Escape to a Claude window also marks it done)
-- POST /run?r=N             → RECIPES[N] in a new tmux window → {"t":"@ID"}
-- POST /mic?down=1&lang=uk  → hold-to-talk: 1 starts DeckHelper.app, 0 stops it → text in /state.voice
-- POST /mic?clear=1         → forget the last transcript
-- POST /log                 → board log lines + timings, appended to ~/Library/Logs/esp-deck.log (`just logs`)
-- POST /hub, /projlist      → recent hub pages, projctl projects (lazy: only when that tab opens)
-- POST /page?i=N&w=COLS     → hub page N as plain text cut to COLS   ·  POST /open?i=N → open it on the Mac
-- POST /fleet?w=COLS        → compact `lead.py blockers --json` (who waits for Mike first; plain python, no Claude tokens)
-- POST /proj?n=NAME&a=up|down|restart → projctl
-- POST /chat?t=@ID&n=N      → that window's Claude conversation, oldest first: {"msgs":[{"r":"u|a|t","x":"…"}]}
-- POST /net?r=day|month|year → minutes on the home LAN per device, top 15: {"r":"day","top":[{name,mac,min}]}
-- POST /spawn?p=NAME        → new window in that project's session running `claude "<body>"` → {"t":"@ID"}
-- POST /deck                → Stream Deck pages from ~/.hammerspoon/deck.json (labels/icons/colors only)
-- POST /act?d=PAGE&i=N  ·  /act?r=N&app=APP → run that deck / ring button's action (actions never leave the Mac)
-- POST /panel[?set=vol|bright|dark|awake|mic|sleep&v=N] → control-panel state / toggles
-- POST /mac                 → now playing (Spotify / Music) + files selected in Finder + last conversion
-- POST /media?k=play|next|prev|volup|voldown → media keys (also drive YouTube in the browser)
-- POST /convert?f=jpg|png|heic|gif|pdf|mp4|mp3|m4a → convert the Finder selection, results land next to the originals
-- /state.fw = sha256 of a firmware `just ota` is serving on :7778 (hs.httpserver can't stream big binaries)
-- Every request needs "X-Deck-Token: $DECK_TOKEN" (~/.hammerspoon/.env); CORS is open for the simulator.
local M = {}

local env = require("modules.env")
local sysmonitor = require("modules.sysmonitor")
local todoist = require("modules.todoist")
local paneclean = require("modules.paneclean")

local PORT = 7777
local HOME = os.getenv("HOME")
local TMUX = "/opt/homebrew/bin/tmux"
local AGENT_STATE = HOME .. "/dotfiles/tmux/scripts/agent-state.sh" -- Claude hook; `chat` reads a session JSONL
local STATUSLINE = HOME .. "/.claude/statusline.sh"
local REMINDERS = HOME .. "/.claude/reminders.sh"
local HELPER_APP = HOME .. "/code/esp-deck/helper/DeckHelper.app" -- `just permissions` once
local NET_DIR = HOME .. "/Library/Application Support/esp-deck" -- net-day|month|year.json (top 15), written by launchd: `just netscan` in esp-deck
local VOICE_FILE = "/tmp/deck-voice.txt"
local CAL_FILE = "/tmp/deck-cal.json"
local FW_SHA = "/tmp/deck-ota.sha" -- written by `just ota`; the board updates when it differs from its own
local PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" .. HOME .. "/.local/bin"

-- Typed into the open session (row on the session screen)
local SLASH = { "/mine", "/fleet", "/stuck", "/trylog", "/devnow", "/brief" }

-- Recipes tab: { label, shell command } — each runs in a new tmux window the board then opens
local RECIPES = {
  { "fleet",      "just -g fleet '' 1" }, -- positional: w (empty = pane width), plain
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
local function cut(s, n) local o = utf8.offset(s, n + 1); return o and s:sub(1, o - 1) or s end -- never mid-UTF-8

local function task(cmd, args, cb)
  local t = hs.task.new(cmd, function(_, out) if cb then cb(out or "") end end, args)
  t:setEnvironment({ PATH = PATH, HOME = HOME, LANG = "en_US.UTF-8" })
  t:start()
  return t
end

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("a")
  f:close()
  return data
end

-- ── slow sources, refreshed in the background ──
local limits, rem = {}, {}
local slowTick = 0
local HUB_DIR = HOME .. "/zettelkasten/claude_code"
local HUB_URL = "http://localhost:8890/"
local PROJCTL = HOME .. "/code/projctl"
local hub, projects, projWhere = {}, {}, {} -- projWhere[name] = { dir, session } for /spawn

local function refreshHub()
  -- newest 30 pages (no .bak copies), title from <title>
  task("/bin/sh", { "-c", "cd '" .. HUB_DIR .. "' && find . -name '*.html' ! -name '*.bak*' ! -name index.html "
    .. "-mtime -90 -exec stat -f '%m %N' {} + | sort -rn | head -30" }, function(out)
    local list = {}
    for mtime, path in out:gmatch("(%d+) %./([^\n]+)") do
      local f = io.open(HUB_DIR .. "/" .. path)
      local head = f and f:read(4096) or ""
      if f then f:close() end
      local title = (head:match("<title>(.-)</title>") or path:match("([^/]+)%.html$"))
        :gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&#39;", "'")
      list[#list + 1] = { path = path, url = HUB_URL .. path, t = clean(title):sub(1, 90), d = os.date("%d.%m", tonumber(mtime)),
                          dir = clean(path:match("^([^/]+)") or "") }
    end
    hub = list
  end)
end

local function refreshProjects()
  -- registry.conf: name|dir|session|port|extra|autostart → running = its tmux session exists
  -- (one async list-sessions: a sync has-session per project held up every request behind it)
  local list, where = {}, {}
  for line in (readFile(PROJCTL .. "/registry.conf") or ""):gmatch("[^\n]+") do
    local name, dir, session, port, _, auto = line:match("^([^#|][^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|?(%d?)")
    if name then
      list[#list + 1] = { n = name, session = session, port = port, auto = auto == "1" }
      where[name] = { dir = dir:gsub("^~", HOME), session = session }
    end
  end
  projWhere = where
  task(TMUX, { "list-sessions", "-F", "#{session_name}" }, function(out)
    local up = {}
    for n in out:gmatch("[^\n]+") do up[n] = true end
    for _, pr in ipairs(list) do pr.on = up[pr.session] == true; pr.session = nil end
    projects = list
  end)
end

local function refreshSlow()
  slowTick = slowTick + 1

  if slowTick % 2 == 1 then -- calendar every ~2 min: DeckHelper writes CAL_FILE, state() reads it
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

-- tmux windows, cached: refreshed every 3 s by an async task so a /state request never forks tmux
local sessionCache, askCache = {}, {}
local tailCache, fetchTail = {}, nil -- id → the terminal above Claude's dialog, for an ask with no ctx (fetchTail is defined below isRule)
-- the hook's JSON array of strings → cleaned, utf8-safe, each ≤ n chars
local function strList(json, n)
  if json:sub(1, 1) ~= "[" then return {} end -- "" (no ask): hs.json.decode logs an ERROR even inside pcall
  local out, ok, arr = {}, pcall(hs.json.decode, json)
  for _, l in ipairs(ok and type(arr) == "table" and arr or {}) do
    local cok, c = pcall(clean, tostring(l))
    out[#out + 1] = cut(cok and c or "", n)
  end
  return out
end
local function safeClean(s, n) -- utf8.codes throws on invalid UTF-8; one bad window must not drop the list
  local ok, c = pcall(clean, s)
  return cut(ok and c or "", n)
end
-- list-windows fields; @agent_ask* come from agent-state.sh, none of them holds a \t
local FIELDS = { "window_id", "session_name}:#{window_index", "window_name", "@agent_state", "pane_current_command",
  "@agent_ask_kind", "@agent_ask_at", "@agent_ask_opts", "@agent_ask_multi", "@agent_ask_n", "@agent_ask_descs",
  "@agent_ask_head", "@agent_ask_ctx", "@agent_transcript", "@agent_at", "@agent_ctx_max", "pane_current_path", "@agent_ask" }
-- transcript path → { mtime, doing, sum, tok, model } from `agent-state.sh info`, re-read only when the file changed
local infoCache = {}
local function refreshInfo(list)
  local keep, stale = {}, {}
  for _, w in ipairs(list) do
    if w.tr ~= "" and not keep[w.tr] then
      local e = infoCache[w.tr] or {}
      keep[w.tr] = e
      local m = hs.fs.attributes(w.tr, "modification") -- a stat, no fork
      if m and m ~= e.mtime then e.mtime = m; stale[#stale + 1] = w.tr end
    end
  end
  infoCache = keep
  if #stale == 0 then return end
  task(AGENT_STATE, { "info", table.unpack(stale) }, function(out)
    for line in out:gmatch("[^\n]+") do
      local ok, d = pcall(hs.json.decode, line)
      local e = ok and type(d) == "table" and infoCache[d.f]
      if e then
        e.doing, e.sum, e.tok, e.model = safeClean(d.doing, 60), safeClean(d.sum, 140), tonumber(d.tok) or 0, d.model or ""
      end
    end
  end)
end
local ST_RANK = { waiting = 1, done = 2, working = 3, idle = 4 }
local IDLE_TEXT = "Claude is waiting for your input" -- idle_prompt's default: resting at the prompt, not a question
-- which hook-kept asks reach the board: an open dialog; an "other" Notification ≤ 1 h; an idle one with real text ≤ 10 min
local function isAsk(st, kind, text, age)
  if kind == "permission" or kind == "choice" then return st == "waiting" end
  if kind == "idle" then return text ~= IDLE_TEXT and text ~= "" and age <= 600 end
  return kind == "other" and age <= 3600
end
local function parseSessions(out)
  local list, asks, seen = {}, {}, {}
  for line in out:gmatch("[^\n]+") do
    local f = {}
    for x in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = x end
    local id, idx, name, st, cmd, kind, at, opts, multi, nq, descs, head, ctx, tr, aat, cmax, cwd, ask =
      table.unpack(f, 1, #FIELDS)
    -- a window linked into several sessions (W42 / w42) comes once per session: keep its first, like the asks
    if id and id:match("^@%d+$") and ask and not seen[id] then
      seen[id] = true
      -- Claude Code shows up as its version ("2.1.301") in pane_current_command
      local claude = st ~= "" or cmd:match("^%d+%.%d+%.%d+$") ~= nil or cmd == "claude"
      name = clean(name)
      -- tmux's automatic-rename calls a Claude window by its version: the project folder says more
      if name == "" or name:match("^%d+%.%d+%.%d+$") or name:lower() == "claude" then
        name = clean(cwd:match("([^/]+)/*$") or name)
      end
      list[#list + 1] = { id = id, idx = idx, name = name, state = st, kind = kind, claude = claude, tr = tr,
                          at = tonumber(aat), cmax = tonumber(cmax), n = #list }
      local askAt = tonumber(at) or os.time()
      if isAsk(st, kind, ask, os.time() - askAt) then
        asks[#asks + 1] = { id = id, idx = idx, name = name, kind = kind ~= "" and kind or "other",
                            text = safeClean(ask, 160), at = askAt,
                            opts = strList(opts, 40), multi = multi == "true", nq = tonumber(nq) or 1,
                            descs = strList(descs, 80), head = safeClean(head, 40), ctx = safeClean(ctx, 600) }
      end
    end
  end
  local rank = { permission = 1, choice = 2 }
  table.sort(asks, function(a, b) -- permission, then choice, then the rest; oldest first within each
    local ra, rb = rank[a.kind] or 3, rank[b.kind] or 3
    if ra ~= rb then return ra < rb end
    return a.at < b.at
  end)
  -- st: waiting only with an open dialog; at the prompt = done for 30 min after the last event, then idle
  refreshInfo(list)
  local now = os.time()
  for _, w in ipairs(list) do
    if w.claude then
      w.at = w.at or (infoCache[w.tr] or {}).mtime -- @agent_at comes with the next hook event; until then the transcript's
      if w.state == "working" then w.st = "working"
      elseif w.state == "waiting" and (w.kind == "permission" or w.kind == "choice") then w.st = "waiting"
      else w.st = w.at and now - w.at <= 1800 and "done" or "idle" end
    end
  end
  -- Claude agents waiting → done → working → idle, the latest event first; other windows after them in tmux order
  local function rank(w) return w.claude and ST_RANK[w.st] or 5 end
  table.sort(list, function(a, b)
    local ra, rb = rank(a), rank(b)
    if ra ~= rb then return ra < rb end
    if ra < 5 and (a.at or 0) ~= (b.at or 0) then return (a.at or 0) > (b.at or 0) end
    return a.n < b.n
  end)
  sessionCache, askCache = list, { table.unpack(asks, 1, 5) }
  local tails = {}
  for _, a in ipairs(askCache) do
    if a.ctx == "" then tails[a.id] = tailCache[a.id] or ""; fetchTail(a.id) end
  end
  tailCache = tails
end
local function refreshSessions()
  task(TMUX, { "list-windows", "-a", "-F", "#{" .. table.concat(FIELDS, "}\t#{") .. "}" }, parseSessions)
end
local function asks()
  local now, r = os.time(), {}
  for i, a in ipairs(askCache) do
    r[i] = { id = a.id, idx = a.idx, name = a.name, kind = a.kind, text = a.text, age = math.max(0, now - a.at),
             opts = a.opts, multi = a.multi, nq = a.nq, descs = a.descs, head = a.head, ctx = a.ctx,
             tail = tailCache[a.id] }
  end
  return r
end
local function sessions()
  local now, r = os.time(), {}
  for i, w in ipairs(sessionCache) do
    local s = { id = w.id, idx = w.idx, name = w.name, state = w.state, claude = w.claude }
    if w.claude then
      local e = infoCache[w.tr] or {}
      s.st = w.st
      s.age = w.at and math.max(0, now - w.at) or nil
      s.doing = e.doing
      if e.tok and e.tok > 0 then
        local max = w.cmax or ((e.model:find("[1m]", 1, true) or e.tok > 200000) and 1000000 or 200000)
        s.ctx = math.floor(e.tok * 100 / max + 0.5)
      end
      if s.st == "done" then s.sum = e.sum end
    end
    r[i] = s
  end
  return r
end

-- ── voice: DeckHelper.app records until SIGINT, then writes the transcript to VOICE_FILE ──
-- (while recording it keeps the partial transcript in VOICE_FILE .. ".partial" → /state.voice.text)
local voice = { state = "idle", text = "" }
local voiceTimer

local function micDown(lang)
  os.remove(VOICE_FILE)
  os.remove(VOICE_FILE .. ".partial")
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

-- a TUI ─── rule (box-drawing + spaces only): wider than the board, so it would wrap into several lines
local isRule = paneclean.isRule

-- the screen above Claude's dialog / input box (its first ─ or ╌ rule in the bottom 30 lines): ≤ 12 lines, ≤ 600 chars
fetchTail = function(id)
  task(TMUX, { "capture-pane", "-p", "-J", "-t", id }, function(out)
    local lines = {}
    for l in (out .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = (l:gsub("%s+$", "")) end
    local stop = #lines + 1
    for i = math.max(1, #lines - 30), #lines do
      if isRule(lines[i]) then stop = i; break end
    end
    local keep = {}
    for i = 1, stop - 1 do
      local ok, c = pcall(clean, lines[i])
      if ok and c ~= "" then keep[#keep + 1] = c end
    end
    local text = table.concat(keep, "\n", math.max(1, #keep - 11))
    if tailCache[id] then tailCache[id] = (text:sub(-600):gsub("^[\128-\191]+", "")) end -- bytes; never mid-UTF-8
  end)
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

-- one tmux line → { {fg, text}, … } (fg nil = default colour), and the colour carried into the next line
local function segments(line, fg, colors)
  local segs, pos = {}, 1
  local function add(t)
    t = clean(t, true)
    if t ~= "" then segs[#segs + 1] = { colors and fg or nil, t } end
  end
  while true do
    local s, e, params = line:find("\27%[([%d;]*)m", pos)
    if not s then break end
    add(line:sub(pos, s - 1))
    fg = sgr(params, fg)
    pos = e + 1
  end
  add(line:sub(pos))
  return segs, fg
end

-- LVGL recolor ("#rrggbb text#", literal # = "##"); the board's label always has recolor on, so escape even plain text
local function span(fg, text)
  if fg then return "#" .. fg .. " " .. text:gsub("#", "####" .. fg .. " ") .. "#" end
  return (text:gsub("#", "##"))
end

-- cut into ≤ width-column lines, every line closing its own colour spans: LVGL resets recolor at each
-- line break, so a span it wrapped itself would spill "#949494"-style garbage onto the screen
local function wrap(segs, width, out)
  local parts, n = {}, 0
  local function flush() out[#out + 1] = table.concat(parts); parts, n = {}, 0 end
  for _, sg in ipairs(segs) do
    local text = sg[2]
    while text ~= "" do
      local len = utf8.len(text)
      if len <= width - n then
        parts[#parts + 1] = span(sg[1], text)
        n = n + len
        text = ""
      else
        local cut = utf8.offset(text, width - n + 1)
        if cut > 1 then parts[#parts + 1] = span(sg[1], text:sub(1, cut - 1)) end
        text = text:sub(cut)
        flush()
      end
    end
  end
  flush()
end

-- a capture-pane → the board's text; clean = paneclean's view, its first line of a turn starts "\1u" / "\1a"
local function render(out, colors, width, clean)
  out = out:gsub("\27%]8;[^\27]*\27\\", "") -- OSC 8 hyperlinks
  local items = {}
  for line in (out .. "\n"):gmatch("(.-)\n") do items[#items + 1] = { s = (line:gsub("%s+$", "")) } end
  if clean then
    local src = {}
    for i, it in ipairs(items) do src[i] = it.s end
    items = paneclean.clean(src)
  end
  local lines, blank, fg = {}, false, nil
  for _, it in ipairs(items) do
    local line, first = it.s, #lines + 1
    local plain = line:gsub("\27%[[%d;]*m", "")
    local empty = plain:match("^%s*$") ~= nil
    if isRule(plain) then -- a ─── rule: one screen wide, no colour
      line = utf8.len(plain) > width and plain:sub(1, utf8.offset(plain, width + 1) - 1) or plain
    end
    if not empty or not blank then
      local segs
      segs, fg = segments(line, fg, colors)
      if #segs == 0 then lines[#lines + 1] = "" else wrap(segs, width, lines) end
      if it.m and lines[first] then lines[first] = "\1" .. it.m .. lines[first] end
    end
    blank = empty
  end
  while #lines > 60 do table.remove(lines, 1) end -- the board re-renders all of it every second: keep it light
  return table.concat(lines, "\n")
end

-- /pane answers from a cache at once; the capture runs async (a sync hs.execute stalled all of HS for up to 1 s),
-- at most every 0.4 s per window+view, and a view nobody asked for in 60 s is dropped
local paneCache = {}
local function pane(id, colors, width, clean)
  width = width and width >= 20 and width or 1000 -- old firmware sends no w: no wrapping here
  local now, key = hs.timer.secondsSinceEpoch(), table.concat({ id, tostring(colors), width, tostring(clean) }, "|")
  for k, e in pairs(paneCache) do if now - e.asked > 60 then paneCache[k] = nil end end
  local e = paneCache[key] or { fetched = 0 }
  paneCache[key], e.asked = e, now
  if not e.busy and now - e.fetched >= 0.4 then
    e.busy, e.fetched = true, now
    task(TMUX, { "capture-pane", "-p", "-e", "-J", "-S", "-120", "-t", id }, function(out)
      local ok, text = pcall(render, out, colors, width, clean)
      if ok then e.data = { t = id, text = text } end
      e.busy = false
    end)
  end
  return e.data or { t = id, text = "", wait = true }
end

-- ── Mac quick actions (Opie-style): now playing + convert what's selected in Finder ──
local NP = {
  Spotify = [[if application "Spotify" is running then tell application "Spotify" to return (player state as string) & "|" & name of current track & "|" & artist of current track & "|" & (player position as integer) & "|" & ((duration of current track) div 1000)]],
  Music = [[if application "Music" is running then tell application "Music" to return (player state as string) & "|" & name of current track & "|" & artist of current track & "|" & (player position as integer) & "|" & ((duration of current track) as integer)]],
}
-- AppleScript runs in /usr/bin/osascript tasks (never on Hammerspoon's thread: an Automation prompt or a busy
-- app would stall the whole deck server); /mac answers from these caches and kicks off a refresh
local macNP, macFiles = nil, {}
local function osa(script, cb) task("/usr/bin/osascript", { "-e", script }, cb) end

local function refreshMac()
  local found = {}
  for _, app in ipairs({ "Spotify", "Music" }) do
    osa(NP[app], function(out)
      local st, title, artist, pos, dur = out:gsub("%s+$", ""):match("^(%w+)|(.-)|(.-)|(%d+)|(%d+)$")
      found[app] = st and { app = app, playing = st == "playing", t = clean(title), a = clean(artist),
                            pos = tonumber(pos), dur = tonumber(dur) } or false
      if found.Spotify ~= nil and found.Music ~= nil then
        local sp, mu = found.Spotify, found.Music
        macNP = (sp and sp.playing and sp) or (mu and mu.playing and mu) or sp or mu or nil
      end
    end)
  end
  osa([[tell application "Finder" to set s to selection as alias list
set out to ""
repeat with f in s
  set out to out & POSIX path of f & linefeed
end repeat
return out]], function(out)
    local files = {}
    for path in out:gmatch("[^\n]+") do
      if not path:match("/$") then files[#files + 1] = path end -- folders: no
    end
    macFiles = files
  end)
end

local IMAGE = { jpg = 1, jpeg = 1, png = 1, heic = 1, tiff = 1, tif = 1, gif = 1, bmp = 1, webp = 1 }
local MEDIA = { mov = 1, mp4 = 1, m4v = 1, avi = 1, mkv = 1, webm = 1, mp3 = 1, wav = 1, m4a = 1, aac = 1, flac = 1 }
local SIPS_FMT = { jpg = "jpeg", png = "png", heic = "heic", gif = "gif", pdf = "pdf", tiff = "tiff" }
local FFMPEG_FMT = { mp4 = 1, mp3 = 1, m4a = 1, gif = 1, wav = 1 }
local conversion = ""

local function freeName(base, ext)
  local out, n = base .. "." .. ext, 1
  while hs.fs.attributes(out) do out = base .. "-" .. n .. "." .. ext; n = n + 1 end
  return out
end

local function convert(files, fmt)
  local started, names = 0, {}
  for _, src in ipairs(files) do
    local base, ext = src:match("^(.*)%.([^./]+)$")
    ext = ext and ext:lower()
    local cmd, args
    if ext and IMAGE[ext] and SIPS_FMT[fmt] then
      local dst = freeName(base, fmt)
      cmd, args = "/usr/bin/sips", { "-s", "format", SIPS_FMT[fmt], src, "--out", dst }
      names[#names + 1] = dst:match("[^/]+$")
    elseif ext and (MEDIA[ext] or ext == "gif") and FFMPEG_FMT[fmt] then
      local dst = freeName(base, fmt)
      args = { "-y", "-loglevel", "error", "-i", src }
      if fmt == "gif" then for _, a in ipairs({ "-vf", "fps=12,scale=480:-1" }) do args[#args + 1] = a end end
      if fmt == "mp3" or fmt == "m4a" or fmt == "wav" then args[#args + 1] = "-vn" end
      args[#args + 1] = dst
      cmd = "/opt/homebrew/bin/ffmpeg"
      names[#names + 1] = dst:match("[^/]+$")
    end
    if cmd then
      started = started + 1
      task(cmd, args, function()
        started = started - 1
        if started == 0 then conversion = "✓ " .. table.concat(names, ", ") end
      end)
    end
  end
  conversion = started > 0 and ("converting " .. started .. " → " .. fmt:upper() .. "…") or ("nothing to convert to " .. fmt:upper())
end

-- hub page → plain text: drop head/style/script, keep paragraphs / headings / list items as lines
local ENT = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ", mdash = "—", ndash = "–", hellip = "…" }
local function htmlText(html, lang)
  -- bilingual hub pages: <x data-en>…</x><x data-ua>…</x> → keep one language; the ☰ menu lives in <details>
  local drop = lang == "en" and "ua" or "en"
  html = html:gsub("<(%w+)[^>]-data%-" .. drop .. "[^>]*>.-</%1>", ""):gsub("<details.-</details>", "")
  html = html:gsub("<head.-</head>", ""):gsub("<style.-</style>", ""):gsub("<script.-</script>", "")
  html = html:gsub("<nav.-</nav>", ""):gsub("<button.-</button>", ""):gsub("<select.-</select>", ""):gsub("<label.-</label>", "")
  html = html:gsub("<br%s*/?>", "\n"):gsub("</p>", "\n\n"):gsub("<h%d[^>]*>", "\n\n"):gsub("</h%d>", "\n")
  html = html:gsub("<li[^>]*>", "\n• "):gsub("</tr>", "\n"):gsub("</t[dh]>", "  "):gsub("</div>", "\n"):gsub("</pre>", "\n")
  html = html:gsub("<[^>]+>", "")
  html = html:gsub("&(%a+);", function(e) return ENT[e] or "" end)
  html = html:gsub("&#(%d+);", function(n) return utf8.char(tonumber(n)) end)
  local lines, blank = {}, true
  for line in (html .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if line ~= "" or not blank then lines[#lines + 1] = line end
    blank = line == ""
  end
  return table.concat(lines, "\n")
end

-- plain multi-line text → board lines cut to width (no colours; # escaped for the recolor label)
local function plainLines(text, width, fg)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    line = clean(line, true)
    if line == "" then out[#out + 1] = "" end
    -- break at the last space that fits (prose); wrap() still hard-cuts anything longer than a line
    while line ~= "" do
      local len = utf8.len(line)
      if len <= width then
        wrap({ { fg, line } }, width, out)
        break
      end
      local cut = utf8.offset(line, width + 1)
      local sp = line:sub(1, cut - 1):match(".*() ")
      if not sp or sp < cut / 2 then sp = cut end
      wrap({ { fg, line:sub(1, sp - 1) } }, width, out)
      line = line:sub(sp):gsub("^ ", "")
    end
    if #out > 1500 then break end
  end
  return table.concat(out, "\n")
end

-- compact fleet for the board (`lead.py blockers --json`): windows that wait for Mike first, ≤3 asks each
-- lead.py runs async: the board gets the last result (its long-press refresh brings the fresh one)
local fleetRaw
local function refreshFleet()
  task("/bin/sh", { "-c", "PATH=$PATH:$HOME/.pyenv/shims python3 $HOME/.claude/scripts/lead.py blockers --json 2>/dev/null" },
       function(out) fleetRaw = out end)
end
local function fleetText(width)
  local raw = fleetRaw
  refreshFleet()
  if not raw then return "…" end
  local ok, d = pcall(hs.json.decode, raw or "")
  if not ok or not d then return "lead.py blockers failed:\n" .. plainLines(raw or "", width) end
  local rows = d.rows or {}
  local function asks(r) local a = {}; for _, x in ipairs(r.asks or {}) do a[#a + 1] = x end
    for _, x in ipairs(r.need or {}) do a[#a + 1] = x end; return a end
  table.sort(rows, function(a, b)
    local na, nb = #asks(a) + #(a.plans or {}) > 0, #asks(b) + #(b.plans or {}) > 0
    if na ~= nb then return na end
    return (tonumber(a.i) or 0) < (tonumber(b.i) or 0)
  end)
  local L = {}
  -- ind: wrapped lines of a bullet start under its text, not at column 0
  local function add(text, fg, ind)
    ind = ind or 0
    L[#L + 1] = (plainLines(text, width - ind, fg):gsub("\n", "\n" .. (" "):rep(ind)))
  end
  add((d.session or "") .. "  " .. (d.ts or "") .. "   long-press = refresh", "808080")
  for _, r in ipairs(rows) do
    local a = asks(r)
    local name = (r.name or ""):gsub("^.-│%S*%s*", "") -- drop the "🙋│🔵 " badge
    add("")
    add(r.win .. "  " .. name, (#a + #(r.plans or {}) > 0) and "f5f543" or "cccccc")
    local meta = { r.state }
    if r.pct then meta[#meta + 1] = r.pct .. "%" end
    if (r.eta or "") ~= "" then meta[#meta + 1] = "ETA " .. r.eta end
    add("  " .. table.concat(meta, " · "), "808080")
    for k, x in ipairs(a) do
      if k > 3 then add("  +" .. (#a - 3) .. " more", "808080"); break end
      add("  • " .. cut(x:gsub("^%-%s*", ""):gsub("%*%*", ""), 160), "ff9e64", 4)
    end
    for _, pl in ipairs(r.plans or {}) do add("  plan " .. (pl.id or "?") .. " → «" .. (pl.say or "") .. "»", "6eb5ff") end
  end
  if #(d.extra or {}) > 0 then
    add("")
    add("Other", "f5f543")
    for _, x in ipairs(d.extra) do add("  • " .. cut(x, 160), "cccccc", 4) end
  end
  return table.concat(L, "\n")
end

M.pane = pane -- debug: hs -c to inspect one window

local function currentSession()
  local s = hs.execute(TMUX .. " list-clients -F '#{client_session}' | head -1"):gsub("%s+", "")
  if s == "" then s = hs.execute(TMUX .. " list-sessions -F '#{session_name}' | head -1"):gsub("%s+", "") end
  return s
end

local function runRecipe(r)
  -- one window per recipe: close the previous "deck:<label>" before opening a fresh one
  for _, w in ipairs(sessions()) do
    if w.name == clean("deck:" .. r[1]) then task(TMUX, { "kill-window", "-t", w.id }) end
  end
  local id = hs.execute(TMUX .. " new-window -d -P -F '#{window_id}' -t '" .. currentSession() .. ":' -n 'deck:"
    .. r[1] .. "' \"" .. r[2] .. "; echo; read -sk '?done, any key closes'\" "):gsub("%s+", "")
  return id
end

-- claude in a new window of the project's session; the task text never meets a shell
local function spawnClaude(w, text)
  local function q(s) return "'" .. s:gsub("'", "'\\''") .. "'" end -- registry values only, never the body
  local has = os.execute(TMUX .. " has-session -t " .. q("=" .. w.session) .. " 2>/dev/null")
  local cmd = has and ("new-window -d -t " .. q("=" .. w.session .. ":")) or ("new-session -d -s " .. q(w.session))
  local id = hs.execute(TMUX .. " " .. cmd .. " -P -F '#{window_id}' -c " .. q(w.dir)):gsub("%s+", "")
  if not id:match("^@%d+$") then return nil end
  -- ≥2 command args → tmux execvp()s them directly: the body stays one argv, whatever it holds
  task(TMUX, { "respawn-pane", "-k", "-t", id, "claude", text })
  return id
end

-- /chat, cached like sessions: answer from the cache at once, refresh async (≤1 per 2 s per window),
-- forget a window nobody asked about for 60 s — two sync hs.execute here froze HS ~10% of the time
local chatCache = {}
local function chat(id, n)
  local now = os.time()
  for k, e in pairs(chatCache) do if now - e.asked > 60 then chatCache[k] = nil end end
  local e = chatCache[id] or { fetched = 0 }
  chatCache[id], e.asked = e, now
  if not e.busy and now - e.fetched >= 2 then
    e.busy, e.fetched = true, now
    local function done(d) e.data, e.busy = d, false end
    task(TMUX, { "show", "-wv", "-t", id, "@agent_transcript" }, function(out)
      local path = out:gsub("%s+$", "")
      if path == "" then return done({ msgs = {}, err = "no transcript" }) end
      -- the hook keeps the session JSONL per window; agent-state.sh chat turns it into u/a/t lines
      task(AGENT_STATE, { "chat", path, tostring(math.max(1, math.min(30, n or 15))) }, function(raw)
        local ok, d = pcall(hs.json.decode, raw)
        if not ok or type(d) ~= "table" then return done({ msgs = {}, err = "no transcript" }) end
        for _, m in ipairs(d.msgs or {}) do -- mono clean keeps the newlines of a chat bubble
          local cok, c = pcall(clean, tostring(m.x), true)
          m.x = cut((cok and c or ""):gsub("^%s+", ""), 500) -- the 🔧/❓ the board can't draw leave a space
        end
        done(d)
      end)
    end)
  end
  return e.data or { msgs = {}, wait = true }
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

-- ── deck.json: Stream Deck pages + per-app ring; reloaded when the file changes ──
local DECK_FILE = HOME .. "/.hammerspoon/deck.json"
local deckCfg, deckVer = { deck = {}, ring = {} }, ""
local function loadDeck()
  local raw = readFile(DECK_FILE) or "{}"
  local ok, c = pcall(hs.json.decode, raw)
  if ok and type(c) == "table" then
    deckCfg, deckVer = c, hs.hash.MD5(raw)
  else
    print("deck.json: invalid JSON, keeping the previous buttons")
  end
end

local function ringFor(app)
  local r = deckCfg.ring or {}
  return r[app] or r["*"] or {}, r[app] and app or "*"
end

local function strip(buttons) -- what the board needs: no actions
  local out = {}
  for i, b in ipairs(buttons or {}) do out[i] = { label = clean(b.label or ""), icon = b.icon, color = b.color } end
  return out
end

local MODS = { cmd = "cmd", command = "cmd", shift = "shift", alt = "alt", option = "alt", opt = "alt", ctrl = "ctrl", control = "ctrl", fn = "fn" }
local SYSKEY = { play = "PLAY", next = "NEXT", prev = "PREVIOUS", volup = "SOUND_UP", voldown = "SOUND_DOWN", mute = "MUTE" }

local function runAction(a, label)
  if type(a) ~= "table" then return nil end
  if a.app then hs.application.launchOrFocus(a.app) end
  if a.keys then
    local mods, key = {}, nil
    for part in a.keys:gmatch("[^+]+") do
      if MODS[part:lower()] then mods[#mods + 1] = MODS[part:lower()] else key = part end
    end
    if key then hs.eventtap.keyStroke(mods, key, 0) end
  end
  if a.media and SYSKEY[a.media] then
    hs.eventtap.event.newSystemKeyEvent(SYSKEY[a.media], true):post()
    hs.eventtap.event.newSystemKeyEvent(SYSKEY[a.media], false):post()
  end
  if a.url then task("/usr/bin/open", { a.url }) end
  if a.sh then task("/bin/zsh", { "-lc", a.sh }) end
  if a.lua then
    local fn, err = load(a.lua)
    if fn then pcall(fn) else print("deck lua: " .. tostring(err)) end
  end
  if a.convert then convert(macFiles, a.convert) end
  if a.term then return runRecipe({ label or "deck", a.term }) end -- the board opens this tmux window
end

-- ── control panel (Raven-style): toggles, sliders, what needs you ──
-- memory: the biggest processes (killable from the board, never system ones) + pressure + free disk
local NO_KILL = { kernel_task = 1, WindowServer = 1, launchd = 1, loginwindow = 1, Hammerspoon = 1, Finder = 1, Dock = 1,
  SystemUIServer = 1, coreaudiod = 1, mds = 1, mds_stores = 1, cfprefsd = 1, ["Claude Code"] = 1, claude = 1 }
local topPids, memRaw = {}, ""
local function memoryState()
  local raw = memRaw -- async below: three sync hs.execute here ran on every panel poll
  task("/bin/sh", { "-c", "/bin/ps -axo pid=,rss=,comm= -m | /usr/bin/head -40; echo '\1'; "
    .. "/usr/sbin/sysctl -n kern.memorystatus_vm_pressure_level; /bin/df -g / | /usr/bin/awk 'NR==2{print $4}'" },
    function(out) memRaw = out end)
  local ps, rest = raw:match("^(.-)\1\n(.*)$")
  local pressure, free = (rest or ""):match("^(%d+)%s+(%d+)")
  local procs, pids = {}, {}
  for pid, rss, cmd in (ps or ""):gmatch("%s*(%d+)%s+(%d+)%s+([^\n]+)") do
    local name = cmd:match("([^/]+)$") or cmd
    -- Claude Code shows up as its version ("2.1.303") or "claude …": quitting it would kill the sessions
    local claude = name:match("^%d+%.%d+%.%d+$") or name:lower():match("^claude")
    if not NO_KILL[name] and not claude and tonumber(pid) > 300 and #procs < 6 then
      procs[#procs + 1] = { pid = tonumber(pid), name = clean(name):sub(1, 28), mb = math.floor(tonumber(rss) / 1024) }
      pids[tonumber(pid)] = true
    end
  end
  if ps then topPids = pids end
  return { ram = sysmonitor.ramPct(), pressure = ({ ["1"] = "normal", ["2"] = "warning", ["4"] = "critical" })[pressure] or "?",
           disk = tonumber(free) or 0, procs = procs }
end

local function panelState()
  local out, inp = hs.audiodevice.defaultOutputDevice(), hs.audiodevice.defaultInputDevice()
  local notes = {}
  for _, w in ipairs(sessions()) do
    if w.claude and w.state == "waiting" then
      notes[#notes + 1] = { icon = "bell", t = w.idx .. "  " .. w.name, s = "Claude is waiting for you", id = w.id }
    end
  end
  for _, l in ipairs(calendarLines()) do
    if l:find(" · in ") or l:find("^● ") then notes[#notes + 1] = { icon = "call", t = l, s = "calendar" } end
  end
  if #rem > 0 then notes[#notes + 1] = { icon = "warning", t = #rem .. " reminders", s = rem[1].t } end
  local b = hs.brightness.get()
  return {
    vol = out and math.floor(out:outputVolume() or 0) or 0, muted = out and out:outputMuted() or false,
    mic = inp and inp:inputMuted() or false, bright = b or -1,
    dark = hs.host.interfaceStyle() == "Dark", awake = hs.caffeinate.get("displayIdle") or false,
    np = macNP, notes = notes, mem = memoryState(),
  }
end

local function panelSet(key, v)
  local out, inp = hs.audiodevice.defaultOutputDevice(), hs.audiodevice.defaultInputDevice()
  if key == "vol" and out then out:setOutputVolume(v); out:setOutputMuted(false) end
  if key == "bright" then hs.brightness.set(v) end
  if key == "mic" and inp then inp:setInputMuted(not inp:inputMuted()) end
  if key == "awake" then hs.caffeinate.toggle("displayIdle") end
  if key == "sleep" then task("/usr/bin/pmset", { "displaysleepnow" }) end
  if key == "kill" and topPids[v] then task("/bin/kill", { tostring(v) }) end -- only a pid the board was shown
  if key == "hogs" then return runRecipe({ "disk hogs", "just -g disk-hogs" }) end
  if key == "dark" then
    osa('tell application "System Events" to tell appearance preferences to set dark mode to not dark mode')
  end
end

local frontName = ""
local function state()
  if voice.state == "rec" then voice.text = clean(readFile(VOICE_FILE .. ".partial") or "") end
  local fa = hs.application.frontmostApplication()
  frontName = fa and fa:name() or ""
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
    rem = rem, todo = todo, cal = calendarLines(), sessions = sessions(), asks = asks(),
    recipes = recipes, slash = SLASH, voice = voice, fw = readFile(FW_SHA),
    front = frontName, ring = strip((ringFor(frontName))), deckv = deckVer, board = M.boardVer,
  }
end

local enterTimers = {} -- id → the pending Enter of a /send (kept so it is not collected before it fires)
local function handle(method, path, headers, body)
  if method == "OPTIONS" then return reply("", 204) end
  local token = env.get("DECK_TOKEN")
  if not token or headers["X-Deck-Token"] ~= token then return reply("forbidden", 403) end

  if headers["X-Deck-Ver"] then M.boardVer = headers["X-Deck-Ver"] end
  local route, qs = path:match("^([^?]*)%??(.*)$")
  local p = query(qs)
  local id = p.t and p.t:match("^@%d+$")

  if method == "GET" and route == "/state" then return reply(state(), 200, true) end
  if method == "GET" and route == "/pane" and id then return reply(pane(id, p.c == "1", tonumber(p.w), p.m == "clean"), 200, true) end
  if method == "POST" and route == "/send" and id then
    task(TMUX, { "send-keys", "-t", id, "-l", "--", body or "" }, function()
      -- an Enter right behind the text lands before Claude's input has it: "/compact" would go out as a message
      if p.enter == "1" then
        enterTimers[id] = hs.timer.doAfter(0.3, function() enterTimers[id] = nil; task(TMUX, { "send-keys", "-t", id, "Enter" }) end)
      end
    end)
    return reply("ok", 200)
  end
  if method == "POST" and route == "/net" then
    local r = p.r or "day"
    if r ~= "day" and r ~= "month" and r ~= "year" then return reply("r=day|month|year", 400) end
    local ok, top = pcall(hs.json.decode, readFile(NET_DIR .. "/net-" .. r .. ".json") or "[]")
    top = ok and type(top) == "table" and top or {}
    for _, d in ipairs(top) do d.name = safeClean(tostring(d.name), 40) end
    return reply({ r = r, top = top }, 200, true)
  end
  if method == "POST" and route == "/key" and id and validKey(p.k) then
    task(TMUX, { "send-keys", "-t", id, p.k })
    -- Escape interrupts Claude (the board's "Ні" too) and an interrupt fires no Stop hook: without this the window
    -- would keep its answered ask / "working" for good. agent-state.sh done drops them (the hook wants $TMUX)
    if p.k == "Escape" then
      for _, w in ipairs(sessionCache) do
        if w.id == id and w.state ~= "" then
          task("/bin/sh", { "-c", 'TMUX="$(tmux display -p "#{socket_path}"),0,0" TMUX_PANE="$1" "$0" done </dev/null',
                                   AGENT_STATE, id })
          break
        end
      end
    end
    return reply("ok", 200)
  end
  local r = RECIPES[tonumber(p.r or "")]
  if method == "POST" and route == "/run" and r then return reply({ t = runRecipe(r) }, 200, true) end
  local width = math.max(20, math.min(200, tonumber(p.w) or 53))
  if method == "POST" and route == "/page" then
    local h = hub[tonumber(p.i or "")]
    if not h then return reply("not found", 404) end
    local text = htmlText(readFile(HUB_DIR .. "/" .. h.path) or "", p.lang)
    return reply({ title = h.t, text = plainLines(text, width) }, 200, true)
  end
  -- heavy lists only when the board opens that tab (lazy), not in every 2-second /state
  if method == "POST" and route == "/hub" then
    refreshHub() -- async: the board gets the cached list now, a fresh one on its next open
    return reply({ hub = hub }, 200, true)
  end
  if method == "POST" and route == "/projlist" then
    refreshProjects()
    return reply({ proj = projects }, 200, true)
  end
  if method == "POST" and route == "/deck" then
    local pages = {}
    for i, pg in ipairs(deckCfg.deck or {}) do pages[i] = { page = clean(pg.page or ("Page " .. i)), buttons = strip(pg.buttons) } end
    return reply({ pages = pages, v = deckVer }, 200, true)
  end
  if method == "POST" and route == "/act" then
    local b
    if p.d then
      local pg = (deckCfg.deck or {})[tonumber(p.d) or 0]
      b = pg and (pg.buttons or {})[tonumber(p.i) or 0]
    elseif p.r then
      b = (ringFor(p.app or ""))[tonumber(p.r) or 0]
    end
    if not b then return reply("no such button", 404) end
    local t = runAction(b.action, b.label)
    return reply({ t = t or "" }, 200, true)
  end
  if method == "POST" and route == "/panel" then
    local t = p.set and panelSet(p.set, tonumber(p.v) or 0)
    refreshMac()
    local st = panelState()
    st.t = t -- disk hogs opens its tmux window on the board
    return reply(st, 200, true)
  end
  if method == "POST" and route == "/mac" then
    local names = {}
    refreshMac() -- answer from the cache, refresh for the next call (~1 s later)
    for i, f in ipairs(macFiles) do
      if i > 8 then names[#names + 1] = "…"; break end
      names[#names + 1] = clean(f:match("[^/]+$"))
    end
    return reply({ np = macNP, files = names, conv = clean(conversion) }, 200, true)
  end
  local MEDIA_KEY = { play = "PLAY", next = "NEXT", prev = "PREVIOUS", volup = "SOUND_UP", voldown = "SOUND_DOWN" }
  if method == "POST" and route == "/media" and MEDIA_KEY[p.k] then
    hs.eventtap.event.newSystemKeyEvent(MEDIA_KEY[p.k], true):post()
    hs.eventtap.event.newSystemKeyEvent(MEDIA_KEY[p.k], false):post()
    return reply("ok", 200)
  end
  if method == "POST" and route == "/convert" and (SIPS_FMT[p.f] or FFMPEG_FMT[p.f]) then
    convert(macFiles, p.f)
    return reply("ok", 200)
  end
  if method == "POST" and route == "/open" then
    local h = hub[tonumber(p.i or "")]
    if h then task("/usr/bin/open", { HUB_URL .. h.path }) end
    return reply("ok", 200)
  end
  if method == "POST" and route == "/fleet" then
    return reply({ title = "Fleet", text = fleetText(width) }, 200, true)
  end
  if method == "POST" and route == "/proj" and p.n and ({ up = 1, down = 1, restart = 1 })[p.a] then
    for _, pr in ipairs(projects) do
      if pr.n == p.n then -- registry name only, never free text, reaches the shell
        task("/opt/homebrew/bin/just", { "--justfile", PROJCTL .. "/justfile", "--working-directory", PROJCTL, p.a, pr.n },
             function() refreshProjects() end)
      end
    end
    return reply("ok", 200)
  end
  if method == "POST" and route == "/chat" and id then return reply(chat(id, tonumber(p.n)), 200, true) end
  if method == "POST" and route == "/spawn" then
    refreshProjects()
    local w = projWhere[p.p or ""]
    if not w then return reply("unknown project", 400) end
    if not (body or ""):match("%S") then return reply("empty task", 400) end -- voice that wasn't recognised
    local id = spawnClaude(w, body)
    if not id then return reply("tmux failed", 500) end
    refreshSessions()
    return reply({ t = id }, 200, true)
  end
  if method == "POST" and route == "/log" then
    local f = io.open(HOME .. "/Library/Logs/esp-deck.log", "a")
    if f then
      for line in (body or ""):gmatch("[^\n]+") do f:write(os.date("%H:%M:%S "), line, "\n") end
      f:close()
    end
    return reply("ok", 200)
  end
  if method == "POST" and route == "/mic" then
    if p.clear == "1" then voice = { state = "idle", text = "" }
    elseif p.down == "1" then micDown(p.lang)
    else micUp() end
    return reply("ok", 200)
  end
  return reply("not found", 404)
end

-- a slow request (>300 ms in the handler) or an HS main-thread stall (the 0.25 s tick late by >1 s: some module's
-- sync hs.execute) goes to ~/Library/Logs/deck-slow.log — the board's "perf state 4153ms" lines name neither
local SLOW_LOG = HOME .. "/Library/Logs/deck-slow.log"
local function slowLog(line)
  print("deck slow: " .. line)
  local f = io.open(SLOW_LOG, "a")
  if f then f:write(os.date("%H:%M:%S "), line, "\n"); f:close() end
end
local function timed(method, path, headers, body)
  local t0 = hs.timer.absoluteTime()
  local a, b, c = handle(method, path, headers, body)
  local ms = (hs.timer.absoluteTime() - t0) / 1e6
  if ms > 300 then slowLog(string.format("%s %s %.0f ms", method, path:match("^[^?]*"), ms)) end
  return a, b, c
end

function M.start()
  loadDeck()
  refreshHub() -- warm the cache once; later only when the board opens Hub
  M.deckWatcher = hs.pathwatcher.new(DECK_FILE, loadDeck):start()
  refreshSlow()
  M.slowTimer = hs.timer.doEvery(60, refreshSlow) -- statusline.sh (bash + python) + reminders: once a minute is plenty
  refreshSessions()
  refreshProjects() -- warm: /spawn and /projlist answer from it
  refreshFleet()
  memoryState()
  M.sessionTimer = hs.timer.doEvery(3, refreshSessions)
  local last = hs.timer.absoluteTime()
  M.stallTimer = hs.timer.doEvery(0.25, function()
    local t = hs.timer.absoluteTime()
    local gap = (t - last) / 1e6
    last = t
    if gap > 1250 then
      local l = (package.loaded["modules.stallprof"] or {}).last -- the callback that ended last: the stall's suspect
      slowLog(string.format("HS stall %.0f ms%s", gap - 250,
        l and string.format(" · last cb %s (%.0f ms, ended %.0f ms ago)", l.label, l.ms, (t - l.at) / 1e6) or ""))
    end
  end)
  M.server = hs.httpserver.new(false, false):setPort(PORT):setCallback(timed):start()
end

return M
