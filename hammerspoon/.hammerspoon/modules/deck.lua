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

-- "+ task" targets beyond projctl: every tmux session (its active pane's dir) and every git repo under
-- ~/code (depth 3, no worktrees), ~/dotfiles, ~/zettelkasten — refreshed async, looked up by /spawn
local extraWhere, extraNames = {}, {}
local function refreshTargets()
  task(TMUX, { "list-sessions", "-F", "#{session_name}\t#{pane_current_path}" }, function(out)
    local w, names = {}, {}
    for name, dir in out:gmatch("([^\t\n]+)\t([^\n]+)") do
      w[name] = { dir = dir, session = name }
      names[#names + 1] = name
    end
    task("/usr/bin/find", { HOME .. "/code", "-maxdepth", "3", "-name", ".git", "-type", "d" }, function(found)
      local repos = { HOME .. "/dotfiles", HOME .. "/zettelkasten" }
      for g in found:gmatch("[^\n]+") do
        if not g:find("/worktrees/") and not g:find("/%.claude/") then repos[#repos + 1] = g:gsub("/%.git$", "") end
      end
      table.sort(repos)
      for _, dir in ipairs(repos) do
        local name = dir:match("([^/]+)$"):gsub("[^%w_%-]", "_")
        if not w[name] then
          w[name] = { dir = dir, session = name }
          names[#names + 1] = name
        end
      end
      extraWhere, extraNames = w, names
    end)
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
  refreshTargets()
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
-- windows Claude's hooks never tag: a `claude agents` client (its hook-reported file is never written; the agent it
-- shows is a background job) and a claude whose hook never ran. Their state comes from the background jobs' own
-- state.json (every ~10 s) or from how fresh their transcript is.
-- window id → the transcript its chat shows (a job's, or the project's newest unclaimed); kept on disk across reloads
local JOBPICK_FILE = HOME .. "/.hammerspoon/deck-jobpick.json"
local jobPick = (function()
  local f = io.open(JOBPICK_FILE)
  local ok, t = pcall(hs.json.decode, f and f:read("a") or "")
  if f then f:close() end
  return ok and type(t) == "table" and t or {}
end)()
local function savePick(id, tr)
  jobPick[id] = tr
  local f = io.open(JOBPICK_FILE, "w")
  if f then f:write(hs.json.encode(jobPick)); f:close() end
end
local jobs = { by = {}, active = {}, tr = {} } -- job transcript → state; active jobs for the picker; job id → transcript
local JQ = "/usr/bin/jq"
local function jobStates()
  local r = {}
  for f in hs.fs.dir(HOME .. "/.claude/jobs") do
    local p = HOME .. "/.claude/jobs/" .. f .. "/state.json"
    if f:sub(1, 1) ~= "." and hs.fs.attributes(p) then r[#r + 1] = p end
  end
  return r
end
local function refreshJobs()
  task(JQ, { "-r", 'select(.linkScanPath) | "\\(.updatedAt)\t\\(.state)\t\\(.daemonShort // .sessionId[:8])\t\\(.name // "?")\t\\(.linkScanPath)"',
    table.unpack(jobStates()) }, function(o)
    local by, active, tr = {}, {}, {}
    local dayAgo = os.date("!%Y-%m-%dT%H:%M:%S", os.time() - 86400)
    for at, st, jid, name, path in o:gmatch("([^\t\n]+)\t([^\t\n]+)\t([^\t\n]+)\t([^\t\n]*)\t([^\n]+)") do
      by[path], tr[jid] = st, path
      -- active = touched in the last 24 h; one blocked for weeks is not "waiting for you" any more
      if st ~= "done" and st ~= "failed" and at >= dayAgo and hs.fs.attributes(path) then
        active[#active + 1] = { id = jid, name = safeClean(name, 40), st = st, at = at }
      end
    end
    table.sort(active, function(a, b) return a.at > b.at end)
    jobs = { by = by, active = active, tr = tr }
    -- a claude whose hook never ran (no @agent_transcript, e.g. a lead started before the hooks): the newest
    -- transcript of its project that no window, pick or background job owns
    local taken = {}
    for _, j in ipairs(active) do taken[tr[j.id]] = true end -- live background jobs (a done one may be resumed in a window)
    for _, t in pairs(jobPick) do taken[t] = true end
    for _, w in ipairs(sessionCache) do if w.tr ~= "" then taken[w.tr] = true end end
    for _, w in ipairs(sessionCache) do
      if w.claude and w.state == "" and not jobPick[w.id] and (w.cwd or "") ~= "" then
        local dir = HOME .. "/.claude/projects/" .. w.cwd:gsub("[/.]", "-")
        if hs.fs.attributes(dir) then
          local best, bestM
          for f in hs.fs.dir(dir) do
            local path = dir .. "/" .. f
            local m = f:match("%.jsonl$") and not taken[path] and hs.fs.attributes(path, "modification")
            if m and (not bestM or m > bestM) then best, bestM = path, m end
          end
          if best then taken[best] = true; savePick(w.id, best) end
        end
      end
    end
  end)
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
        e.title = safeClean(d.title or "", 60) -- the Claude session's own name (/rename, else its ai-title)
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
      list[#list + 1] = { id = id, idx = idx, name = name, state = st, kind = kind, claude = claude, tr = tr, cwd = cwd,
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
  -- background sessions (claude --bg) have no tmux window: a row each in a "bg" block, unless a window shows it
  local shown = {}
  for _, w in ipairs(list) do if w.tr ~= "" then shown[w.tr] = true end end
  for _, t in pairs(jobPick) do shown[t] = true end
  for _, j in ipairs(jobs.active) do
    local t = jobs.tr[j.id]
    if t and not shown[t] then
      list[#list + 1] = { id = "job:" .. j.id, idx = "bg:" .. j.id:sub(1, 4), name = j.name, state = "", kind = "",
                          claude = true, tr = t, job = j.st, n = #list }
    end
  end
  for _, w in ipairs(list) do -- untagged Claude windows: the transcript they most likely show
    if w.claude and w.state == "" then
      local live = w.tr ~= "" and hs.fs.attributes(w.tr)
      if w.job then live = true end
      if not live then w.tr = jobPick[w.id] or "" end -- a `claude agents` window: only once you picked its session
      w.untagged = true
    end
  end
  refreshInfo(list)
  local now = os.time()
  for _, w in ipairs(list) do
    if w.claude then
      w.at = w.at or (infoCache[w.tr] or {}).mtime -- @agent_at comes with the next hook event; until then the transcript's
      local m = w.untagged and w.tr ~= "" and hs.fs.attributes(w.tr, "modification")
      local js = w.untagged and jobs.by[w.tr]
      -- a fresh transcript beats the job's own state, which lags (still "blocked" while it already works again)
      if m and now - m <= 90 then w.st = "working"
      elseif js == "blocked" and m and now - m <= 7200 then w.st = "waiting"
      elseif js == "working" then w.st = "working"
      elseif w.state == "working" then w.st = "working"
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
local jobTick = 0
local function refreshSessions()
  jobTick = jobTick + 1
  if jobTick % 3 == 1 then refreshJobs() end -- every ~9 s
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
      if e.title and e.title ~= "" and e.title ~= w.name then s.title = e.title end
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
local journalAdd -- the board's 📝 (hold the mic on the Garmin card): set below, next to Garmin's data

local function micDown(lang)
  os.remove(VOICE_FILE)
  os.remove(VOICE_FILE .. ".partial")
  voice = { state = "rec", text = "" }
  task("/usr/bin/open", { "-g", "-n", "-a", HELPER_APP, "--args", "listen", lang == "en" and "en-US" or "uk-UA", VOICE_FILE })
end

-- the board's own mic: raw PCM arrives in /mic/pcm chunks, the close (/mic?down=0&board=1) runs whisper on it
local PCM_FILE, WAV_FILE = "/tmp/deck-voice.pcm", "/tmp/deck-voice.wav"
local WHISPER = "/opt/homebrew/bin/whisper-cli"
-- same model + tuning as the stt-host service (~/zettelkasten/claude_code/stt-service/host), run directly: no extra hop
local WHISPER_MODEL = HOME .. "/.local/share/stt-host/models/ggml-large-v3-turbo-q5_0.bin"
local WHISPER_PROMPT = { uk = "Розмова українською мовою. Говоримо чітко, правильними реченнями.",
  en = "A conversation in English with clear speech and proper sentences." }

local function micBoardUp(rate, lang)
  voice.state = "busy"
  local f = io.open(PCM_FILE, "rb")
  local pcm = f and f:read("a") or ""
  if f then f:close() end
  if #pcm < rate then voice = { state = "done", text = "", journal = voice.journal }; return end -- under ½ s: nothing said
  local w = io.open(WAV_FILE, "wb")
  w:write(string.pack("<c4I4c4c4I4I2I2I4I4I2I2c4I4", "RIFF", 36 + #pcm, "WAVE", "fmt ", 16, 1, 1, rate, rate * 2, 2, 16,
    "data", #pcm), pcm)
  w:close()
  lang = lang == "en" and "en" or "uk"
  task(WHISPER, { "-m", WHISPER_MODEL, "-l", lang, "--prompt", WHISPER_PROMPT[lang], "--suppress-nst", "--beam-size", "8",
    "--best-of", "8", "-nt", "-np", "-f", WAV_FILE }, function(out)
    local j = voice.journal
    voice = { state = "done", text = clean(((out or ""):gsub("%s+", " "):gsub("^ ", ""))), journal = j }
    if j and voice.text ~= "" then journalAdd(voice.text, lang) end
  end)
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
-- RGB565 little-endian → PNG with the stdlib (zlib + struct): no Pillow needed
local SHOT_PY = [[
import sys, zlib, struct
raw, w, h, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
d = open(raw, "rb").read()
rows = bytearray()
for y in range(h):
    rows.append(0)
    for x in range(w):
        i = (y * w + x) * 2
        if i + 1 >= len(d): rows += b"\0\0\0"; continue
        p = d[i] | d[i + 1] << 8
        rows += bytes(((p >> 11) << 3, ((p >> 5) & 63) << 2, (p & 31) << 3))
chunk = lambda t, b: struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b))
open(out, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                       + chunk(b"IDAT", zlib.compress(bytes(rows))) + chunk(b"IEND", b""))
]]
local chatCache = {}
local SHOT_DIR = HOME .. "/Library/Logs/esp-deck-shots"
local lastShot -- the board's last 📷, until 📎 pastes it
local clipSeen = -1 -- pasteboard changeCount already pasted
local function clipImage() -- an image on the clipboard not pasted yet (no read of the image itself: cheap)
  if hs.pasteboard.changeCount() == clipSeen then return false end
  for _, t in ipairs(hs.pasteboard.contentTypes() or {}) do
    if t == "public.png" or t == "public.tiff" then return true end
  end
  return false
end
local function chat(id, n, force, job)
  local now = os.time()
  for k, e in pairs(chatCache) do if now - e.asked > 60 then chatCache[k] = nil end end
  local e = chatCache[id] or { fetched = 0 }
  chatCache[id], e.asked = e, now
  if force then e.fetched = 0 end -- the board's ↻: read the transcript now, not within the 2 s throttle
  if not e.busy and now - e.fetched >= 2 then
    e.busy, e.fetched = true, now
    local function done(d) e.data, e.busy = d, false end
    local function withPath(path)
      if path == "" then return done({ msgs = {}, err = "no transcript" }) end
      -- the hook keeps the session JSONL per window; agent-state.sh chat turns it into u/a/t lines
      task(AGENT_STATE, { "chat", path, tostring(math.max(1, math.min(60, n or 15))) }, function(raw)
        local ok, d = pcall(hs.json.decode, raw)
        if not ok or type(d) ~= "table" then return done({ msgs = {}, err = "no transcript" }) end
        -- newest first, whole messages up to 3000 chars, until ~36 KB: the board reads at most 48 KB per reply
        -- 14 KB by default (36 KB scrolled at 9 fps on the board); scrolling up for history asks more, up to 40 KB
        local msgs, kept, budget = d.msgs or {}, {}, math.min(40000, 14000 + math.max(0, (n or 15) - 15) * 900)
        for i = #msgs, 1, -1 do
          local m = msgs[i]
          local cok, c = pcall(clean, tostring(m.x), true) -- mono clean keeps the newlines of a chat bubble
          c = (cok and c or ""):gsub("^%s+", ""):gsub("%*%*", "") -- the 🔧/❓ the board can't draw leave a space; no bold
          m.x = cut(c, 3000)
          budget = budget - #m.x - 20
          if budget < 0 and #kept > 0 then break end
          table.insert(kept, 1, m)
        end
        d.msgs = kept
        -- the terminal's foot for the chat's status bar: Claude's spinner line ("✻ Thinking… (12s · ↑ 3k tokens)")
        -- and the status lines under the input box (model, tokens, limits, mode)
        task(TMUX, { "capture-pane", "-p", "-t", id }, function(pane)
          local lines = {}
          for l in (pane or ""):gmatch("[^\n]*") do lines[#lines + 1] = l end
          local rule, spin = nil, nil
          for i = #lines, 1, -1 do
            if not rule and lines[i]:match("^%s*─") then rule = i end
            -- "✻ Thinking… (12s · ↑ 3k tokens · esc to interrupt)", also bare "Beaming… (19m 20s · 6.6k tokens)"
            if not spin and (lines[i]:find("esc to interrupt", 1, true) or lines[i]:match("%S…%s*%(%d+[hms]")) then
              spin = safeClean(lines[i], 120)
            end
          end
          local foot = {}
          for i = (rule or #lines) + 1, #lines do
            local c = safeClean(lines[i], 160):gsub("^%s+", "")
            if c ~= "" then foot[#foot + 1] = c end
          end
          d.spin, d.foot = spin, foot
          done(d)
        end)
      end)
    end
    local jid = id:match("^job:(%w+)$") -- a background session's row: its own transcript, no window behind it
    if jid then return withPath(jobs.tr[jid] or "") end
    -- no hook-kept transcript (the hook never ran there): the newest one no other window claims, from the
    -- window's own project folder. A dead one = a `claude agents` client: the background job it most likely
    -- shows (the latest active one), kept for that window until ↻ — never a teammate's transcript.
    -- ponytail: latest-active-job guess, read the attached job id if Claude Code ever exposes it
    task(TMUX, { "display", "-p", "-t", id, "#{@agent_transcript}\t#{pane_current_path}" }, function(out)
      local path, cwd = out:gsub("%s+$", ""):match("^([^\t]*)\t?(.*)$")
      if path ~= "" and hs.fs.attributes(path) then return withPath(path) end
      if path ~= "" then -- a client of background sessions: `claude attach <id>` says which; `claude agents` can't
        if job and jobs.tr[job] then savePick(id, jobs.tr[job]) end
        return task("/bin/sh", { "-c", "ps -o args= -p \"$(pgrep -P $(" .. TMUX .. " display -p -t " .. id ..
          " '#{pane_pid}') | tr '\\n' ,)\" 2>/dev/null; " .. TMUX .. " display -p -t " .. id ..
          " '#{session_name} #{window_name}'" }, function(out)
          local att = (out or ""):match("claude attach (%S+)")
          if att then
            for jid, t in pairs(jobs.tr) do
              if jid:sub(1, #att) == att or att:sub(1, #jid) == jid then savePick(id, t) end
            end
          end
          if not jobPick[id] then -- the window's name names one active session ("esp-deck" → "Прошивка ESP32-C5…")
            local names, hit = (out or ""):match("([^\n]*)\n?$"):lower(), nil
            for _, j in ipairs(jobs.active) do
              local jn = j.name:lower()
              for w in names:gmatch("[%w]+") do
                if #w >= 3 and jn:find(w, 1, true) then hit = hit == nil and j.id or false; break end
              end
            end
            if hit then savePick(id, jobs.tr[hit]) end
          end
          if jobPick[id] then return withPath(jobPick[id]) end
          done({ msgs = {}, err = "pick", jobs = jobs.active }) -- the board asks which session this window shows
        end)
      end
      local dir = cwd ~= "" and HOME .. "/.claude/projects/" .. cwd:gsub("[/.]", "-") or ""
      if not hs.fs.attributes(dir) then return withPath("") end
      task("/bin/sh", { "-c", TMUX .. " list-windows -a -F '#{@agent_transcript}'; echo --; ls -t " .. dir .. "/*.jsonl | head -20" }, function(o)
        local claimed, past = {}, false
        for l in o:gmatch("[^\n]+") do
          if l == "--" then past = true
          elseif not past then claimed[l] = true
          elseif not claimed[l] then savePick(id, l); return withPath(l) end
        end
        withPath("")
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
-- ── Mac notifications → the board: only the app's name flashes there; the text waits in the board's ✉ panel ──
-- helper/notes.py reads Notification Center's database (Hammerspoon needs Full Disk Access); it runs only when
-- the database file changed (one stat every 3 s)
local NOTES_PY = HOME .. "/code/esp-deck/helper/notes.py"
local NOTES_DB = HOME .. "/Library/Group Containers/group.com.apple.usernoted/db2/db"
local notes, notesLast, notesSeen, notesMtime, notesBusy = {}, nil, 0, -1, false
local function appName(bundle)
  return hs.application.nameForBundleID(bundle) or bundle:match("([^.]+)$") or bundle
end
local function refreshNotes()
  local m = math.max(hs.fs.attributes(NOTES_DB, "modification") or 0, hs.fs.attributes(NOTES_DB .. "-wal", "modification") or 0)
  if notesBusy or m == notesMtime then return end -- no Full Disk Access: stat says 0, one try, then quiet
  notesBusy, notesMtime = true, m
  task("/usr/bin/python3", { NOTES_PY, tostring(notesLast or 0) }, function(out)
    notesBusy = false
    for line in (out or ""):gmatch("[^\n]+") do
      local ok, d = pcall(hs.json.decode, line)
      if ok and type(d) == "table" then
        if d.last then notesLast, notesSeen = d.last, d.last -- first run: start from now, no replay
        elseif d.id then
          table.insert(notes, 1, { id = d.id, app = safeClean(appName(d.bundle), 30), title = safeClean(d.title, 120),
                                   subtitle = safeClean(d.subtitle, 120), body = safeClean(d.body, 400), at = d.at })
          notes[21] = nil
          notesLast = math.max(notesLast or 0, d.id)
        end
      end
    end
  end)
end
-- ── Garmin (helper/garmin.py, unofficial garminconnect): once logged in (`just garmin-login` in esp-deck),
-- every 15 min → /state.garmin for the board's Здоров'я tab ──
local GARMIN_PY, UV = HOME .. "/code/esp-deck/helper/garmin.py", HOME .. "/.local/bin/uv"
local garmin
local function refreshGarmin()
  if not hs.fs.attributes(HOME .. "/.garminconnect") then return end -- not logged in yet
  task(UV, { "run", "--quiet", "--with", "garminconnect", "python", GARMIN_PY, "fetch" }, function(out)
    local ok, d = pcall(hs.json.decode, (out or ""):match("([^\n]+)%s*$") or "") -- the last non-empty line
    if ok and type(d) == "table" then d.at = os.time(); garmin = d end
  end)
end

-- 📝 voice journal: "я зараз іду гуляти" → one JSON line with the time and what Garmin said at that moment,
-- for the teammate's patterns/advice (helper/health_metrics.py reads it); the board shows the last 3
local health -- (the composite metrics, filled below; the journal notes the question it answers)
local JOURNAL = HOME .. "/.local/share/esp-deck/journal.jsonl"
local journalTail = {}
journalAdd = function(text, lang)
  local g = garmin or {}
  local f = io.open(JOURNAL, "a")
  if not f then return end
  f:write(hs.json.encode({ at = os.date("%Y-%m-%dT%H:%M:%S"), text = text, lang = lang, steps = g.steps,
    hr = g.hr_now, battery = g.battery, stress = g.stress, kcal_active = g.kcal_active,
    q = health and health.ask or nil }), "\n") -- q: the metrics' question this answers, when one was up
  f:close()
  table.insert(journalTail, 1, os.date("%H:%M") .. "  " .. text)
  journalTail[4] = nil
end
do -- the last 3 after a reload
  local f = io.open(JOURNAL)
  if f then
    for l in f:lines() do
      local ok, e = pcall(hs.json.decode, l)
      if ok and e then table.insert(journalTail, 1, (e.at or ""):sub(12, 16) .. "  " .. (e.text or "")); journalTail[4] = nil end
    end
    f:close()
  end
end

-- 🎙 meetings (Plaud-style): the board streams the room's PCM (/meet/pcm), on stop helper/meeting.py runs whisper
-- + a Claude summary → ~/.local/share/esp-deck/meetings/<id>.md; /state.meet = {state, note, last[3]}
local MEET_DIR, MEET_PY = HOME .. "/.local/share/esp-deck/meetings", HOME .. "/code/esp-deck/helper/meeting.py"
local meet = { state = "idle", last = {} }
local meetId, meetCmd = nil, { n = 0 } -- meetCmd: the Mac's 🎙 menu asks the board to start / stop (it polls /state)
do
  local f = io.open(MEET_DIR .. "/index.jsonl")
  if f then
    for l in f:lines() do
      local ok, e = pcall(hs.json.decode, l)
      if ok and e then table.insert(meet.last, 1, e); meet.last[4] = nil end
    end
    f:close()
  end
end
local function meetState()
  if meet.proc and (meet.state == "stt" or meet.state == "spk" or meet.state == "sum") then
    local st = readFile(MEET_DIR .. "/" .. meet.proc .. ".stage")
    if st == "spk" or st == "sum" then meet.state = st end
  end
  local last = {} -- the full summary (body) only for the newest: /state stays small
  for i, e in ipairs(meet.last) do
    -- '#' is a colour code on the board's label: markdown headings become plain lines there
    last[i] = { id = e.id, at = e.at, title = e.title, summary = e.summary, body = i == 1 and e.body and e.body:gsub("#+ ?", "") or nil }
  end
  return { state = meet.state, note = meet.note, last = last, cmd = meetCmd }
end
-- the board names a meeting by its start (unix, the board's clock): the same name however late its parts arrive
local function meetName(bid)
  local t = tonumber(bid) or 0
  return os.date("%Y-%m-%d_%H%M%S", t > 1700000000 and t or os.time()), t
end
local meetDone = {} -- names already sent to meeting.py: a repeated stop (the board retries until a 200) is a no-op
local function meetStop(id, rate, fmt, len)
  if not id or meetDone[id] then return end
  meetDone[id] = true
  if meetId == id then meetId = nil end
  meet.state, meet.note, meet.proc = "stt", nil, id
  -- screenshots: from the start to start + the recorded length
  local secs = len and math.floor(len / (fmt == "ulaw" and rate or rate * 2)) or (os.time() - (meet.t0 or os.time()))
  task(UV, { "run", "--quiet", "--with", "sherpa-onnx", "--with", "numpy", "python", MEET_PY,
    MEET_DIR .. "/" .. id .. ".pcm", tostring(rate), meet.lang or "uk", tostring(meet.t0 or 0),
    tostring((meet.t0 or os.time()) + secs), fmt or "pcm" },
    function(out, code)
    local ok, e = pcall(hs.json.decode, (out or ""):match("([^\n]+)%s*$") or "")
    if ok and type(e) == "table" and e.title then
      table.insert(meet.last, 1, e); meet.last[4] = nil
      if meet.state ~= "rec" then meet.state = "done" end -- a newer meeting may be recording by now
      hs.notify.new({ title = "Мітинг: " .. e.title, informativeText = e.summary or "" }):send()
    else
      if meet.state ~= "rec" then meet.state, meet.note = "err", "не вдалося розшифрувати — аудіо збережено в " .. id end
    end
  end)
end

-- 🎙 in the menu bar: start / stop a meeting on the board from the Mac, see where it is, open the last summaries
-- a meeting recorded by the Mac alone (no board): ffmpeg from any input device → the same 16 kHz μ-law .pcm, and
-- on stop the same meeting.py (transcript, speakers, summary, screenshots). Needs the mic permission for Hammerspoon
local FFMPEG = "/opt/homebrew/bin/ffmpeg"
local meetMac -- the running ffmpeg task while the Mac records
local function macRecStart(dev, lang)
  local id = os.date("%Y-%m-%d_%H%M%S")
  hs.fs.mkdir(MEET_DIR)
  local path = MEET_DIR .. "/" .. id .. ".pcm"
  meetId, meet.bid = id, nil
  meet.state, meet.note, meet.lang, meet.t0, meet.lastPcm, meet.src = "rec", nil, lang, os.time(), os.time(), "mac"
  meetMac = hs.task.new(FFMPEG, function(code, _, err)
    meetMac = nil
    local size = hs.fs.attributes(path, "size") or 0
    if size < 16000 then -- under a second: the device gave nothing (mic permission? a silent virtual device?)
      meet.state, meet.note, meet.src = "err", "Mac нічого не записав: " .. ((err or ""):match("[^\n]+") or ("код " .. tostring(code))), nil
      return
    end
    meet.src = nil
    meetStop(id, 16000, "ulaw", size)
  end, { "-hide_banner", "-loglevel", "error", "-f", "avfoundation", "-i", ":" .. dev, "-ac", "1", "-ar", "16000",
    "-f", "mulaw", "-y", path })
  meetMac:start()
end

local function meetMenu()
  local items = {}
  if meet.state == "rec" and meetMac then
    table.insert(items, { title = "■ Зупинити запис на Mac", fn = function() meetMac:interrupt() end }) -- ffmpeg closes the file
  elseif meet.state == "rec" then
    table.insert(items, { title = "■ Зупинити запис", fn = function() meetCmd = { n = meetCmd.n + 1, act = "stop" } end })
    if meet.note then -- the board is away: process what arrived so far (whatever it sends later is ignored)
      table.insert(items, { title = "Обробити те, що вже прийшло", fn = function() meetStop(meetId, 16000, "ulaw") end })
    end
  else
    for _, l in ipairs({ { "uk", "UA" }, { "en", "EN" } }) do
      table.insert(items, { title = "● Почати мітинг на платі (" .. l[2] .. ")",
        fn = function() meetCmd = { n = meetCmd.n + 1, act = "start", lang = l[1] } end })
    end
    local devs = {} -- "● only the Mac": every input device, UA / EN
    for _, d in ipairs(hs.audiodevice.allInputDevices()) do
      for _, l in ipairs({ { "uk", "UA" }, { "en", "EN" } }) do
        table.insert(devs, { title = d:name() .. " · " .. l[2], fn = function() macRecStart(d:name(), l[1]) end })
      end
    end
    table.insert(items, { title = "● Записати лише Маком", menu = devs })
  end
  table.insert(items, { title = "-" })
  for _, e in ipairs(meet.last) do
    table.insert(items, { title = (e.at or "") .. "  " .. (e.title or ""),
      fn = function() task("/usr/bin/open", { MEET_DIR .. "/" .. e.id .. ".md" }) end })
  end
  table.insert(items, { title = "Відкрити папку мітингів", fn = function() task("/usr/bin/open", { MEET_DIR }) end })
  return items
end
-- screenshots go to the clipboard here (screencapture target = clipboard): mid-meeting, every new image on the
-- clipboard is saved to <id>_clips/<unix>.png; meeting.py attaches them at their moment
local meetClipSeen
local function meetClips()
  local cc = hs.pasteboard.changeCount()
  if meet.state ~= "rec" or not meetId then meetClipSeen = cc; return end
  if cc == meetClipSeen then return end
  meetClipSeen = cc
  for _, t in ipairs(hs.pasteboard.contentTypes() or {}) do
    if t == "public.png" or t == "public.tiff" then
      local img = hs.pasteboard.readImage()
      if img then
        hs.fs.mkdir(MEET_DIR .. "/" .. meetId .. "_clips")
        img:saveToFile(MEET_DIR .. "/" .. meetId .. "_clips/" .. os.time() .. ".png")
      end
      return
    end
  end
end
local function meetBar()
  meetClips()
  -- the board went quiet mid-meeting: it keeps recording into its flash and sends it all when it's back
  if meetMac then meet.lastPcm = os.time() end -- the Mac records itself: never "the board went away"
  meet.note = meet.state == "rec" and meet.lastPcm and os.time() - meet.lastPcm > 90
    and "плата поза зв'язком — пише в пам'ять і дошле" or (meet.state ~= "rec" and meet.note or nil)
  if not M.meetBar then return end
  local t = meet.state == "rec" and meet.t0 and os.time() - meet.t0 or 0
  M.meetBar:setTitle(meet.state == "rec" and string.format("🔴 %d:%02d", t // 60, t % 60)
    or (meet.state == "stt" or meet.state == "spk" or meet.state == "sum") and "🎙…" or "🎙")
end

-- the teammate's composite metrics (helper/health_metrics.py, docs/health-metrics.md): only what the board draws
local HM_PY = HOME .. "/code/esp-deck/helper/health_metrics.py"
local function refreshHealth()
  if not hs.fs.attributes(HOME .. "/.garminconnect") then return end
  task(UV, { "run", "--quiet", "--with", "garminconnect", "python", HM_PY }, function(out)
    local ok, d = pcall(hs.json.decode, (out or ""):match("([^\n]+)%s*$") or "")
    if not ok or type(d) ~= "table" or type(d.board) ~= "table" then return end
    local alerts = {}
    for i, a in ipairs(d.alerts or {}) do if i <= 3 then alerts[i] = { a[1], a[3] } end end
    health = { metrics = d.board.metrics, advice = d.board.advice, progress = d.board.progress, tip = d.tip,
               alerts = alerts, synced = d.synced, streak = (d.records or {}).streak,
               move_goal = d.move_goal, exercise_goal = d.exercise_goal, exercise_min = d.exercise_min,
               steps_goal = d.steps_goal, kg = (d.plan and d.plan.kg) or nil, bmi = d.bmi, weight = d.kg, ask = d.board.ask, bb = d.board.bb,
               stress = d.board.stress, stress_now = d.stress and d.stress.now, score = d.board.score, sleep_q = d.board.sleep,
               links = d.board.links, body = d.board.body, goals = d.board.goals, review = d.board.review, tone = d.board.tone, focus = d.board.focus,
               load = d.load and { status = d.load.status_ua, acute = d.load.acute, tunnel = d.load.tunnel,
                                   focus = d.load.focus, readiness = d.load.readiness and d.load.readiness.score,
                                   zones = d.load.zones and d.load.zones.week, text = d.board.load } or nil }
  end)
end

local function notesState() -- for /state: no text, only how many are new and whose the newest is
  local n = 0
  for _, x in ipairs(notes) do if x.id > notesSeen then n = n + 1 end end
  return notes[1] and { n = n, last = notes[1].id, app = notes[1].app } or nil
end

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
    recipes = recipes, slash = SLASH, voice = voice, fw = readFile(FW_SHA), fw_notes = readFile(FW_SHA) and readFile("/tmp/deck-ota.notes"),
    front = frontName, ring = strip((ringFor(frontName))), deckv = deckVer, board = M.boardVer,
    clip = (clipImage() and "img") or (lastShot and "shot") or nil, -- 📎 on the board: something to paste
    notes = notesState(),
    garmin = garmin,
    health = health,
    journal = journalTail,
    meet = meetState(),
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
    local live, new, seen = {}, {}, {}
    for _, w in ipairs(sessions()) do
      if w.claude then live[#live + 1] = { id = w.id, n = w.idx .. "  " .. w.name, st = w.state } end
    end
    for _, pr in ipairs(projects) do if not seen[pr.n] then new[#new + 1] = pr.n; seen[pr.n] = true end end
    for _, n in ipairs(extraNames) do if not seen[n] then new[#new + 1] = n; seen[n] = true end end
    return reply({ proj = projects, live = live, new = new }, 200, true)
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
    -- a Hacker News discussion from the board's Dash; only https links to news.ycombinator.com
    if p.u and p.u:match("^https://news%.ycombinator%.com/item%?id=%d+$") then task("/usr/bin/open", { p.u }) end
    -- the health site at the board's tab (↗ on the board, after its own yes); only the local dashboard
    -- a meeting's summary (.md) in the default app; the id is ours (date_time), nothing else opens
    if p.meet and p.meet:match("^%d%d%d%d%-%d%d%-%d%d_%d%d%d%d%d%d$") then task("/usr/bin/open", { MEET_DIR .. "/" .. p.meet .. ".md" }) end
    local hu = p.h and health and health.links and health.links[p.h]
    if type(hu) == "string" and hu:match("^http://127%.0%.0%.1:8893/") then task("/usr/bin/open", { hu }) end
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
  local jobId = p.t and p.t:match("^job:%w+$")
  if method == "POST" and route == "/chat" and jobId then return reply(chat(jobId, tonumber(p.n), p.f == "1"), 200, true) end
  if method == "POST" and route == "/chat" and id then return reply(chat(id, tonumber(p.n), p.f == "1" or p.job ~= nil, p.job), 200, true) end
  if method == "POST" and route == "/spawn" then
    refreshProjects()
    local w = projWhere[p.p or ""] or extraWhere[p.p or ""]
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
  -- 📷 on the board: RGB565 chunks, then /shot?w=&h=&t= → a PNG; its path typed into window t (no Enter)
  if method == "POST" and route == "/shot/part" then
    local f = io.open("/tmp/deck-shot.raw", p.seq == "0" and "wb" or "ab")
    if f then f:write(body or ""); f:close() end
    return reply("ok", 200)
  end
  if method == "POST" and route == "/shot" then -- saved, not typed: 📎 on the board pastes it where you want
    hs.fs.mkdir(SHOT_DIR)
    local png = SHOT_DIR .. "/" .. os.date("%Y%m%d-%H%M%S") .. ".png"
    local w, h = tonumber(p.w) or 320, tonumber(p.h) or 480
    task("/usr/bin/python3", { "-c", SHOT_PY, "/tmp/deck-shot.raw", tostring(w), tostring(h), png }, function()
      if hs.fs.attributes(png) then lastShot = png end
    end)
    return reply("ok", 200)
  end
  -- 📎: the image on the Mac's clipboard (a copied screenshot) first, else the board's last 📷 → its path typed
  -- into window t, no Enter (words with 🎤, then ✓)
  if method == "POST" and route == "/shot/paste" and id then
    local png = lastShot
    local img = clipImage() and hs.pasteboard.readImage()
    if img then
      hs.fs.mkdir(SHOT_DIR)
      png = SHOT_DIR .. "/clip-" .. os.date("%Y%m%d-%H%M%S") .. ".png"
      if not img:saveToFile(png) then png = nil end
      clipSeen = hs.pasteboard.changeCount() -- pasted: the same clipboard no longer offers 📎
    end
    lastShot = nil
    if png then task(TMUX, { "send-keys", "-t", id, "-l", png .. " " }) end
    return reply(png and "ok" or "nothing", png and 200 or 404)
  end
  -- the board retries each of these until a 200, maybe minutes later (it kept the audio while the Mac was away):
  -- start / pcm at a byte offset / stop are all idempotent
  -- 1029-20xxxx firmware wrote NVS from a PSRAM-stack task after a 200 here → int-wdt reboot loop; answering 503
  -- to that one stuck meeting keeps its uploader retrying (no NVS write) so the fixed firmware can be flashed
  if method == "POST" and (route == "/meet" or route == "/meet/pcm") and p.id == "1793298707" then
    return reply("busy", 503)
  end
  if method == "POST" and route == "/meet" and p.id then
    local id, t = meetName(p.id)
    if p.start == "1" and not meetDone[id] and meetId ~= id then
      hs.fs.mkdir(MEET_DIR)
      meetId, meet.bid = id, p.id
      meet.state, meet.note, meet.lang, meet.t0, meet.lastPcm = "rec", nil, p.lang == "en" and "en" or "uk",
        t > 1700000000 and t or os.time(), os.time()
    elseif p.stop == "1" then meetStop(id, tonumber(p.rate) or 16000, p.fmt, tonumber(p.len)) end
    return reply("ok", 200)
  end
  -- the older firmware (no id: start / pcm?seq= appended / stop): kept until every board runs the flash-log one
  if method == "POST" and route == "/meet" and not p.id then
    if p.start == "1" then
      hs.fs.mkdir(MEET_DIR)
      meetId = os.date("%Y-%m-%d_%H%M%S")
      meet.state, meet.note, meet.lang, meet.t0, meet.lastPcm = "rec", nil, p.lang == "en" and "en" or "uk", os.time(), os.time()
    elseif p.stop == "1" and meetId then meetStop(meetId, tonumber(p.rate) or 22050, "pcm") end
    return reply("ok", 200)
  end
  if method == "POST" and route == "/meet/pcm" and not p.id then
    if not meetId then -- Hammerspoon reloaded mid-meeting: the newest unprocessed .pcm is the one being recorded
      local best, bt
      for f in hs.fs.dir(MEET_DIR) do
        local a = f:match("^(%d%d%d%d%-%d%d%-%d%d_%d%d%d%d%d%d)%.pcm$")
        local m = a and hs.fs.attributes(MEET_DIR .. "/" .. f, "modification")
        if m and (not bt or m > bt) then best, bt = a, m end
      end
      if best then
        meetId = best
        meet.state, meet.lang, meet.t0 = "rec", meet.lang or "uk", os.time({ year = tonumber(best:sub(1, 4)),
          month = tonumber(best:sub(6, 7)), day = tonumber(best:sub(9, 10)), hour = tonumber(best:sub(12, 13)),
          min = tonumber(best:sub(14, 15)), sec = tonumber(best:sub(16, 17)) })
      end
    end
    if meetId then
      local f = io.open(MEET_DIR .. "/" .. meetId .. ".pcm", p.seq == "0" and "wb" or "ab")
      if f then f:write(body or ""); f:close() end
      meet.lastPcm = os.time()
    end
    return reply("ok", 200)
  end
  if method == "POST" and route == "/meet/pcm" and p.id and tonumber(p.off) then
    local path = MEET_DIR .. "/" .. meetName(p.id) .. ".pcm"
    local f = io.open(path, "r+b") or io.open(path, "wb")
    if not f then return reply("can't write", 500) end
    f:seek("set", tonumber(p.off)); f:write(body or ""); f:close()
    meet.lastPcm = os.time()
    return reply("ok", 200)
  end
  if method == "POST" and route == "/mic/pcm" then
    local f = io.open(PCM_FILE, p.seq == "0" and "wb" or "ab")
    if f then f:write(body or ""); f:close() end
    return reply("ok", 200)
  end
  -- the board's pull-down on the Dash: everything the minute timers would bring, now
  -- the board's ✉ panel: the last 20 with their text; opening it marks them seen
  if method == "POST" and route == "/notes" then
    local now = os.time()
    local list = {}
    for i, x in ipairs(notes) do
      list[i] = { app = x.app, title = x.title, subtitle = x.subtitle, body = x.body, ago = math.max(0, now - (x.at or now)) }
    end
    if notes[1] then notesSeen = notes[1].id end
    return reply({ notes = list }, 200, true)
  end
  if method == "POST" and route == "/refresh" then
    refreshJobs(); refreshSessions(); refreshSlow(); refreshGarmin(); refreshHealth()
    return reply("ok", 200)
  end
  if method == "POST" and route == "/mic" then
    if p.clear == "1" then voice = { state = "idle", text = "" }
    elseif p.down == "1" and p.board == "1" then os.remove(PCM_FILE); voice = { state = "rec", text = "", journal = p.j == "1" }
    elseif p.down == "1" then micDown(p.lang)
    elseif p.board == "1" then micBoardUp(tonumber(p.rate) or 22050, p.lang)
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
  M.meetBar = hs.menubar.new():setMenu(meetMenu)
  M.meetTimer = hs.timer.doEvery(1, meetBar)
  meetBar()
  loadDeck()
  refreshHub() -- warm the cache once; later only when the board opens Hub
  M.deckWatcher = hs.pathwatcher.new(DECK_FILE, loadDeck):start()
  refreshSlow()
  M.slowTimer = hs.timer.doEvery(60, refreshSlow) -- statusline.sh (bash + python) + reminders: once a minute is plenty
  refreshSessions()
  refreshProjects() -- warm: /spawn and /projlist answer from it
  refreshFleet()
  memoryState()
  M.sessionTimer = hs.timer.doEvery(3, function() refreshSessions(); refreshNotes() end)
  refreshGarmin(); refreshHealth()
  M.garminTimer = hs.timer.doEvery(15 * 60, function() refreshGarmin(); refreshHealth() end)
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
