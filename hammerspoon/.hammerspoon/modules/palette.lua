-- Command palette over the config's own hotkeys.
--
-- hs.hotkey.getHotkeys() knows which chords are live but nothing about what
-- they do — the bindings carry no messages, so it can only ever print "⌥⇧O".
-- The descriptions already exist though: they are the comments above each
-- binding in init.lua. So this parses init.lua itself. The palette therefore
-- cannot drift from what is actually bound — edit a comment, and the palette
-- says the new thing on the next reload.
--
-- Picking an entry replays its chord rather than calling the function, so
-- whatever the binding really does (guard checks included) happens unchanged.

local M = {}

local SYMBOL     = { cmd = "⌘", ctrl = "⌃", alt = "⌥", shift = "⇧" }
local MOD_ORDER  = { "ctrl", "alt", "shift", "cmd" }
local KEY_LABEL  = { ["return"] = "↩", space = "Space", delete = "⌫",
                     left = "←", right = "→", up = "↑", down = "↓" }

M.entries = {}

-- ─── Parsing init.lua ───────────────────────────────────────────

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- "{ \"ctrl\", \"alt\" }" or a name defined earlier ("hyper") → list of mods
local function parseMods(expr, named)
  expr = trim(expr)
  if named[expr] then return named[expr] end
  local mods = {}
  for m in expr:gmatch('"([%a]+)"') do mods[#mods + 1] = m:lower() end
  return mods
end

local function chord(mods, key)
  local set = {}
  for _, m in ipairs(mods) do set[m] = true end
  local out = {}
  for _, m in ipairs(MOD_ORDER) do
    if set[m] then out[#out + 1] = SYMBOL[m] end
  end
  local label = KEY_LABEL[key:lower()] or key:upper()
  return table.concat(out) .. label
end

-- "apps.toggle(\"Ghostty\")" → "Toggle Ghostty", "system.toggleDarkMode" →
-- "Toggle dark mode". Showing the call itself is honest but unreadable, and
-- the call already says what the thing does — it just needs unpacking.
-- Verbs that mean nothing on their own: "Toggle" what? For those the module
-- name is the missing object ("dropdown.toggle" → "Toggle dropdown"), while
-- "windows.maximize" already says everything and gains nothing from it.
local NEEDS_OBJECT = { toggle = true, show = true, start = true, open = true, hide = true }

local function words(s)
  local w = s:gsub("(%l)(%u)", "%1 %2"):gsub("_", " "):lower()
  return w:sub(1, 1):upper() .. w:sub(2)
end

local function humanize(action)
  if action == "" or action:match("^function") then return nil end
  local arg = action:match('"([^"]+)"')
  local mod, fn = action:match("([%w_]+)%.([%w_]+)")
  fn = fn or action:match("^([%w_]+)")
  if not fn then return nil end

  if arg then return words(fn) .. " " .. (arg:gsub("_", " ")) end
  if mod and NEEDS_OBJECT[fn:lower()] then return words(fn) .. " " .. mod:lower() end
  return words(fn)
end

-- Comments name their key either bare ("I = pick a display…") or spelled out
-- with the chord ("ctrl+alt+cmd+Space = jump to any window").
local function namesKey(token, key)
  token, key = token:lower(), key:lower()
  if token == key then return true end
  return token:match("%+" .. key:gsub("(%W)", "%%%1") .. "$") ~= nil
end

-- A comment about this exact key is the best description there is. Anything
-- else above a binding tends to be a heading for the group below it ("Halves"
-- over four arrow keys), which reads worse than the unpacked call — so the call
-- wins, and a loose comment is only the last resort.
local function describe(comments, key, action)
  for _, c in ipairs(comments) do
    local k, rest = c:match("^(%S+)%s*=%s*(.+)$")
    if k and namesKey(k, key) then return trim(rest) end
  end
  return humanize(action) or (#comments > 0 and comments[1]) or action
end

function M.parse(path)
  path = path or (hs.configdir .. "/init.lua")
  local f = io.open(path, "r")
  if not f then return {} end

  local named, entries = {}, {}
  local section, comments = "", {}

  for line in f:lines() do
    local var, body = line:match("^%s*local%s+([%w_]+)%s*=%s*{(.-)}")
    if var and body:find('"') then
      local mods = {}
      for m in body:gmatch('"([%a]+)"') do mods[#mods + 1] = m:lower() end
      if #mods > 0 then named[var] = mods end
    end

    if line:match("^%s*%-%-") then
      local text = trim(line:gsub("^%s*%-%-%s?", ""))
      -- Section rules are drawn with box characters; Lua patterns are byte-wise,
      -- so strip the character rather than trying to match a run of it.
      if text:find("─", 1, true) then
        section, comments = trim((text:gsub("─", ""))), {}
      elseif text ~= "" then
        comments[#comments + 1] = text
      end
    elseif trim(line) == "" then
      comments = {}
    end

    -- Two shapes, and the brace form must be tried first: a non-greedy capture
    -- would otherwise stop at the first comma inside { "ctrl", "alt", "cmd" }
    -- and mistake "alt" for the key.
    local modExpr, key, action =
      line:match("bind%s*%(%s*({.-})%s*,%s*\"([^\"]+)\"%s*,%s*(.-)%s*%)%s*$")
    if not modExpr then
      modExpr, key, action =
        line:match("bind%s*%(%s*([%w_]+)%s*,%s*\"([^\"]+)\"%s*,%s*(.-)%s*%)%s*$")
    end
    if modExpr and key then
      local mods = parseMods(modExpr, named)
      if #mods > 0 then
        entries[#entries + 1] = {
          key     = key,
          mods    = mods,
          chord   = chord(mods, key),
          section = section,
          desc    = describe(comments, key, action or ""),
        }
        comments = {}
      end
    end
  end
  f:close()

  M.entries = entries
  return entries
end

-- ─── Palette ────────────────────────────────────────────────────

M._chooser = nil
M._expose  = nil

-- Everything at once, regardless of how the tiler laid the row out — useful
-- when the desktop is mirrored onto a small screen and most columns are parked
-- past its edge.
function M.showAllWindows()
  M._expose = M._expose or hs.expose.new(nil, { showThumbnails = true })
  M._expose:toggleShow()
end

-- The chord is the thing the eye hunts for, so give it its own colour and a
-- monospaced run; the section trails behind it in grey as context.
local function subtitle(chord, section)
  local keys = hs.styledtext.new(chord, {
    color = { hex = "#7AA2F7" }, font = { name = "Menlo", size = 12 },
  })
  local rest = hs.styledtext.new("    " .. (section ~= "" and section or "hotkey"), {
    color = { white = 0.55 }, font = { size = 12 },
  })
  return keys .. rest
end

local function items()
  local out = {
    { text    = "Show all windows",
      subText = subtitle("⌃⌥⇧W", "Exposé — every window, any space, ignores tiling"),
      special = "expose" },
  }
  for _, e in ipairs(M.entries) do
    out[#out + 1] = {
      text    = e.desc,
      subText = subtitle(e.chord, e.section),
      mods    = e.mods,
      key     = e.key,
    }
  end
  return out
end

function M.show()
  if #M.entries == 0 then M.parse() end

  M._chooser = M._chooser or hs.chooser.new(function(choice)
    if not choice then return end
    if choice.special == "expose" then return M.showAllWindows() end
    -- Replay the chord so the real binding runs, guard and all.
    hs.timer.doAfter(0.05, function()
      hs.eventtap.keyStroke(choice.mods, choice.key, 0)
    end)
  end)
  M._chooser:placeholderText("what do you want to do?   (or type a chord: ⌥⇧, ctrl…)")
  M._chooser:searchSubText(true)   -- so typing a chord finds it too
  M._chooser:rows(14)
  M._chooser:width(40)
  M._chooser:bgDark(true)
  M._chooser:choices(items())
  M._chooser:show()
end

-- Re-read init.lua (after editing comments or bindings)
function M.reload()
  M.parse()
  hs.alert.show(("Palette: %d hotkeys"):format(#M.entries), 2)
end

return M
