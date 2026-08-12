-- Command palette over everything this config can do.
--
-- Two sources, because neither is enough alone:
--
--   init.lua   — every binding, and the comments above them. hs.hotkey knows
--                which chords are live but carries no description at all, so
--                the best it could ever print is "⌥⇧O".
--   modules/   — every zero-argument M.* function, including the many that
--                were never given a chord. Those are commands too; they were
--                simply unreachable until now.
--
-- Both are read from the files rather than from the running state, so nothing
-- has to be registered by hand and nothing can drift: edit a comment or add a
-- function, reload, and the palette says the new thing.
--
-- The list is browsed by category first — pick "Window Management" and you get
-- its commands and nothing else — with a flat "All commands" for when you would
-- rather just type. Choosing a bound command replays its chord, so whatever the
-- binding really does (guard included) happens exactly as if typed; choosing an
-- unbound one calls the function.

local M = {}

local SYMBOL    = { cmd = "⌘", ctrl = "⌃", alt = "⌥", shift = "⇧" }
local MOD_ORDER = { "ctrl", "alt", "shift", "cmd" }
local KEY_LABEL = { ["return"] = "↩", space = "Space", delete = "⌫",
                    left = "←", right = "→", up = "↑", down = "↓" }

-- Plumbing, not commands: these run themselves at load time or need arguments
-- we cannot invent, and listing them would bury the things worth picking.
local INTERNAL = {
  init = true, start = true, stop = true, load = true, save = true,
  parse = true, buildChoices = true, setup = true, bind = true,
}

-- Verbs that mean nothing alone: "Toggle" what? The module is the missing
-- object ("dropdown.toggle" → "Toggle dropdown"), while "windows.maximize"
-- already says everything and gains nothing from it.
local NEEDS_OBJECT = { toggle = true, show = true, open = true, hide = true, find = true }

M.entries    = {}   -- flat list of every command
M.categories = {}   -- ordered { name = …, items = { entry, … } }

-- ─── Text helpers ───────────────────────────────────────────────

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function words(s)
  local w = s:gsub("(%l)(%u)", "%1 %2"):gsub("_", " "):lower()
  return w:sub(1, 1):upper() .. w:sub(2)
end

