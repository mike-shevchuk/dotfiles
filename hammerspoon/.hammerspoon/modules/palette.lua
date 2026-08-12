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

  -- Categories keep the order they first appear in, so the bound commands from
  -- init.lua lead and the module-only ones follow.
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
  return entries
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
    text    = e.title,
    subText = styled(e.chord or "no hotkey", e.chord and BLUE or GREY, tail),
    entry   = e,
  }
end

-- ─── Running a command ──────────────────────────────────────────

local function run(e)
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
    if choice.entry then return run(choice.entry) end
  end)
  M._chooser:searchSubText(true)   -- so a chord or a module name finds it too
  M._chooser:bgDark(true)
  M._chooser:width(40)
  M._chooser:rows(14)
  return M._chooser
end

-- Root: the categories themselves.
function M.show()
  if #M.entries == 0 then M.parse() end

  local rows = {
    { text = "All commands", goTo = "all",
      subText = styled(("%d"):format(#M.entries), BLUE, "everything in one flat list") },
    { text = "Show all windows", expose = true,
      subText = styled("⌃⌥⇧W", BLUE, "Exposé — every window, any space, ignores tiling") },
  }
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
  ch:placeholderText("category — or type to search across them")
  ch:choices(rows)
  ch:show()
end

function M.showCategory(name)
  if #M.entries == 0 then M.parse() end
  local rows = { { text = "← Categories", goTo = "root",
                   subText = styled("esc", GREY, "back to the category list") } }
  for _, c in ipairs(M.categories) do
    if c.name == name then
      for _, e in ipairs(c.items) do rows[#rows + 1] = rowFor(e) end
    end
  end

  local ch = chooser()
  ch:placeholderText(name .. " — " .. (#rows - 1) .. " commands")
  ch:choices(rows)
  ch:show()
end

function M.showAll()
  if #M.entries == 0 then M.parse() end
  local rows = { { text = "← Categories", goTo = "root",
                   subText = styled("esc", GREY, "back to the category list") } }
  for _, e in ipairs(M.entries) do rows[#rows + 1] = rowFor(e) end

  local ch = chooser()
  ch:placeholderText(("all %d commands — type a name, a chord, or a module"):format(#M.entries))
  ch:choices(rows)
  ch:show()
end

function M.reload()
  M.parse()
  hs.alert.show(("Palette: %d commands in %d categories"):format(#M.entries, #M.categories), 2)
end

return M
