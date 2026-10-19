-- pal: a Raycast-style launcher, drawn by pal/index.html in one hs.webview.
--
-- This half owns the window, the data, sqlite and every side effect; the page
-- only renders and handles keys. pal/CONTRACT.md is the law for what crosses
-- between them. The data is the same the chooser palette shows — its entries,
-- its run(), its folders — so the two can never disagree about what a command
-- does; this file only adds the sources a chooser could not hold (zshrc, notes,
-- Todoist, PRs, clipboard, snippets).
--
-- Items cross to JS as plain tables. Anything that has to *do* something stays
-- here in ACT, keyed by item id, because a function cannot ride through JSON.

local M = {}

local palette  = require("modules.palette")
local launcher = require("modules.launcher")

local HOME   = os.getenv("HOME")
local DOT    = HOME .. "/dotfiles"
local FAST   = HOME .. "/code/b2b/rescue-serverless/backend/src/lambdas/api/fast"
local ZETTEL = HOME .. "/zettelkasten/claude_code"
local PATH   = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" .. HOME .. "/.local/bin"

local ACT = {}   -- id → { run=fn, stay=bool, copy=text, preview=fn|string, acts={…}, entry=e }

-- ─── Small helpers ──────────────────────────────────────────────

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function q1(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

-- Percent-encode everything but unreserved chars: obsidian:// reads "+" literally.
local function urlencode(s)
  return (s:gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function ago(t)
  local d = os.time() - t
  if d < 3600 then return math.floor(d / 60) .. "m" end
  if d < 86400 then return math.floor(d / 3600) .. "h" end
  return math.floor(d / 86400) .. "d"
end

-- Background shell, output to a callback. A login zsh so PATH matches the
-- terminal; nothing here may block the webview's main thread.
-- Running tasks are pinned in `running`: an hs.task nothing references gets
-- garbage-collected mid-flight and its callback simply never fires. Output is
-- drained as it streams: without a streaming callback a task writing more than
-- the 64KB pipe buffer (Todoist's task list) blocks forever.
local running = {}
local function sh(cmd, cb, env)
  local out, err, t = {}, {}, nil
  t = hs.task.new("/bin/zsh", function(code, o, e)
    running[t] = nil
    out[#out + 1], err[#err + 1] = o, e
    local ok, x = pcall(cb or function() end, table.concat(out), table.concat(err), code)
    if not ok then print("pal: " .. tostring(x)) end
  end, function(_, o, e)
    out[#out + 1], err[#err + 1] = o, e
    return true
  end, { "-lc", cmd })
  running[t] = true
  if env then
    env.PATH, env.HOME = env.PATH or PATH, env.HOME or HOME
    t:setEnvironment(env)
  end
  t:start()
  return t
end

-- ─── Talking to the page ────────────────────────────────────────

local function send(payload)
  if M._sink then return M._sink(payload) end   -- headless tests
  if M.wv then M.wv:evaluateJavaScript("PAL.recv(" .. hs.json.encode(payload) .. ")") end
end

local function preview(id, body, title, mono)
  send({ type = "preview", id = id, title = title, body = body or "", mono = mono or nil })
end

-- ─── sqlite: usage, learned abbreviations, settings ─────────────
--
-- Outside the repo on purpose: it is per-machine history, not config.

local db = hs.sqlite3.open(HOME .. "/.hammerspoon/pal.db")
db:exec([[
  CREATE TABLE IF NOT EXISTS usage (id TEXT PRIMARY KEY, n INTEGER, last INTEGER);
  CREATE TABLE IF NOT EXISTS abbrev (q TEXT, id TEXT, n INTEGER, PRIMARY KEY (q, id));
  CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT);
]])

local function exec(sql, ...)
  local st = db:prepare(sql)
  if not st then return print("pal: sqlite: " .. db:errmsg()) end
  st:bind_values(...)
  st:step()
  st:finalize()
end

function M.record(id, q)
  exec([[INSERT INTO usage (id, n, last) VALUES (?, 1, ?)
         ON CONFLICT(id) DO UPDATE SET n = n + 1, last = excluded.last]], id, os.time())
  q = trim(q):lower()
  if q ~= "" then
    exec([[INSERT INTO abbrev (q, id, n) VALUES (?, ?, 1)
           ON CONFLICT(q, id) DO UPDATE SET n = n + 1]], q, id)
  end
end

function M.usage()
  local out = {}
  for r in db:nrows("SELECT id, n, last FROM usage") do out[r.id] = { n = r.n, last = r.last } end
  return out
end

function M.abbrev()
  local out = {}
  for r in db:nrows("SELECT q, id, n FROM abbrev") do
    out[r.q] = out[r.q] or {}
    out[r.q][r.id] = r.n
  end
  return out
end

local function kvGet(k, default)
  local st, v = db:prepare("SELECT v FROM kv WHERE k = ?"), nil
  st:bind_values(k)
  for r in st:nrows() do v = r.v end
  st:finalize()
  return v or default
end

local function kvSet(k, v)
  exec("INSERT INTO kv (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v", k, v)
end

-- hs.json.decode raises on anything that is not JSON — an empty body after a
-- network blip, an HTML error page — so every decode goes through here and a
-- bad response becomes an error row instead of a console ERROR.
local function decode(s)
  if type(s) ~= "string" or not s:match("^%s*[%[{]") then return nil end
  local ok, v = pcall(hs.json.decode, s)
  return ok and v or nil
end

-- Favourites for everything that is not a palette command; those keep using
-- palette's own star so both views agree.
local favs = decode(kvGet("fav", "{}")) or {}

-- Every starred id, both kinds, for the page's empty-query ranking.
local function favList()
  local out = {}
  for id in pairs(favs) do out[#out + 1] = id end
  for source in pairs(palette.favourites) do out[#out + 1] = "cmd:" .. source end
  table.sort(out)
  return out
end

local function settings()
  return { type = "settings", theme = kvGet("theme", "night"), header = kvGet("header", "line"), favs = favList() }
end

-- ─── Item construction ──────────────────────────────────────────

-- Register what an item does and return the JSON-safe part. h.acts is the
-- ordered ⌘K list: { {id, t, hk?, fn, stay?}, … }.
local function item(it, h)
  h = h or {}
  h.title = it.t
  ACT[it.id] = h
  if h.acts then
    it.acts = {}
    for _, a in ipairs(h.acts) do it.acts[#it.acts + 1] = { id = a.id, t = a.t, hk = a.hk } end
  end
  local e = h.entry
  if (e and e.fav) or favs[it.id] then it.fav = true end
  return it
end

local function revealActs(path)
  return {
    { id = "reveal", t = "Reveal in Finder", fn = function() hs.execute("open -R " .. q1(path)) end },
    { id = "path",   t = "Copy path", fn = function() hs.pasteboard.setContents(path) end },
  }
end

-- New tmux window in dir; palette.runInTmux wraps the command in single
-- quotes, so anything passed here must not contain one.
local function tmux(cmd, dir, title) return function() palette.runInTmux(cmd, dir, title) end end

-- Run now and stream the result into the preview pane instead of a terminal.
local function runHere(id, cmd, dir)
  return function()
    preview(id, "running…\n$ " .. cmd, cmd, true)
    sh((dir and ("cd " .. q1(dir) .. " && ") or "") .. cmd .. " 2>&1", function(out, _, code)
      preview(id, ("$ %s\n\n%s\n── exit %d ──"):format(cmd, out, code), cmd, true)
    end)
  end
end

-- Paste into whatever had focus before pal opened. hide() already handed it
-- focus back; the extra beat lets the window actually become key first.
local function paster(text)
  return function()
    hs.pasteboard.setContents(text)
    hs.timer.doAfter(0.15, function() hs.eventtap.keyStroke({ "cmd" }, "v", 0) end)
  end
end

local function procItem(pid, cpu, name, f)
  return item({ id = "proc:" .. pid, t = name, s = ("%s%% cpu · pid %s"):format(cpu, pid), ic = "⚙️", f = f, k = "proc" }, {
    copy = tostring(pid),
    run = function()
      local app = hs.application.applicationForPID(tonumber(pid))
      if app then app:activate() else hs.alert.show("pid " .. pid .. " has no window", 1.5) end
    end,
    preview = function(id)
      sh("ps -o pid,ppid,pcpu,pmem,etime,command -p " .. pid, function(out) preview(id, out, name, true) end)
    end,
    acts = { { id = "kill", t = "Kill (TERM)", hk = "⌘⌫", fn = function()
      hs.execute("kill " .. pid); hs.alert.show("killed " .. name, 1.5) end } },
  })
end

-- ─── Sources ────────────────────────────────────────────────────

-- Palette entries: the commands, bindings and recipes palette.lua already finds.
local function cmdItem(e, f)
  local id = "cmd:" .. e.source
  return item({ id = id, t = e.title, s = e.detail or e.category, ic = palette.iconFor(e),
                f = f or "home", k = "cmd", hk = e.chord }, {
    entry = e, copy = e.source,
    run = function() palette.runEntry(e) end,
    preview = table.concat({ e.title, "", "category  " .. (e.category or ""),
      "hotkey    " .. (e.chord or "—"), "source    " .. e.source, e.detail and ("\n" .. e.detail) or "" }, "\n"),
  })
end

local function cmdItems()
  if #palette.entries == 0 then palette.parse() end
  local out = {}
  for _, e in ipairs(palette.entries) do
    if e.category ~= palette.ARCHIVE then out[#out + 1] = cmdItem(e) end
  end
  return out
end

-- Apps with real icons. Encoding ~150 PNGs costs a second or two, so it is
-- paid once per Hammerspoon load and every open after that reads the cache.
local iconURL = {}
local function appItems()
  local out = {}
  M._apps = M._apps or launcher.apps()
  for _, a in ipairs(M._apps) do
    if not iconURL[a.path] then
      local img = launcher.appIcon(a.path)
      iconURL[a.path] = img and img:setSize({ w = 64, h = 64 }):encodeAsURLString() or "🧭"
    end
    out[#out + 1] = item({ id = "app:" .. a.path, t = a.text, s = a.path:match("^(.*)/[^/]+$"),
                           ic = iconURL[a.path], f = "apps", k = "app" }, {
      run = function() hs.application.launchOrFocus(a.path) end,
      preview = a.text .. "\n\n" .. a.path,
      acts = revealActs(a.path),
    })
  end
  return out
end

-- zshrc aliases and functions: the shell's own command list. Parsed from the
-- file, not from a running zsh, for the same reason palette reads init.lua.
local ZSHRC = DOT .. "/zsh/.zshrc"
local SKIP_ZSH = { preexec = true, precmd = true, chpwd = true, zshaddhistory = true, periodic = true }

local function parseZsh()
  local mt = hs.fs.attributes(ZSHRC, "modification")
  if M._zsh and M._zshMt == mt then return M._zsh end
  local defs, comment, fn = {}, nil, nil
  local f = io.open(ZSHRC)
  if not f then return {} end
  for line in f:lines() do
    if fn then
      fn.body[#fn.body + 1] = line
      if line:match("^}") or #fn.body > 40 then fn = nil end
    else
      local c = line:match("^%s*#%s?(.*)$")
      local name, _, cmd = line:match("^alias%s+([%w_%-%.]+)=(['\"])(.-)%2")
      local fname = line:match("^function%s+([%w_%-]+)") or line:match("^([%w_%-]+)%s*%(%)%s*{")
      if name then
        defs[#defs + 1] = { name = name, kind = "alias", cmd = cmd,
          note = line:match("%s#%s*(.+)$") or comment, body = { line } }
      elseif fname then
        local d = { name = fname, kind = "function", note = comment, body = { line } }
        defs[#defs + 1] = d
        if not line:match("}%s*$") then fn = d end
      end
      comment = c and c ~= "" and c or nil
    end
  end
  f:close()
  local out = {}
  for _, d in ipairs(defs) do
    if not d.name:match("^_") and not d.name:match("^prompt") and not SKIP_ZSH[d.name] then
      out[#out + 1] = d
    end
  end
  M._zsh, M._zshMt = out, mt
  return out
end

local function zshItems()
  local out = {}
  for _, d in ipairs(parseZsh()) do
    out[#out + 1] = item({ id = "zsh:" .. d.name, t = d.name,
      s = d.kind == "alias" and d.cmd or (d.note or "function"),
      ic = d.kind == "alias" and "💲" or "ƒ", f = "shell", k = "zsh", kw = d.name }, {
      copy = d.name,
      run = tmux("zsh -ic " .. d.name, HOME, d.name),
      preview = function(id) preview(id, (d.note and ("# " .. d.note .. "\n") or "") .. table.concat(d.body, "\n"), d.name, true) end,
    })
  end
  return out
end

M.THEMES = { "night", "paper", "terminal", "catppuccin-mocha", "tokyo-night", "nord",
             "gruvbox-dark", "dracula", "rose-pine", "solarized-light", "kanagawa", "everforest" }

local function themeItems()
  local out = {}
  for _, name in ipairs(M.THEMES) do
    out[#out + 1] = item({ id = "theme:" .. name, t = "Theme: " .. name, s = "pal colour scheme",
                           ic = "🎨", f = "home", k = "theme" }, {
      stay = true,
      run = function() kvSet("theme", name); send(settings()) end,
      preview = "Switch pal to the " .. name .. " theme (⌘T cycles).",
    })
  end
  return out
end

local function snippetItems()
  local f = io.open(hs.configdir .. "/pal/snippets.json")
  if not f then return {} end
  local list = decode(f:read("a"))
  f:close()
  local out = {}
  for i, s in ipairs(list or {}) do
    out[#out + 1] = item({ id = "snip:" .. (s.name or i), t = s.name, s = s.body:match("^[^\n]*"),
                           ic = "✂️", f = "snippets", k = "snip" },
      { copy = s.body, run = paster(s.body), preview = s.body })
  end
  return out
end

local function clipItems()
  local out = {}
  for _, text in ipairs(hs.settings.get("clipboard_history") or {}) do
    if type(text) == "string" then
      local one = text:gsub("%s+", " ")
      out[#out + 1] = item({ id = "clip:" .. hs.hash.MD5(text), t = one:sub(1, 120), s = #text .. " chars",
                             ic = "📋", f = "clipboard", k = "clip" },
        { copy = text, run = paster(text), preview = function(id) preview(id, text, nil, true) end })
    end
  end
  return out
end

-- Recipes of one justfile, cached by mtime: `just --dump` is a process spawn.
local justCache = {}
local function justItems(path, f)
  local mt = hs.fs.attributes(path, "modification")
  if not mt then return {} end
  local c = justCache[path]
  if not c or c.mt ~= mt then
    local entries = {}
    palette.parseJustfile(path, entries, {})
    c = { mt = mt, entries = entries }
    justCache[path] = c
  end
  local dir, out = path:match("^(.*)/[^/]+$"), {}
  for _, e in ipairs(c.entries) do
    local cmd = ("just --justfile %s %s"):format(path, e.recipe)
    -- Required arguments are asked for in the terminal itself: the webview has
    -- no place to type them, and running without them only prints an error.
    local needs = false
    for _, p in ipairs(e.params or {}) do needs = needs or p.required end
    local full = needs and ("printf \"args: \"; read a; " .. cmd .. " $a") or cmd
    out[#out + 1] = item({ id = "just:" .. path .. ":" .. e.recipe, t = e.title, s = e.detail:gsub("^just %-g", "just"),
                           ic = "▶️", f = f, k = "just", kw = e.recipe }, {
      copy = cmd,
      run = tmux(full, dir, e.recipe),
      preview = function(id)
        sh(("just --justfile %s --show %s"):format(q1(path), e.recipe), function(o, err) preview(id, o ~= "" and o or err, e.recipe, true) end)
      end,
      acts = { { id = "here", t = "Run here (output in preview)", stay = true,
                 fn = runHere("just:" .. path .. ":" .. e.recipe, cmd, dir) } },
    })
  end
  return out
end

local function gitItems(path, f)
  local out = {}
  for _, g in ipairs({ { "status", "git status -sb", "🌿" }, { "log", "git log --oneline -15", "🧾" } }) do
    local id = "git:" .. path .. ":" .. g[1]
    out[#out + 1] = item({ id = id, t = "git " .. g[1], s = g[2], ic = g[3], f = f, k = "sys" }, {
      copy = g[2], run = tmux(g[2], path, "git"),
      preview = function() runHere(id, g[2], path)() end,
    })
  end
  return out
end

-- palette.FOLDERS holds the hand-written per-folder commands; reuse by name.
local function paletteFolder(name)
  for _, pf in ipairs(palette.FOLDERS) do if pf.name == name then return pf end end
end

local function folderCmds(name, f)
  local pf, out = paletteFolder(name), {}
  for _, c in ipairs(pf and pf.cmds or {}) do
    local full = pf.dir and ("just --justfile justfile.v2 lead " .. c[2]) or c[2]
    out[#out + 1] = item({ id = "fcmd:" .. f .. ":" .. c[2], t = c[1]:gsub("^%S+%s+", ""), s = c[3],
                           ic = c[1]:match("^(%S+)"), f = f, k = "cmd" }, {
      copy = full, run = tmux(full, pf.dir or pf.path, c[2]),
      preview = "$ " .. full .. "\n\n" .. c[3],
      acts = { { id = "here", t = "Run here (output in preview)", stay = true,
                 fn = runHere("fcmd:" .. f .. ":" .. c[2], full, pf.dir or pf.path) } },
    })
  end
  return out
end

-- palette.EXTRA builds chooser rows; keep their text and their tmux command.
local function extraItems(kind, f, k, acts)
  local out = {}
  for _, r in ipairs(palette.EXTRA[kind](launcher)) do
    local sub = type(r.subText) == "userdata" and r.subText:getString() or tostring(r.subText or "")
    local slug = r.tmux:match("rem%-show (%S+)$")
    out[#out + 1] = item({ id = k .. ":" .. (slug or r.title), t = r.text, s = trim(sub),
                           ic = "🔔", f = f, k = k }, {
      copy = r.tmux, run = tmux(r.tmux, r.dir, r.title),
      preview = slug and function(id)
        sh(HOME .. "/.claude/reminders.sh show " .. slug, function(o, e) preview(id, o ~= "" and o or e, r.text) end)
      end or (r.text .. "\n\n" .. sub),
      acts = acts and acts(slug, r) or nil,
    })
  end
  return out
end

local function reminderItems()
  return extraItems("reminders", "reminders", "rem", function(slug)
    return {
      { id = "show", t = "Show here", stay = true, fn = function()
          sh(HOME .. "/.claude/reminders.sh show " .. slug, function(o) preview("rem:" .. slug, o, slug) end) end },
      { id = "done", t = "Mark done", fn = function()
          hs.alert.show(trim(hs.execute(HOME .. "/.claude/reminders.sh done " .. slug)), 1.5) end },
    }
  end)
end

-- Same rows as palette.EXTRA.projects, but one `tmux ls` instead of a login
-- shell per project: that loop costs ~4s for 15 projects, far too slow here.
local function projectItems()
  local out = folderCmds("projctl", "projects")
  local up = {}
  for name in (hs.execute("/opt/homebrew/bin/tmux ls -F '#S' 2>/dev/null") or ""):gmatch("[^\n]+") do up[name] = true end
  local f = io.open(HOME .. "/code/projctl/registry.conf")
  if not f then return out end
  for line in f:lines() do
    local name, _, session, port, _, on = line:match("^([^#|][^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(%d)")
    if name then
      local run, attach = up[session], "just -g proj attach " .. name
      out[#out + 1] = item({ id = "proj:" .. name, t = name, ic = run and "🟢" or "⚪", f = "projects", k = "proj",
        s = (run and "running" or "stopped") .. (port ~= "" and ("  :" .. port) or "") .. (on == "1" and "  · auto-start" or "  · manual") }, {
        copy = attach, run = tmux(attach, HOME, name),
        preview = ("%s\n\nsession  %s\nport     %s\n%s\n\nEnter attaches"):format(name, session, port ~= "" and port or "—",
          run and "● running" or "○ stopped"),
      })
    end
  end
  f:close()
  return out
end

local function rescueItems()
  local out = folderCmds("rescue-serverless", "rescue")
  for _, it in ipairs(justItems(FAST .. "/justfile.v2", "rescue")) do out[#out + 1] = it end
  return out
end

local function zettelItems()
  local out = {}
  local list = hs.execute(("find %s -name '*.md' -type f -print0 | xargs -0 stat -f '%%m\t%%N' | sort -rn | head -40")
    :format(q1(ZETTEL))) or ""
  for mt, path in list:gmatch("(%d+)\t([^\n]+)") do
    local rel = path:sub(#ZETTEL + 2)
    out[#out + 1] = item({ id = "note:" .. path, t = rel:match("([^/]+)%.md$"),
                           s = (rel:match("^(.*)/") or "") .. "  · " .. ago(tonumber(mt)), ic = "🗒", f = "zettel", k = "note" }, {
      copy = path,
      run = function() hs.urlevent.openURL("obsidian://open?path=" .. urlencode(path)) end,
      preview = function(id)
        local fh = io.open(path)
        local body = fh and fh:read(4000) or ""
        if fh then fh:close() end
        preview(id, body, rel)
      end,
      acts = revealActs(path),
    })
  end
  return out
end

local SYSTEM_CATS = { System = true, Shell = true, Trackpad = true, Screenshot = true }
local function systemItems()
  if #palette.entries == 0 then palette.parse() end
  local out = {}
  for _, e in ipairs(palette.entries) do
    if e.kind == "action" and SYSTEM_CATS[e.category] then out[#out + 1] = cmdItem(e, "system") end
  end
  local ps = hs.execute("ps -Ao pid=,pcpu=,comm= -r | head -15") or ""
  for pid, cpu, comm in ps:gmatch("%s*(%d+)%s+([%d%.]+)%s+([^\n]+)") do
    out[#out + 1] = procItem(pid, cpu, comm:match("([^/]+)$"), "system")
  end
  return out
end

-- ─── Network-backed folders (async) ─────────────────────────────

-- dotfiles/.env first (the documented home of the token), then the
-- Hammerspoon one the widgets use.
local function todoistToken()
  local f = io.open(DOT .. "/.env")
  if f then
    for line in f:lines() do
      local v = line:match("^%s*export%s+TODOIST_TOKEN%s*=%s*(.+)$") or line:match("^%s*TODOIST_TOKEN%s*=%s*(.+)$")
      if v then f:close(); return (trim(v):gsub("^[\"']", ""):gsub("[\"']$", "")) end
    end
    f:close()
  end
  return require("modules.env").get("TODOIST_TOKEN")
end

-- The token rides in the environment, so the echoed command is exactly the one
-- that runs and is copy-paste ready in a shell that has $TODOIST_TOKEN.
-- -I (--ignore-stdin) matters: hs.task's stdin is a pipe, and xh reads a piped
-- stdin as a body and silently turns every GET into a POST.
local function todoist(cmd, cb)
  print("━━━ xh ━━━  " .. cmd)
  return sh(cmd, cb, { TODOIST_TOKEN = todoistToken() })
end

local TD = "https://api.todoist.com/api/v1/tasks"

local function fetchTodoist(done)
  todoist(('xh -bI "%s?limit=200" "Authorization:Bearer $TODOIST_TOKEN"'):format(TD), function(out, err)
    local data = decode(out)
    local tasks = type(data) == "table" and data.results or nil
    if not tasks then
      return done({ item({ id = "task:error", t = "Todoist: no tasks", s = trim(err ~= "" and err or out):sub(1, 200),
                           ic = "⚠️", f = "todoist", k = "task" }, { preview = out .. "\n" .. err }) })
    end
    -- ponytail: first page only (200); follow next_cursor if the inbox ever grows past it
    local today = os.date("%Y-%m-%d")
    local function due(t) return t.due and t.due.date and t.due.date:sub(1, 10) or "9999" end
    table.sort(tasks, function(a, b)
      if due(a) ~= due(b) then return due(a) < due(b) end
      return (a.priority or 1) > (b.priority or 1)
    end)
    local out2 = {}
    for _, t in ipairs(tasks) do
      local d = due(t)
      local url = "https://todoist.com/app/task/" .. t.id
      out2[#out2 + 1] = item({ id = "task:" .. t.id, t = t.content,
        s = trim(((d ~= "9999") and ((t.due.string or d) .. "  ") or "") .. table.concat(t.labels or {}, " ")),
        ic = d < today and "🔴" or (d == today and "🟠" or "☑️"), f = "todoist", k = "task" }, {
        copy = url,
        run = function() hs.urlevent.openURL(url) end,
        preview = ("%s\n\ndue  %s\npriority  p%d\nlabels  %s\n%s\n\n%s"):format(t.content,
          d ~= "9999" and d or "—", 5 - (t.priority or 1), table.concat(t.labels or {}, ", "), url, t.description or ""),
        acts = { { id = "close", t = "Complete", fn = function()
          todoist(('xh -bI POST "%s/%s/close" "Authorization:Bearer $TODOIST_TOKEN"'):format(TD, t.id),
            function() hs.alert.show("✓ " .. t.content, 1.5) end) end } },
      })
    end
    done(out2)
  end)
end

local function fetchPRs(done)
  sh("gh search prs --author=@me --state=open --limit 50 --json number,title,repository,url", function(out, err)
    local prs = decode(out)
    if type(prs) ~= "table" then
      return done({ item({ id = "pr:error", t = "gh: no PRs", s = trim(err):sub(1, 200), ic = "⚠️", f = "prs", k = "pr" }, {}) })
    end
    local list = {}
    for _, p in ipairs(prs) do
      list[#list + 1] = item({ id = "pr:" .. p.url, t = p.title, s = ("%s#%d"):format(p.repository.name, p.number),
                               ic = "🔀", f = "prs", k = "pr" }, {
        copy = p.url,
        run = function() hs.urlevent.openURL(p.url) end,
        preview = function(id) sh("gh pr view " .. q1(p.url), function(o, e) preview(id, o ~= "" and o or e, p.title) end) end,
      })
    end
    done(list)
  end)
end

-- ─── Folders ────────────────────────────────────────────────────

M.FOLDERS = {
  { id = "home",      name = "Home",      icon = "🏠" },
  { id = "apps",      name = "Apps",      icon = "🧭", view = "tiles", build = appItems },
  { id = "dotfiles",  name = "dotfiles",  icon = "📁", path = DOT },
  { id = "rescue",    name = "rescue",    icon = "🚑", path = HOME .. "/code/b2b/rescue-serverless", build = rescueItems },
  { id = "projects",  name = "projects",  icon = "🛠", path = HOME .. "/code/projctl", noGit = true, build = projectItems },
  { id = "reminders", name = "reminders", icon = "🔔", build = reminderItems },
  { id = "zettel",    name = "zettel",    icon = "🗂", path = ZETTEL, build = zettelItems },
  { id = "todoist",   name = "todoist",   icon = "☑️", fetch = fetchTodoist },
  { id = "prs",       name = "PRs",       icon = "🔀", fetch = fetchPRs },
  { id = "system",    name = "system",    icon = "🖥", build = systemItems },
  { id = "shell",     name = "shell",     icon = "💻", build = zshItems },
  { id = "clipboard", name = "clipboard", icon = "📋", build = clipItems },
  { id = "snippets",  name = "snippets",  icon = "✂️", build = snippetItems },
}
local byId = {}
for _, f in ipairs(M.FOLDERS) do byId[f.id] = f end

M._cache = {}   -- folder id → last items, so Home and async folders have something at once

-- Folder-specific items, then the generic ones every folder with a path gets:
-- its justfile's recipes and, for a repo, git status/log.
local function folderItems(f)
  local out = f.build and f.build() or {}
  if f.path then
    for _, it in ipairs(justItems(f.path .. "/justfile", f.id)) do out[#out + 1] = it end
    if not f.noGit then for _, it in ipairs(gitItems(f.path, f.id)) do out[#out + 1] = it end end
  end
  M._cache[f.id] = out
  return out
end

-- palette's statusLine, also cut into chips for the header's chip mode.
local function status(f, n)
  local line
  if f.path then
    line = palette.statusLine({ icon = f.icon, name = f.name, path = f.path, noGit = f.noGit })
  else
    line = ("%s %s  ·  %d items"):format(f.icon, f.name, n)
  end
  local chips = {}
  for part in (line .. "  "):gmatch("(.-)%s%s+") do
    local c = trim(part)
    if c ~= "" and c ~= "·" then chips[#chips + 1] = c end
  end
  return { line = line, chips = chips }
end

-- Home: commands, apps, shell, themes, snippets — the cheap, cached sets — plus
-- whatever other folders have already loaded. Dedup by id: system re-lists
-- some palette commands.
function M.homeItems()
  local seen, out = {}, {}
  local function add(list)
    for _, it in ipairs(list) do
      if not seen[it.id] then seen[it.id], out[#out + 1] = true, it end
    end
  end
  M._static = M._static or {}
  if not M._static.cmd then M._static.cmd = cmdItems() end
  add(M._static.cmd)
  add(appItems())
  add(zshItems())
  add(themeItems())
  add(snippetItems())
  for _, f in ipairs(M.FOLDERS) do
    if f.id ~= "home" and f.id ~= "clipboard" and M._cache[f.id] then add(M._cache[f.id]) end
  end
  M._cache.home = out
  return out
end

function M.folder(id)
  local f = byId[id] or byId.home
  if f.id == "home" then
    local items = M.homeItems()
    return send({ type = "folder", id = "home", items = items, status = status(f, #items) })
  end
  if f.fetch then
    local cached = M._cache[f.id] or {}
    send({ type = "folder", id = f.id, items = cached, status = status(f, #cached) })
    return f.fetch(function(items)
      M._cache[f.id] = items
      send({ type = "folder", id = f.id, items = items, status = status(f, #items) })
    end)
  end
  local items = folderItems(f)
  send({ type = "folder", id = f.id, items = items, status = status(f, #items) })
end

-- ─── Keywords ───────────────────────────────────────────────────

M.KEYWORDS = {
  { kw = "g",   t = "Google",           url = "https://www.google.com/search?q=%s" },
  { kw = "gh",  t = "GitHub search",    url = "https://github.com/search?q=%s&type=repositories" },
  { kw = "yt",  t = "YouTube",          url = "https://www.youtube.com/results?search_query=%s" },
  { kw = "w",   t = "Wikipedia",        url = "https://en.wikipedia.org/w/index.php?search=%s" },
  { kw = "tr",  t = "Google Translate", url = "https://translate.google.com/?sl=auto&tl=en&text=%s" },
  { kw = "lin", t = "Linear search",    url = "https://linear.app/search?q=%s" },
  { kw = "aws", t = "AWS console",      url = "https://console.aws.amazon.com/console/home#search=%s" },
  { kw = "$",   t = "Shell command (output in preview)" },
  { kw = "?",   t = "Ask Claude" },
  { kw = "f",   t = "Find files (dotfiles, zettelkasten, code)" },
  { kw = ":",   t = "Who listens on a port (:8000)" },
  { kw = "p",   t = "Processes by name" },
  { kw = "rem", t = "Add a reminder" },
  { kw = "td",  t = "Add to Todoist" },
}

local claudeBin
local function claude()
  -- the real binary, never the zsh function of the same name; ~/.local/bin is
  -- only on PATH once .zshrc runs, hence the interactive fallback
  claudeBin = claudeBin or trim(hs.execute("/bin/zsh -lc 'whence -p claude'"))
  if claudeBin == "" then claudeBin = trim(hs.execute("/bin/zsh -ic 'whence -p claude' 2>/dev/null")):match("[^\n]*$") end
  return claudeBin
end

local function provide(q, items) send({ type = "provide", q = q, items = items }) end

-- One query task at a time: typing "f foo" fires for f, fo, foo, and only the
-- last answer matters (the page drops stale q anyway).
local function single(t)
  if M._qtask and M._qtask:isRunning() then M._qtask:terminate() end
  M._qtask = t
end

local function slugify(s)
  return (s:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""):sub(1, 40))
end

function M.query(q)
  local cmd = q:match("^%$%s*(.-)%s*$")
  if cmd and cmd ~= "" then
    local id = "sh:" .. cmd
    return provide(q, { item({ id = id, t = "Run: " .. cmd, s = "zsh -lc · output in preview", ic = "💻", k = "sys" }, {
      stay = true, copy = cmd, run = runHere(id, cmd), preview = "Enter runs it here:\n\n$ " .. cmd,
      acts = { { id = "tmux", t = "Run in tmux", fn = tmux(cmd, HOME, "$") } },
    }) })
  end

  local ask = q:match("^%?%s*(.-)%s*$")
  if ask and ask ~= "" then
    local id = "ask:" .. ask
    return provide(q, { item({ id = id, t = "Ask Claude: " .. ask, s = "claude -p · answer in preview", ic = "✨", k = "sys" }, {
      stay = true, copy = ask, preview = "Enter asks Claude:\n\n" .. ask,
      run = function()
        if claude() == "" then return preview(id, "claude binary not found (whence -p claude)", ask) end
        preview(id, "thinking…", ask)
        local t
        t = hs.task.new(claude(), function(_, out, err)
          running[t] = nil
          preview(id, trim(out ~= "" and out or err), ask)
        end, { "-p", ask })
        running[t] = true
        t:start()
      end,
    }) })
  end

  local name = q:match("^f%s+(.-)%s*$")
  if name and name ~= "" then
    return single(sh(("fd -i --max-results 40 -- %s %s %s %s"):format(q1(name), DOT, HOME .. "/zettelkasten", HOME .. "/code"),
      function(out)
        local items = {}
        for line in out:gmatch("[^\n]+") do
          local path = line:gsub("/$", "")
          items[#items + 1] = item({ id = "file:" .. path, t = path:match("([^/]+)$"), s = path:gsub("^" .. HOME, "~"),
                                     ic = "📄", k = "file" }, {
            copy = path,
            run = function()
              if path:match("^" .. HOME .. "/zettelkasten/.*%.md$") then
                hs.urlevent.openURL("obsidian://open?path=" .. urlencode(path))
              else hs.execute("open " .. q1(path)) end
            end,
            preview = function(id)
              sh("head -c 4000 " .. q1(path) .. " 2>/dev/null || ls -la " .. q1(path), function(o) preview(id, o, path, true) end)
            end,
            acts = revealActs(path),
          })
        end
        provide(q, items)
      end))
  end

  local port = q:match("^:(%d+)$")
  if port then
    return single(sh("lsof -nP -iTCP:" .. port .. " -sTCP:LISTEN", function(out)
      local items = {}
      for comm, pid in out:gmatch("\n(%S+)%s+(%d+)") do items[#items + 1] = procItem(pid, "?", comm .. " :" .. port) end
      provide(q, items)
    end))
  end

  local pname = q:match("^p%s+(.-)%s*$")
  if pname and pname ~= "" then
    local items = {}
    for pid, cpu, comm in (hs.execute("ps -Ao pid=,pcpu=,comm= -r") or ""):gmatch("%s*(%d+)%s+([%d%.]+)%s+([^\n]+)") do
      if comm:lower():find(pname:lower(), 1, true) and #items < 40 then
        items[#items + 1] = procItem(pid, cpu, comm:match("([^/]+)$"))
      end
    end
    return provide(q, items)
  end

  local rem = q:match("^rem%s+(.-)%s*$")
  if rem and rem ~= "" then
    local slug = slugify(rem)
    return provide(q, { item({ id = "remadd:" .. slug, t = "Add reminder: " .. rem, s = slug, ic = "🔔", k = "rem" }, {
      run = function()
        -- stdin is the body; empty, or cat waits forever
        hs.alert.show(trim(hs.execute(("%s/.claude/reminders.sh add %s %s </dev/null"):format(HOME, q1(slug), q1(rem)))), 1.5)
      end,
    }) })
  end

  local td = q:match("^td%s+(.-)%s*$")
  if td and td ~= "" then
    return provide(q, { item({ id = "tdadd:" .. td, t = "Add to Todoist: " .. td, s = "POST /api/v1/tasks", ic = "☑️", k = "task" }, {
      run = function()
        todoist(('xh -bI POST "%s" "Authorization:Bearer $TODOIST_TOKEN" content=%s'):format(TD, q1(td)), function(out)
          local t = decode(out)
          hs.alert.show(t and t.id and ("☑️ added: " .. td) or ("Todoist: " .. out:sub(1, 120)), 2)
        end)
      end,
    }) })
  end
end

-- ─── Window ─────────────────────────────────────────────────────

local function init()
  local items = M.homeItems()
  local folders = {}
  for _, f in ipairs(M.FOLDERS) do folders[#folders + 1] = { id = f.id, name = f.name, icon = f.icon, view = f.view } end
  local payload = { type = "init", folders = folders, items = items, usage = M.usage(), abbrev = M.abbrev(),
                    keywords = M.KEYWORDS, themes = M.THEMES }
  local s = settings()
  payload.settings = { theme = s.theme, header = s.header }
  payload.favs = s.favs
  send(payload)
  -- Warm the network folders so Home and their first open are not empty;
  -- only the cache is filled, the page is not told until it asks.
  for _, f in ipairs(M.FOLDERS) do
    if f.fetch then f.fetch(function(list) M._cache[f.id] = list end) end
  end
end

function M.hide(refocus)
  if not (M.wv and M.wv:isVisible()) then return end
  M.wv:hide()
  if refocus and M._prev then M._prev:focus() end
end

-- Stays open: the page re-ranks from the favs echoed back in settings.
local function toggleFav(id, h)
  if h.entry then
    palette.toggleFavourite(h.entry)
  else
    favs[id] = (not favs[id]) or nil
    kvSet("fav", hs.json.encode(favs))
  end
  send(settings())
end

-- Every side effect happens after the window is gone (and focus handed back),
-- so typing, pasting and keystroke replays land where they should.
function M.run(id, q, action)
  local h = ACT[id]
  if not h then return hs.alert.show("pal: unknown item " .. tostring(id), 2) end
  action = action or "run"
  M.record(id, q)
  if action == "copy" then
    hs.pasteboard.setContents(h.copy or h.title or id)
    return M.hide(true)
  end
  if action == "fav" or action == "favourite" then return toggleFav(id, h) end
  local fn, stay = h.run, h.stay
  if action ~= "run" then
    for _, a in ipairs(h.acts or {}) do if a.id == action then fn, stay = a.fn, a.stay end end
  end
  if not fn then return end
  if stay then return fn() end
  M.hide(true)
  hs.timer.doAfter(0.05, function()
    local ok, err = pcall(fn)
    if not ok then hs.alert.show("pal: " .. tostring(err), 4) end
  end)
end

function M.previewOf(id)
  local h = ACT[id]
  if not h or not h.preview then return preview(id, "", nil) end
  if type(h.preview) == "function" then return h.preview(id) end
  preview(id, h.preview)
end

-- The JS → Lua message table from CONTRACT.md.
function M.handle(m)
  local t = m.type
  if t == "ready" then init()
  elseif t == "folder" then M.folder(m.id)
  elseif t == "preview" then M.previewOf(m.id)
  elseif t == "run" then M.run(m.id, m.q, m.action)
  elseif t == "query" then M.query(m.q or "")
  elseif t == "set" then
    if m.k == "theme" or m.k == "header" then kvSet(m.k, tostring(m.v)) end
    send(settings())
  elseif t == "hide" then M.hide(true)
  elseif t == "copy" then hs.pasteboard.setContents(m.text or ""); M.hide(true)
  elseif t == "open" then M.hide(false); hs.urlevent.openURL(m.url)
  end
end

local W, H = 880, 540

local function create()
  local uc = hs.webview.usercontent.new("pal")
  uc:setCallback(function(msg)
    local ok, err = pcall(M.handle, msg.body or {})
    if not ok then print("pal: " .. tostring(err)) end
  end)
  M.wv = hs.webview.new({ x = 0, y = 0, w = W, h = H }, { developerExtrasEnabled = true }, uc)
    :windowStyle({ "borderless" })
    :transparent(true)
    :allowTextEntry(true)
    :shadow(true)
    :level(hs.drawing.windowLevels.modalPanel)
    :closeOnEscape(false)
    :deleteOnClose(false)
    :windowCallback(function(action, _, focused)
      -- Clicking elsewhere hides without refocusing: the click chose a new window.
      if action == "focusChange" and not focused then M.hide(false) end
    end)
  M.wv:url("file://" .. hs.configdir .. "/pal/index.html")
  M._uc = uc
end

function M.toggle()
  if M.wv and M.wv:isVisible() then return M.hide(true) end
  if not M.wv then create() end
  M._prev = hs.window.focusedWindow()
  local screen = (M._prev and M._prev:screen() or hs.screen.mainScreen()):frame()
  M.wv:frame({ x = screen.x + (screen.w - W) / 2, y = screen.y + (screen.h - H) / 2.6, w = W, h = H })
  M.wv:show()
  local win = M.wv:hswindow()
  if win then win:focus() end
  send({ type = "open" })
end

return M