local function titleCase(s)
  return (s:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

-- "apps.toggle(\"Ghostty\")" → "Toggle Ghostty"; "system.toggleDarkMode" →
-- "Toggle dark mode". The call already says what it does — it needs unpacking,
-- not quoting.
local function humanize(action)
  if not action or action == "" or action:match("^function") then return nil end
  local arg = action:match('"([^"]+)"')
  local mod, fn = action:match("([%w_]+)%.([%w_]+)")
  fn = fn or action:match("^([%w_]+)")
  if not fn then return nil end
  if arg then return words(fn) .. " " .. (arg:gsub("_", " ")) end
  if mod and NEEDS_OBJECT[fn:lower()] then return words(fn) .. " " .. mod:lower() end
  return words(fn)
end

local function chordOf(mods, key)
  local set = {}
  for _, m in ipairs(mods) do set[m] = true end
  local out = {}
  for _, m in ipairs(MOD_ORDER) do
    if set[m] then out[#out + 1] = SYMBOL[m] end
  end
  return table.concat(out) .. (KEY_LABEL[key:lower()] or key:upper())
end

-- ─── Source 1: bindings in init.lua ─────────────────────────────

local function parseMods(expr, named)
  expr = trim(expr)
  if named[expr] then return named[expr] end
  local mods = {}
  for m in expr:gmatch('"([%a]+)"') do mods[#mods + 1] = m:lower() end
  return mods
end

-- Comments name their key either bare ("I = pick a display…") or spelled out
-- with the whole chord ("ctrl+alt+cmd+Space = jump to any window").
local function namesKey(token, key)
  token, key = token:lower(), key:lower()
  if token == key then return true end
  return token:match("%+" .. key:gsub("(%W)", "%%%1") .. "$") ~= nil
end

-- A comment about this exact key is the best description there is. Anything
-- else above a binding tends to be a heading for the group below it ("Halves"
-- over four arrow keys), which reads worse than the unpacked call.
local function describe(comments, key, action)
  for _, c in ipairs(comments) do
    local k, rest = c:match("^(%S+)%s*=%s*(.+)$")
    if k and namesKey(k, key) then return trim(rest) end
  end
  return humanize(action) or (#comments > 0 and comments[1]) or action
end

local function parseInit(path, out, sectionOfModule, bound)
  local f = io.open(path, "r")
  if not f then return end
  local named, section, comments = {}, "General", {}

  for line in f:lines() do
    local var, body = line:match("^%s*local%s+([%w_]+)%s*=%s*{(.-)}")
    if var and body:find('"') then
      local mods = {}
      for m in body:gmatch('"([%a]+)"') do mods[#mods + 1] = m:lower() end
      if #mods > 0 then named[var] = mods end
    end

    if line:match("^%s*%-%-") then
      local text = trim(line:gsub("^%s*%-%-%s?", ""))
      -- Section rules are drawn with U+2500; Lua patterns are byte-wise and
      -- cannot match it as a run, so strip the character instead.
      if text:find("─", 1, true) then
        section, comments = trim((text:gsub("─", ""))), {}
      elseif text ~= "" then
        comments[#comments + 1] = text
      end
    elseif trim(line) == "" then
      comments = {}
    end

    -- The brace form must be tried first: a non-greedy capture would otherwise
    -- stop at the first comma in { "ctrl", "alt", "cmd" } and read "alt" as the key.
    local modExpr, key, action =
      line:match("bind%s*%(%s*({.-})%s*,%s*\"([^\"]+)\"%s*,%s*(.-)%s*%)%s*$")
    if not modExpr then
      modExpr, key, action =
        line:match("bind%s*%(%s*([%w_]+)%s*,%s*\"([^\"]+)\"%s*,%s*(.-)%s*%)%s*$")
    end

    if modExpr and key then
      local mods = parseMods(modExpr, named)
      if #mods > 0 then
        action = action or ""
        local mod, fn = action:match("([%w_]+)%.([%w_]+)")
        if mod and fn then
          bound[mod .. "." .. fn] = true
          sectionOfModule[mod] = sectionOfModule[mod] or section
        end
        out[#out + 1] = {
          kind     = "key",
          title    = describe(comments, key, action),
          category = section,
          chord    = chordOf(mods, key),
          source   = action ~= "" and action or "—",
          mods     = mods,
          key      = key,
        }
        comments = {}
      end
    end
  end
  f:close()
end

-- ─── Source 2: every zero-arg function in modules/ ──────────────
--
-- Read, never required: requiring a module to look at it would run its
-- top-level code as a side effect of merely listing commands.

local function parseModule(path, name, out, sectionOfModule, bound)
  local f = io.open(path, "r")
  if not f then return end
  local comments = {}

  for line in f:lines() do
    if line:match("^%s*%-%-") then
      local text = trim(line:gsub("^%s*%-%-%s?", ""))
      if text ~= "" and not text:find("─", 1, true) then comments[#comments + 1] = text end
    elseif trim(line) == "" then
      comments = {}
    end

    -- Both declaration styles: "function M.x()" and "M.x = function()"
    local fn = line:match("^function%s+M%.([%w_]+)%s*%(%s*%)")
             or line:match("^M%.([%w_]+)%s*=%s*function%s*%(%s*%)")
    if fn then
      local full = name .. "." .. fn
      -- Predicates and accessors answer a question rather than doing anything,
      -- so there is nothing to pick them for.
      local isGetter = fn:match("^get%u") or fn:match("^is%u") or fn:match("^has%u")
      if not INTERNAL[fn] and not bound[full] and not fn:match("^_") and not isGetter then
        out[#out + 1] = {
          kind     = "fn",
          title    = humanize(full) or words(fn),
          category = sectionOfModule[name] or titleCase(name),
          chord    = nil,
          source   = full .. "()",
          detail   = #comments > 0 and comments[1] or nil,
          module   = name,
          fn       = fn,
        }
      end
      comments = {}
    end
  end
  f:close()
end

-- ─── Source 3: just recipes ─────────────────────────────────────
--
-- The other half of this setup lives in ~/dotfiles/.justdir/global.just, and it
-- is the half with the long tail — disk cleanup, git sweeps, cheatsheets, the
-- mirror commands. `just --dump --dump-format json` hands over names, doc
-- comments and groups exactly as written, so nothing has to be re-described.

M.justfile = os.getenv("HOME") .. "/dotfiles/.justdir/global.just"

local function parseJust(entries)
  local probe = io.open(M.justfile, "r")
  if not probe then return end
  probe:close()

  local out, ok = hs.execute(
    ("just --justfile %s --dump --dump-format json 2>/dev/null"):format(M.justfile), true)
  if not ok or not out or out == "" then return end
  local decoded, data = pcall(hs.json.decode, out)
  if not decoded or type(data) ~= "table" or type(data.recipes) ~= "table" then return end

  local names = {}
  for name in pairs(data.recipes) do names[#names + 1] = name end
  table.sort(names)

  for _, name in ipairs(names) do
    local r = data.recipes[name]
    local private, group = name:sub(1, 1) == "_", nil
    for _, attr in ipairs(r.attributes or {}) do
      if type(attr) == "table" and attr.group then group = attr.group
      elseif attr == "private" then private = true end
    end
    if not private then
      local doc = r.doc
      entries[#entries + 1] = {
        kind     = "just",
        title    = (doc and doc ~= "" and doc) or name,
        category = "just · " .. (group or "misc"),
        source   = "just -g " .. name,
        detail   = "just -g " .. name,
        recipe   = name,
      }
    end
  end
end

-- ─── Build ──────────────────────────────────────────────────────

function M.parse()
  local dir = hs.configdir
  local entries, sectionOfModule, bound = {}, {}, {}

  parseInit(dir .. "/init.lua", entries, sectionOfModule, bound)

  local names = {}
  for file in hs.fs.dir(dir .. "/modules") do
    local n = file:match("^([%w_]+)%.lua$")
    if n then names[#names + 1] = n end
  end
  table.sort(names)
  for _, n in ipairs(names) do
    parseModule(dir .. "/modules/" .. n .. ".lua", n, entries, sectionOfModule, bound)
  end

  parseJust(entries)

  -- Remember where each command started out, so equally-used ones keep the
  -- order the files give them instead of shuffling on every parse.
  for i, e in ipairs(entries) do
    e.order = i
    e.fav   = M.favourites[e.source] or false
    if M.archived[e.source] then
      e.category = M.ARCHIVE
    elseif M.moved[e.source] then
      e.category = M.moved[e.source]
    end
  end

  local cats, index = {}, {}
  for _, e in ipairs(entries) do
    local c = index[e.category]
    if not c then
      c = { name = e.category, items = {} }
      index[e.category], cats[#cats + 1] = c, c
    end
    c.items[#c.items + 1] = e
  end

  M.entries, M.categories = entries, cats
  M.sort()
  return entries
end

-- ─── Most-used first ────────────────────────────────────────────
--
-- Counted per command and kept in hs.settings, so the ranking survives reloads
-- and restarts. Ties fall back to file order — without that, everything unused
-- would reshuffle each time and the list would never feel familiar.

local USES_KEY = "PaletteUses"
M.uses = hs.settings.get(USES_KEY) or {}

-- Hand-made arrangement, kept beside the automatic ranking: a star pins a
-- command to the top, the archive hides one without deleting it, and a move
-- puts it under whatever heading actually makes sense to you. All three are
-- keyed by the command's source string, which is stable across reparses.
local FAV_KEY, ARCHIVE_KEY, MOVED_KEY = "PaletteFavourites", "PaletteArchived", "PaletteMoved"
M.favourites = hs.settings.get(FAV_KEY) or {}
M.archived   = hs.settings.get(ARCHIVE_KEY) or {}
M.moved      = hs.settings.get(MOVED_KEY) or {}

M.ARCHIVE   = "Archive"
M.FAVOURITE = "★ Favourites"

local function usesOf(e) return M.uses[e.source] or 0 end

-- Starred first, then whatever gets used most, and file order to break ties so
-- the untouched majority stays where it was last time.
local function byUse(a, b)
  local fa, fb = a.fav and 1 or 0, b.fav and 1 or 0
  if fa ~= fb then return fa > fb end
  local ua, ub = usesOf(a), usesOf(b)
  if ua ~= ub then return ua > ub end
  return (a.order or 0) < (b.order or 0)
end

function M.sort()
  table.sort(M.entries, byUse)
  for _, c in ipairs(M.categories) do
    table.sort(c.items, byUse)
    c.uses = 0
    for _, e in ipairs(c.items) do c.uses = c.uses + usesOf(e) end
  end
  table.sort(M.categories, function(a, b)
    -- The archive is a drawer, not a destination: it always sits last however
    -- much it is used.
    if (a.name == M.ARCHIVE) ~= (b.name == M.ARCHIVE) then return b.name == M.ARCHIVE end
    if a.uses ~= b.uses then return a.uses > b.uses end
    return (a.items[1] and a.items[1].order or 0) < (b.items[1] and b.items[1].order or 0)
  end)
end

-- ─── Starring, archiving, moving ────────────────────────────────

local function persist()
  hs.settings.set(FAV_KEY, M.favourites)
  hs.settings.set(ARCHIVE_KEY, M.archived)
  hs.settings.set(MOVED_KEY, M.moved)
end

function M.toggleFavourite(e)
  M.favourites[e.source] = (not M.favourites[e.source]) or nil
  e.fav = M.favourites[e.source] or false
  persist()
  hs.alert.show((e.fav and "★ " or "☆ ") .. e.title, 1)
end

function M.archive(e)
  if M.archived[e.source] then
    M.archived[e.source] = nil
    hs.alert.show("Out of the archive: " .. e.title, 1.5)
  else
    M.archived[e.source] = true
    hs.alert.show("Archived: " .. e.title, 1.5)
  end
  persist()
  M.parse()
end

function M.moveTo(e, category)
  if category == nil or category == "" then
    M.moved[e.source] = nil
  else
    M.moved[e.source] = category
    M.archived[e.source] = nil
  end
  persist()
  M.parse()
  hs.alert.show(e.title .. "  →  " .. (category or "back where it came from"), 2)
end

function M.favourites_list()
  local out = {}
  for _, e in ipairs(M.entries) do
    if e.fav then out[#out + 1] = e end
  end
  return out
end

local function remember(e)
  M.uses[e.source] = (M.uses[e.source] or 0) + 1
  hs.settings.set(USES_KEY, M.uses)
  M.sort()
end

-- Forget the ranking and go back to file order
function M.resetUses()
  M.uses = {}
  hs.settings.set(USES_KEY, M.uses)
  M.sort()
  hs.alert.show("Palette: usage ranking cleared", 2)
end

-- ─── Presentation ───────────────────────────────────────────────

local BLUE, GREY = { hex = "#7AA2F7" }, { white = 0.5 }

local function styled(left, leftColor, right)
  local a = hs.styledtext.new(left, { color = leftColor, font = { name = "Menlo", size = 12 } })
  if not right or right == "" then return a end
  return a .. hs.styledtext.new("    " .. right, { color = GREY, font = { size = 12 } })
end

local function rowFor(e)
  local tail = e.detail and (e.category .. "  ·  " .. e.detail) or (e.category .. "  ·  " .. e.source)
  return {
    text    = (e.fav and "★  " or "") .. e.title,
    subText = styled(e.chord or "no hotkey", e.chord and BLUE or GREY, tail),
    entry   = e,
  }
end

-- ─── Running a command ──────────────────────────────────────────

local function run(e)
  remember(e)

  if e.kind == "just" then
    -- A new tmux window, because half these recipes want a real terminal: fzf
    -- and gum need a TTY, and their output is worth reading afterwards. The
    -- window waits on a keypress so a fast recipe does not vanish.
    local inner = ("just -g %s; printf \"\\n── done ── press enter\\n\"; read x"):format(e.recipe)
    local cmd = ("tmux new-window -n 'just %s' '%s' 2>&1"):format(e.recipe, inner)
    local out, ok = hs.execute(cmd, true)
    if not ok then
      hs.alert.show("Palette: no tmux session — running in background", 2)
      hs.task.new("/bin/zsh", function(_, so, se)
        hs.alert.show((so ~= "" and so or se or ""):sub(1, 400), 6)
      end, { "-lc", "just -g " .. e.recipe }):start()
    end
    return
  end

  if e.kind == "key" then
    -- Replay the chord instead of calling the function, so guard and every
    -- other wrapper behaves exactly as when the keys are pressed.
    hs.timer.doAfter(0.05, function() hs.eventtap.keyStroke(e.mods, e.key, 0) end)
    return
  end
  local ok, mod = pcall(require, "modules." .. e.module)
  if not ok or type(mod) ~= "table" or type(mod[e.fn]) ~= "function" then
    return hs.alert.show("Palette: cannot run " .. e.source, 3)
  end
  local ran, err = pcall(mod[e.fn])
  if not ran then hs.alert.show("Palette: " .. tostring(err), 4) end
end

-- ─── Choosers ───────────────────────────────────────────────────

M._chooser = nil
M._expose  = nil

function M.showAllWindows()
  M._expose = M._expose or hs.expose.new(nil, { showThumbnails = true })
  M._expose:toggleShow()
end

-- ─── Arranging from inside the list ─────────────────────────────
--
-- The chooser owns the keyboard while it is up, so the only way to act on the
-- highlighted row is to watch the key stream and swallow what we handle. ⌘⇧ is
-- free here: the chooser itself uses ⌘1-⌘9 for rows and plain typing to filter.

M._view = { kind = "root" }
M._tap  = nil
M._moveChooser = nil

function M.refresh()
  local v = M._view
  if v.kind == "cat" then M.showCategory(v.name)
  elseif v.kind == "all" then M.showAll()
  else M.show() end
end

local function askCategory(e)
  local names, seen = {}, {}
  for _, c in ipairs(M.categories) do
    if not seen[c.name] then seen[c.name], names[#names + 1] = true, c.name end
  end
  table.sort(names)

  local rows = {
    { text = "Put it back", category = false,
      subText = styled("undo", GREY, "return this command to where the files put it") },
  }
  for _, n in ipairs(names) do
    rows[#rows + 1] = { text = n, category = n,
                        subText = styled("move", BLUE, "move “" .. e.title .. "” here") }
  end

  M._moveChooser = M._moveChooser or hs.chooser.new(function(choice)
    if not choice then return hs.timer.doAfter(0.05, M.refresh) end
    M.moveTo(e, choice.category or nil)
    hs.timer.doAfter(0.05, M.refresh)
  end)
  M._moveChooser:placeholderText("move “" .. e.title .. "” to…")
  M._moveChooser:bgDark(true)
  M._moveChooser:width(40)
  M._moveChooser:rows(12)
  M._moveChooser:choices(rows)
  M._moveChooser:show()
end

local function startTap()
  if M._tap then M._tap:stop() end
  M._tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(ev)
    local f = ev:getFlags()
    if not (f.cmd and f.shift) then return false end
    local ch = hs.keycodes.map[ev:getKeyCode()]
    if ch ~= "f" and ch ~= "a" and ch ~= "m" then return false end

    local row = M._chooser and M._chooser:selectedRowContents()
    local e = row and row.entry
    if not e then
      hs.alert.show("Pick a command row first", 1.5)
      return true
    end

    if ch == "f" then
      M.toggleFavourite(e)
      M.sort()
      hs.timer.doAfter(0.05, M.refresh)
    elseif ch == "a" then
      M.archive(e)
      hs.timer.doAfter(0.05, M.refresh)
    elseif ch == "m" then
      M._chooser:hide()
      hs.timer.doAfter(0.1, function() askCategory(e) end)
    end
    return true
  end)
  M._tap:start()
end

-- ─── Sigil filters ──────────────────────────────────────────────
--
-- A leading character narrows the whole list before any typing matters, the way
-- an editor's palette does. The sigil is stripped from the query as soon as it
-- is recognised, so it filters without also having to match any row's text.

local SIGILS = {
  ["*"] = { name = "favourites", test = function(e) return e.fav end },
  ["!"] = { name = "shell recipes", test = function(e) return e.kind == "just" end },
  ["?"] = { name = "has a hotkey", test = function(e) return e.chord ~= nil end },
  ["#"] = { name = "archive", test = function(e) return e.category == M.ARCHIVE end },
  ["/"] = { name = "hammerspoon", test = function(e)
              return e.kind == "fn" or e.kind == "key" end },
}

M._filter = nil

local function filtered()
  local out = {}
  for _, e in ipairs(M.entries) do
    local hidden = e.category == M.ARCHIVE and not (M._filter and M._filter.name == "archive")
    if not hidden and (not M._filter or M._filter.test(e)) then out[#out + 1] = e end
  end
  return out
end

local function chooser()
  M._chooser = M._chooser or hs.chooser.new(function(choice)
    if not choice then return end
    if choice.goTo == "root" then return hs.timer.doAfter(0.05, M.show) end
    if choice.goTo == "all" then return hs.timer.doAfter(0.05, M.showAll) end
    if choice.goTo then
      local name = choice.goTo
      return hs.timer.doAfter(0.05, function() M.showCategory(name) end)
    end
    if choice.expose then return M.showAllWindows() end
    if choice.call then
      -- Pinned rows name their target rather than holding a reference, so the
      -- palette still loads if that module is not installed yet.
      local ok, mod = pcall(require, "modules." .. choice.call[1])
      if ok and type(mod) == "table" and type(mod[choice.call[2]]) == "function" then
        return hs.timer.doAfter(0.05, mod[choice.call[2]])
      end
      return hs.alert.show("Palette: modules/" .. choice.call[1] .. ".lua is not installed", 3)
    end
    if choice.entry then return run(choice.entry) end
  end)
  M._chooser:searchSubText(true)   -- so a chord or a module name finds it too
  M._chooser:bgDark(true)
  M._chooser:width(40)
  M._chooser:rows(14)

  M._chooser:queryChangedCallback(function(q)
    local sigil, rest = q:match("^([%*!%?#/])(.*)$")
    if not sigil then return end
    M._filter = SIGILS[sigil]
    M._view = { kind = "all" }
    local rows = { { text = "← Categories", goTo = "root",
                     subText = styled("esc", GREY, "clear the filter") } }
    for _, e in ipairs(filtered()) do rows[#rows + 1] = rowFor(e) end
    M._chooser:placeholderText(("%s — %d commands"):format(M._filter.name, #rows - 1))
    M._chooser:choices(rows)
    -- Dropping the sigil re-enters this callback with a plain query, which no
    -- longer matches here — so the filter stays and the typing filters within it.
    M._chooser:query(rest)
  end)

  M._chooser:showCallback(startTap)
  M._chooser:hideCallback(function() if M._tap then M._tap:stop() end end)
  return M._chooser
end

-- Root: the categories themselves.
function M.show()
  if #M.entries == 0 then M.parse() end
  M._filter, M._view = nil, { kind = "root" }
  local favs = M.favourites_list()

  -- The things worth reaching for first, before the categories: someone who
  -- remembers only this one chord should still find their way from here.
  local rows = {
    { text = "Cheatsheet — all commands and their keys", goTo = "all",
      subText = styled(("%d"):format(#M.entries), BLUE, "one flat list; type a name, a chord or a module") },
    { text = "Menu of this app", call = { "keyboard", "menuPalette" },
      subText = styled("no mouse", BLUE, "every menu command of the front app, searchable") },
    { text = "Click anything by keyboard", call = { "keyboard", "clickHints" },
      subText = styled("⌃⌥⇧F", BLUE, "labels every button and link — type a label to press it") },
    { text = "Move the cursor with keys", call = { "keyboard", "mouseKeys" },
      subText = styled("no mouse", BLUE, "hjkl to move, space to click, esc to leave") },
    { text = "Show all windows", expose = true,
      subText = styled("Exposé", BLUE, "every window as a thumbnail, whatever the tiler did") },
  }
  if #favs > 0 then
    table.insert(rows, 1, { text = M.FAVOURITE, goTo = M.FAVOURITE,
      subText = styled(("%d starred"):format(#favs), BLUE, "the ones you pinned with ⌘⇧F") })
  end

  for _, c in ipairs(M.categories) do
    -- A taste of what is inside, clipped hard: a long description here wraps
    -- the row onto a second line and the list stops being scannable.
    local names, budget = {}, 62
    for _, e in ipairs(c.items) do
      local t = #e.title > 22 and (e.title:sub(1, 21) .. "…") or e.title
      if budget - #t < 0 then names[#names + 1] = "…" break end
      names[#names + 1], budget = t, budget - #t - 2
    end
    rows[#rows + 1] = {
      text    = c.name,
      goTo    = c.name,
      subText = styled(("%d cmds"):format(#c.items), BLUE, table.concat(names, ", ")),
    }
  end

  local ch = chooser()
  ch:placeholderText("category, or type to search   ·   * ! ? # / filter   ·   ⌘⇧F star  ⌘⇧A archive  ⌘⇧M move")
  ch:choices(rows)
  ch:show()
end

function M.showCategory(name)
  if #M.entries == 0 then M.parse() end
  M._filter, M._view = nil, { kind = "cat", name = name }

  local rows = { { text = "← Categories", goTo = "root",
                   subText = styled("esc", GREY, "back to the category list") } }
  if name == M.FAVOURITE then
    for _, e in ipairs(M.favourites_list()) do rows[#rows + 1] = rowFor(e) end
  else
    for _, c in ipairs(M.categories) do
      if c.name == name then
        for _, e in ipairs(c.items) do rows[#rows + 1] = rowFor(e) end
      end
    end
  end

  local ch = chooser()
  ch:placeholderText(("%s — %d commands   ·   ⌘⇧F star  ⌘⇧A archive  ⌘⇧M move"):format(name, #rows - 1))
  ch:choices(rows)
  ch:show()
end

function M.showAll()
  if #M.entries == 0 then M.parse() end
  M._filter, M._view = nil, { kind = "all" }

  local rows = { { text = "← Categories", goTo = "root",
                   subText = styled("esc", GREY, "back to the category list") } }
  for _, e in ipairs(filtered()) do rows[#rows + 1] = rowFor(e) end

  local ch = chooser()
  ch:placeholderText(("all %d — name, chord or module   ·   * fav  ! shell  ? hotkey  # archive"):format(#rows - 1))
  ch:choices(rows)
  ch:show()
end

function M.reload()
  M.parse()
  hs.alert.show(("Palette: %d commands in %d categories"):format(#M.entries, #M.categories), 2)
end

return M
