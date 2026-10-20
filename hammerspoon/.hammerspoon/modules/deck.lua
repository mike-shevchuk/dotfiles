-- ESP32 deck: HTTP API for the Waveshare ESP32-C5 touch board (firmware + web simulator: ~/code/esp-deck)
-- GET  /state               → dashboard, tmux sessions, recipes, voice state (JSON)
-- GET  /pane?t=@ID          → last lines of that tmux window
-- POST /send?t=@ID&enter=1  → request body typed into the window (then Enter)
-- POST /key?t=@ID&k=Enter   → one whitelisted tmux key
-- POST /run?r=N             → RECIPES[N] in a new tmux window → {"t":"@ID"}
-- POST /mic?down=1&lang=uk  → hold-to-talk: 1 starts DeckHelper.app, 0 stops it → text in /state.voice
-- POST /mic?clear=1         → forget the last transcript
-- POST /log                 → board log lines + timings, appended to ~/Library/Logs/esp-deck.log (`just logs`)
-- POST /hub, /projlist      → recent hub pages, projctl projects (lazy: only when that tab opens)
-- POST /page?i=N&w=COLS     → hub page N as plain text cut to COLS   ·  POST /open?i=N → open it on the Mac
-- POST /fleet?w=COLS        → `lead.py fleet` board (plain python, no Claude tokens)
-- POST /proj?n=NAME&a=up|down|restart → projctl
-- POST /mac                 → now playing (Spotify / Music) + files selected in Finder + last conversion
-- POST /media?k=play|next|prev|volup|voldown → media keys (also drive YouTube in the browser)
-- POST /convert?f=jpg|png|heic|gif|pdf|mp4|mp3|m4a → convert the Finder selection, results land next to the originals
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
local VIEWER = HOME .. "/code/esp-deck/viewer/server.mjs" -- headless-Chrome remote browser for the board (:7779)
local hub, projects = {}, {}

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
  local list = {}
  for line in (readFile(PROJCTL .. "/registry.conf") or ""):gmatch("[^\n]+") do
    local name, _, session, port, _, auto = line:match("^([^#|][^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|?(%d?)")
    if name then
      local ok = os.execute(TMUX .. " has-session -t '=" .. session .. "' 2>/dev/null")
      list[#list + 1] = { n = name, on = ok == true, port = port, auto = auto == "1" }
    end
  end
  projects = list
end

local function refreshSlow()
  slowTick = slowTick + 1
  refreshHub()
  refreshProjects()
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

local function pane(id, colors, width)
  width = width and width >= 20 and width or 1000 -- old firmware sends no w: no wrapping here
  local out = hs.execute(TMUX .. " capture-pane -p -e -J -S -120 -t '" .. id .. "'") or ""
  out = out:gsub("\27%]8;[^\27]*\27\\", "") -- OSC 8 hyperlinks
  local lines, blank, fg = {}, false, nil
  for line in (out .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("%s+$", "")
    local plain = line:gsub("\27%[[%d;]*m", "")
    local empty = plain:match("^%s*$") ~= nil
    if isRule(plain) then -- a ─── rule: one screen wide, no colour
      line = utf8.len(plain) > width and plain:sub(1, utf8.offset(plain, width + 1) - 1) or plain
    end
    if not empty or not blank then
      local segs
      segs, fg = segments(line, fg, colors)
      if #segs == 0 then lines[#lines + 1] = "" else wrap(segs, width, lines) end
    end
    blank = empty
  end
  while #lines > 60 do table.remove(lines, 1) end -- the board re-renders all of it every second: keep it light
  return { t = id, text = table.concat(lines, "\n") }
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
local function plainLines(text, width)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    line = clean(line, true)
    if line == "" then out[#out + 1] = "" end
    -- break at the last space that fits (prose); wrap() still hard-cuts anything longer than a line
    while line ~= "" do
      local len = utf8.len(line)
      if len <= width then
        wrap({ { nil, line } }, width, out)
        break
      end
      local cut = utf8.offset(line, width + 1)
      local sp = line:sub(1, cut - 1):match(".*() ")
      if not sp or sp < cut / 2 then sp = cut end
      wrap({ { nil, line:sub(1, sp - 1) } }, width, out)
      line = line:sub(sp):gsub("^ ", "")
    end
    if #out > 1500 then break end
  end
  return table.concat(out, "\n")
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
  if method == "GET" and route == "/pane" and id then return reply(pane(id, p.c == "1", tonumber(p.w)), 200, true) end
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
  local width = math.max(20, math.min(200, tonumber(p.w) or 53))
  if method == "POST" and route == "/page" then
    local h = hub[tonumber(p.i or "")]
    if not h then return reply("not found", 404) end
    local text = htmlText(readFile(HUB_DIR .. "/" .. h.path) or "", p.lang)
    return reply({ title = h.t, text = plainLines(text, width) }, 200, true)
  end
  -- heavy lists only when the board opens that tab (lazy), not in every 2-second /state
  if method == "POST" and route == "/hub" then return reply({ hub = hub }, 200, true) end
  if method == "POST" and route == "/projlist" then
    refreshProjects()
    return reply({ proj = projects }, 200, true)
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
    local out = hs.execute("PATH=" .. PATH .. ":$HOME/.pyenv/shims python3 " .. HOME .. "/.claude/scripts/lead.py fleet 2>&1") or ""
    return reply({ title = "Fleet", text = plainLines(out:gsub("\27%[[%d;]*m", ""), width) }, 200, true)
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

-- the remote browser lives as long as Hammerspoon; restart it if it dies
local function startViewer()
  M.viewer = hs.task.new("/bin/sh", function(code)
    print("deck viewer exited " .. tostring(code) .. ", restarting in 5 s")
    M.viewerTimer = hs.timer.doAfter(5, startViewer) -- keep a reference: an unreferenced timer gets collected
  end, { "-c", "exec node " .. VIEWER .. " >> /tmp/deck-viewer.log 2>&1" })
  M.viewer:setEnvironment({ PATH = PATH .. ":" .. HOME .. "/.local/share/mise/installs/node/latest/bin", HOME = HOME,
                            DECK_TOKEN = env.get("DECK_TOKEN") or "" })
  M.viewer:start()
end

function M.start()
  if not M.viewer then startViewer() end
  refreshSlow()
  M.slowTimer = hs.timer.doEvery(20, refreshSlow)
  M.server = hs.httpserver.new(false, false):setPort(PORT):setCallback(handle):start()
end

return M
