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

-- More than one justfile can be in play — a branch adds recipes the installed
-- one does not have yet — so the list is a setting. First file to define a name
-- wins, which keeps the installed global authoritative.
M.justfiles = hs.settings.get("PaletteJustfiles")
  or { os.getenv("HOME") .. "/dotfiles/.justdir/global.just" }

local function parseJustfile(path, entries, seen)
  local probe = io.open(path, "r")
  if not probe then return end
  probe:close()

  local out, ok = hs.execute(
    ("just --justfile %s --dump --dump-format json 2>/dev/null"):format(path), true)
  if not ok or not out or out == "" then return end
  local decoded, data = pcall(hs.json.decode, out)
  if not decoded or type(data) ~= "table" or type(data.recipes) ~= "table" then return end

  local names = {}
  for name in pairs(data.recipes) do names[#names + 1] = name end
  table.sort(names)

  for _, name in ipairs(names) do
   if not seen[name] then
    seen[name] = true
    local r = data.recipes[name]
    local private, group = name:sub(1, 1) == "_", nil
    for _, attr in ipairs(r.attributes or {}) do
      if type(attr) == "table" and attr.group then group = attr.group
      elseif attr == "private" then private = true end
    end
    if not private then
      local doc = r.doc

      -- Recipes take arguments, and half of these do. Keep the names and
      -- defaults so the palette can ask for them instead of silently running
      -- with whatever the justfile falls back to.
      local params, sig = {}, {}
      for _, p in ipairs(r.parameters or {}) do
        local required = (p.default == nil)
        params[#params + 1] = { name = p.name, default = p.default, required = required }
        sig[#sig + 1] = required and p.name:upper()
                        or ("[" .. p.name .. "=" .. tostring(p.default) .. "]")
      end

      entries[#entries + 1] = {
        kind     = "just",
        title    = (doc and doc ~= "" and doc) or name,
        category = "just · " .. (group or "misc"),
        source   = "just -g " .. name,
        detail   = "just -g " .. name .. (#sig > 0 and (" " .. table.concat(sig, " ")) or ""),
        recipe   = name,
        justfile = path,
        params   = #params > 0 and params or nil,
      }
    end
   end
  end
end

local function parseJust(entries)
  local seen = {}
  for _, path in ipairs(M.justfiles) do parseJustfile(path, entries, seen) end
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

-- ─── Matching ───────────────────────────────────────────────────
--
-- Setting a queryChangedCallback turns off the chooser's own filtering — it
-- assumes anyone handling the query wants to build the list themselves. The
-- sigils need that callback, so the matching has to be done here, and every
-- view has to hand its full row set over rather than calling choices() itself.

M._rows = {}

local function haystack(r)
  if r.search then return r.search end
  local sub = r.subText
  if type(sub) == "userdata" and sub.getString then sub = sub:getString() end
  r.search = ((r.text or "") .. " " .. tostring(sub or "")):lower()
  return r.search
end

-- Every word has to appear somewhere in the row, in any order: "trash empty"
-- finds the same thing as "empty trash", and "⌥⇧T" finds it by its chord.
local function matching(rows, q)
  q = (q or ""):lower()
  if q == "" then return rows end
  local out = {}
  for _, r in ipairs(rows) do
    local hay, ok = haystack(r), true
    for word in q:gmatch("%S+") do
      if not hay:find(word, 1, true) then ok = false break end
    end
    if ok then out[#out + 1] = r end
  end
  return out
end

-- Hand the rows to the chooser through here, never directly, or the query in
-- the box stops meaning anything.
local function present(ch, rows, placeholder)
  M._rows = rows
  if placeholder then ch:placeholderText(placeholder) end
  ch:choices(matching(rows, ch:query()))
end

-- An icon per row, matched on the category name first and falling back to what
-- kind of thing it is. Purely for scanning: at 128 rows the eye needs a shape
-- to land on before it starts reading.
local CATEGORY_ICON = {
  ["app launcher"] = "🚀", ["window"] = "🪟", ["paperwm"] = "▦",
  ["clipboard"] = "📋", ["audio"] = "🔊", ["system"] = "⚙️", ["display"] = "🖥",
  ["mouse"] = "🎯", ["scratchpad"] = "📝", ["brightness"] = "☀️",
  ["notetaker"] = "📓", ["git"] = "🌿", ["bookmark"] = "🔖", ["pomodoro"] = "🍅",
  ["screenshot"] = "📸", ["task"] = "✅", ["desktop"] = "🖥", ["console"] = "🔨",
  ["mirror"] = "🪞", ["disk"] = "💾", ["cheat"] = "📄", ["til"] = "💡",
  ["search"] = "🔍", ["night"] = "🌙", ["keyboard"] = "⌨️", ["archive"] = "🗄",
  ["launcher"] = "🚀", ["sidecar"] = "🪞", ["todoist"] = "☑️", ["linear"] = "📊",
}
local KIND_ICON = { key = "⌨️", fn = "🔧", just = "▶️" }

local function iconFor(e)
  local name = (e.category or ""):lower()
  for word, icon in pairs(CATEGORY_ICON) do
    if name:find(word, 1, true) then return icon end
  end
  return KIND_ICON[e.kind] or "•"
end

local function rowFor(e)
  local tail = e.detail and (e.category .. "  ·  " .. e.detail) or (e.category .. "  ·  " .. e.source)
  return {
    text    = ("%s  %s%s"):format(iconFor(e), e.fav and "★ " or "", e.title),
    subText = styled(e.chord or "no hotkey", e.chord and BLUE or GREY, tail),
    entry   = e,
  }
end

-- The tab strip, as a row rather than only a placeholder: it stays on screen
-- while typing, and picking it walks to the next tab.
local function tabRow()
  local parts = {}
  for i, t in ipairs(M.TABS) do
    parts[#parts + 1] = (i == M._tab) and ("▸ " .. t.name) or t.name
  end
  return {
    text    = table.concat(parts, "   "),
    subText = styled("⌥1-" .. #M.TABS .. " / Tab", BLUE,
                     "switch tab   ·   esc back   ·   → star   ← archive   ⇧→ move"),
    nextTab = true,
  }
end

-- ─── Running a command ──────────────────────────────────────────

-- A new tmux window, because half these recipes want a real terminal: fzf and
-- gum need a TTY, and the output is worth reading afterwards. The window waits
-- on a keypress so a fast recipe does not vanish before it can be read.
function M.runRecipe(e, args)
  args = (args and args ~= "") and (" " .. args) or ""
  local where = e.justfile and ("--justfile " .. e.justfile .. " ") or "-g "
  local inner = ("just %s%s%s; printf \"\\n── done ── press enter\\n\"; read x")
    :format(where, e.recipe, args)
  local cmd = ("tmux new-window -n 'just %s' '%s' 2>&1"):format(e.recipe, inner)
  local _, ok = hs.execute(cmd, true)
  if not ok then
    hs.alert.show("Palette: no tmux session — running in the background", 2)
    hs.task.new("/bin/zsh", function(_, so, se)
      hs.alert.show((so ~= "" and so or se or ""):sub(1, 400), 6)
    end, { "-lc", "just -g " .. e.recipe .. args }):start()
  end
end

-- Ask for the recipe's arguments with the query field itself: a text prompt
-- would block the whole of Hammerspoon until answered, which is the wrong shape
-- for a setup meant to run on the keyboard. Type, Enter, done — and an empty
-- answer is still valid, since every optional parameter keeps its default.
M._argChooser = nil

function M.askArgs(e)
  local hint = {}
  for _, p in ipairs(e.params) do
    hint[#hint + 1] = p.required and (p.name:upper() .. " (required)")
                      or ("[" .. p.name .. "=" .. tostring(p.default) .. "]")
  end
  local signature = table.concat(hint, "  ")

  local function row(args)
    return { {
      text    = "just -g " .. e.recipe .. (args ~= "" and (" " .. args) or ""),
      subText = styled(args ~= "" and "Enter to run" or "Enter to run with defaults",
                       BLUE, signature),
      args    = args,
    } }
  end

  M._argChooser = M._argChooser or hs.chooser.new(function(choice)
    if not choice then return end
    M.runRecipe(choice.entry or M._argEntry, choice.args or "")
  end)
  M._argEntry = e
  M._argChooser:queryChangedCallback(function(q) M._argChooser:choices(row(q)) end)
  M._argChooser:placeholderText("arguments for " .. e.recipe .. "   ·   " .. signature)
  M._argChooser:bgDark(true)
  M._argChooser:width(40)
  M._argChooser:rows(3)
  M._argChooser:query("")
  M._argChooser:choices(row(""))
  M._argChooser:show()
end

local function run(e)
  remember(e)

  if e.kind == "just" then
    if e.params then return M.askArgs(e) end
    return M.runRecipe(e, "")
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
-- An eventtap cannot help here: the chooser takes the keyboard in a way that
-- keeps a separate tap from ever seeing the keys, so chords over the
-- highlighted row simply never arrive. What does reach us is the query itself,
-- so arranging is a mode typed into it — "+" then pick the command to star it.
-- One keystroke more than a chord, and it announces itself in the placeholder
-- instead of having to be remembered.

M._view = { kind = "root" }
M._mode = nil
M._moveChooser = nil

function M.refresh()
  local v = M._view
  if v.kind == "windows" then M.showWindows()
  elseif v.kind == "cat" then M.showCategory(v.name)
  elseif v.kind == "all" then M.showAll()
  else M.show() end
end

-- ─── Sigils: narrow the list, or act on the next pick ───────────
--
-- A leading character says what the rest of the typing means. The sigil is
-- stripped from the query the moment it is recognised, so it never has to match
-- a row's text; the reentry that strips it carries no sigil, so it settles.

local SIGILS = {
  ["*"] = { name = "starred",       test = function(e) return e.fav end },
  ["!"] = { name = "shell recipes", test = function(e) return e.kind == "just" end },
  ["?"] = { name = "has a hotkey",  test = function(e) return e.chord ~= nil end },
  ["#"] = { name = "archive",       test = function(e) return e.category == M.ARCHIVE end },
  ["/"] = { name = "hammerspoon",   test = function(e)
              return e.kind == "fn" or e.kind == "key" end },
}

-- The same idea, but acting instead of narrowing: type the sigil, then pick a
-- command, and the pick arranges that command rather than running it.
local MODES = {
  ["+"] = { name = "star",    hint = "★  pick a command — Enter stars it (again to unstar)" },
  ["-"] = { name = "archive", hint = "🗄  pick a command — Enter archives it (again to restore)" },
  [">"] = { name = "move",    hint = "→  pick a command — Enter moves it to another category" },
}

-- ─── Tabs ───────────────────────────────────────────────────────
--
-- The filters are useful but a typed sigil is a thing to remember. The same
-- views as tabs cost nothing to discover: the bar is always in the placeholder,
-- ⌥1…⌥6 jump straight to one and Tab walks them in order.

M.TABS = {
  { key = "1", name = "Categories", sigil = nil, root = true },
  { key = "2", name = "All",        sigil = nil },
  { key = "3", name = "Windows",    windows = true },
  { key = "4", name = "★ Starred",  sigil = "*" },
  { key = "5", name = "? Hotkeys",  sigil = "?" },
  { key = "6", name = "justfile",   sigil = "!" },
  { key = "7", name = "# Archive",  sigil = "#" },
}
M._tab = 1

local function tabBar()
  local out = {}
  for i, t in ipairs(M.TABS) do
    out[#out + 1] = (i == M._tab) and ("[" .. t.name .. "]") or t.name
  end
  return table.concat(out, "  ")
end

M._filter = nil

local function filtered()
  local out = {}
  for _, e in ipairs(M.entries) do
    local hidden = e.category == M.ARCHIVE and not (M._filter and M._filter.name == "archive")
    if not hidden and (not M._filter or M._filter.test(e)) then out[#out + 1] = e end
  end
  return out
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

-- ─── Arranging with the arrows ──────────────────────────────────
--
-- An eventtap does see the keys while the chooser is up — an earlier attempt
-- concluded otherwise, on a bad test. So the arrows can act on the highlighted
-- row directly, which beats typing a mode first:
--
--   →  star it        ←  archive it        ⇧→  move it elsewhere
--
-- Up and down still walk the list, and on rows that are not commands the arrows
-- fall through untouched, so navigation never feels trapped.

M._tap = nil

-- Acting rebuilds the list; without this the selection would jump back to the
-- top and starring three things in a row would be a hunt each time.
local function keepRow(fn)
  local row = M._chooser and M._chooser:selectedRow()
  fn()
  hs.timer.doAfter(0.06, function()
    M.refresh()
    hs.timer.doAfter(0.06, function()
      if M._chooser and row then M._chooser:selectedRow(row) end
    end)
  end)
end

local function startTap()
  if M._tap then M._tap:stop() end
  M._tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(ev)
    local key   = hs.keycodes.map[ev:getKeyCode()]
    local flags = ev:getFlags()

    -- Tabs first: they change the whole view, whatever is highlighted.
    if key == "tab" then
      local step = flags.shift and -1 or 1
      M.showTab(((M._tab - 1 + step) % #M.TABS) + 1)
      return true
    end
    if flags.alt and key and key:match("^[1-6]$") then
      M.showTab(tonumber(key))
      return true
    end

    if key ~= "left" and key ~= "right" then return false end

    local row = M._chooser and M._chooser:selectedRowContents()
    local e = row and row.entry
    if not e then return false end

    if key == "right" and ev:getFlags().shift then
      M._chooser:hide()
      hs.timer.doAfter(0.1, function() askCategory(e) end)
    elseif key == "right" then
      keepRow(function() M.toggleFavourite(e) M.sort() end)
    else
      keepRow(function() M.archive(e) end)
    end
    return true
  end)
  M._tap:start()
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
    if choice.nextTab then
      return hs.timer.doAfter(0.05, function() M.showTab((M._tab % #M.TABS) + 1) end)
    end
    if choice.windowId then
      local w = hs.window.get(choice.windowId)
      if w then w:focus() else hs.alert.show("That window is gone", 2) end
      return
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
    if choice.entry then
      local e, mode = choice.entry, M._mode
      M._mode = nil
      if mode then
        if mode.name == "star" then
          M.toggleFavourite(e)
          M.sort()
        elseif mode.name == "archive" then
          M.archive(e)
        elseif mode.name == "move" then
          return hs.timer.doAfter(0.1, function() askCategory(e) end)
        end
        return hs.timer.doAfter(0.05, M.refresh)
      end
      return run(e)
    end
  end)
  M._chooser:searchSubText(true)   -- so a chord or a module name finds it too
  M._chooser:bgDark(true)
  M._chooser:width(40)
  M._chooser:rows(14)
  M._chooser:showCallback(startTap)
  M._chooser:hideCallback(function()
    if M._tap then M._tap:stop() M._tap = nil end
  end)

  M._chooser:queryChangedCallback(function(q)
    local sigil, rest = q:match("^([%*!%?#/%+%->])(.*)$")
    if not sigil then
      -- Plain typing: filter the current view's rows ourselves.
      M._chooser:choices(matching(M._rows, q))
      return
    end

    if MODES[sigil] then
      M._mode = MODES[sigil]
      M._chooser:placeholderText(M._mode.hint)
      M._chooser:query(rest)
      return
    end

    M._filter = SIGILS[sigil]
    M._view = { kind = "all" }
    local rows = { tabRow() }
    for _, e in ipairs(filtered()) do rows[#rows + 1] = rowFor(e) end
    present(M._chooser, rows, ("%s — %d commands"):format(M._filter.name, #rows - 1))
    -- Dropping the sigil re-enters this callback with a plain query, which no
    -- longer matches here — so the filter stays and the typing filters within it.
    M._chooser:query(rest)
  end)

  return M._chooser
end

-- The hotkey's way in. Only a fresh open clears an arranging mode: walking into
-- a category must not, or "+ then find the command" would be impossible for
-- anything that is not already on screen.
function M.open()
  M._mode, M._filter, M._tab = nil, nil, 1
  -- Start empty: last night's query still sitting in the box makes the palette
  -- look broken before a key is pressed.
  if M._chooser then M._chooser:query("") end
  M.show()
end

-- Switch to a tab: the categories, the windows, everything, or a filtered view.
function M.showTab(i)
  local tab = M.TABS[i]
  if not tab then return end
  M._tab = i
  if tab.root then return M.show() end
  if tab.windows then return M.showWindows() end
  M._filter = tab.sigil and SIGILS[tab.sigil] or nil
  M.showAll()
end

-- Every open window, front-to-back. Not a command list at all — it is built
-- fresh each time from what is actually on screen, because a window list cached
-- from a parse would be wrong within seconds.
function M.showWindows()
  M._view = { kind = "windows" }
  local rows = { tabRow() }

  for _, w in ipairs(hs.window.orderedWindows()) do
    local app    = w:application() and w:application():name() or "?"
    local title  = w:title()
    local screen = w:screen() and w:screen():name() or "?"
    -- The palette is itself a window; listing it as somewhere to jump to is
    -- noise at best and a loop at worst.
    if title and title ~= "" and app ~= "Hammerspoon" then
      rows[#rows + 1] = {
        text     = title,
        subText  = styled(app, BLUE, screen .. (w:isMinimized() and "  ·  minimised" or "")),
        windowId = w:id(),
      }
    end
  end

  local ch = chooser()
  present(ch, rows, tabBar() .. ("   ·   %d windows"):format(#rows - 1))
  ch:show()
end

-- Root: the categories themselves.
function M.show()
  if #M.entries == 0 then M.parse() end
  M._view = { kind = "root" }
  local favs = M.favourites_list()

  -- The things worth reaching for first, before the categories: someone who
  -- remembers only this one chord should still find their way from here.
  local rows = {
    { text = "Cheatsheet — all commands and their keys", goTo = "all",
      subText = styled(("%d"):format(#M.entries), BLUE, "one flat list; type a name, a chord or a module") },
    { text = "Open a cheatsheet", call = { "cheatsheets", "show" },
      subText = styled("⌃⌥⇧H", BLUE, "README sections, zettelkasten sheets, and this palette's own") },
    { text = "Menu of this app", call = { "keyboard", "menuPalette" },
      subText = styled("no mouse", BLUE, "every menu command of the front app, searchable") },
    { text = "Click anything by keyboard", call = { "keyboard", "clickHints" },
      subText = styled("⌃⌥⇧F", BLUE, "labels every button and link — type a label to press it") },
    { text = "Move the cursor with keys", call = { "keyboard", "mouseKeys" },
      subText = styled("no mouse", BLUE, "hjkl to move, space to click, esc to leave") },
    { text = "Show all windows", expose = true,
      subText = styled("Exposé", BLUE, "every window as a thumbnail, whatever the tiler did") },
  }
  table.insert(rows, 1, tabRow())

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
  present(ch, rows, M._mode and M._mode.hint or (tabBar() .. "   ·   ⌥1-7 / Tab"))
  ch:show()
end

function M.showCategory(name)
  if #M.entries == 0 then M.parse() end
  M._view = { kind = "cat", name = name }

  local rows = { tabRow() }
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
  present(ch, rows, M._mode and M._mode.hint
    or ("%s — %d   ·   → star   ← archive   ⇧→ move"):format(name, #rows - 1))
  ch:show()
end

function M.showAll()
  if #M.entries == 0 then M.parse() end
  M._view = { kind = "all" }

  local rows = { tabRow() }
  for _, e in ipairs(filtered()) do rows[#rows + 1] = rowFor(e) end

  local ch = chooser()
  present(ch, rows, M._mode and M._mode.hint
    or (tabBar() .. ("   ·   %d   ·   → star  ← archive  ⇧→ move"):format(#rows - 1)))
  ch:show()
end

function M.reload()
  M.parse()
  hs.alert.show(("Palette: %d commands in %d categories"):format(#M.entries, #M.categories), 2)
end

return M
