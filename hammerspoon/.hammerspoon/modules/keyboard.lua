-- Working without a mouse.
--
-- Three gaps stand between a tiling setup and never touching the trackpad, and
-- each needs a different answer:
--
--   menus     — every app hides commands behind its menu bar. They are all
--               reachable through the accessibility API, so they can be a
--               searchable list instead of a drag through submenus.
--   clicking  — buttons, links, checkboxes. The same API exposes them with an
--               AXPress action, so labelling them on screen and typing a label
--               replaces aiming a pointer.
--   the rest  — anything that answers only to a real pointer (canvases, drag
--               handles, hover menus). For those the cursor itself moves under
--               the keyboard.
--
-- Nothing here polls or installs a permanent eventtap: the modal key handlers
-- exist only while a mode is on screen.

local M = {}

local ax = hs.axuielement

M.config = {
  hintKeys   = "fjdkslaghrueiwoqptyvncmxzb", -- home row first; label alphabet
  step       = 60,   -- pixels a single cursor nudge moves
  bigStep    = 240,  -- …with shift held
  hintRoles  = {     -- what counts as "clickable" when hinting
    AXButton = true, AXLink = true, AXCheckBox = true, AXRadioButton = true,
    AXMenuButton = true, AXPopUpButton = true, AXTextField = true,
    AXTextArea = true, AXComboBox = true, AXDisclosureTriangle = true,
    AXTabGroup = true, AXSlider = true, AXImage = false, AXRow = true,
  },
}

-- ─── Shared drawing ─────────────────────────────────────────────

local function label(frame, text)
  local w, h = 14 + #text * 11, 22
  local c = hs.canvas.new({ x = frame.x + frame.w / 2 - w / 2, y = frame.y + frame.h / 2 - h / 2,
                            w = w, h = h })
  c:appendElements(
    { type = "rectangle", action = "fill", roundedRectRadii = { xRadius = 5, yRadius = 5 },
      fillColor = { hex = "#F7C948", alpha = 0.96 } },
    { type = "text", text = text:upper(), textColor = { hex = "#1A1A1A" },
      textSize = 14, textAlignment = "center",
      textFont = "Menlo-Bold", frame = { x = 0, y = 2, w = w, h = h } })
  c:level(hs.canvas.windowLevels.overlay)
  c:show()
  return c
end

-- Labels are assigned so that the shortest ones land on the home row first;
-- past 26 targets they become two characters rather than running out.
local function labels(n)
  local keys, out = M.config.hintKeys, {}
  for i = 1, n do
    if i <= #keys then
      out[i] = keys:sub(i, i)
    else
      local a = math.floor((i - #keys - 1) / #keys) + 1
      local b = ((i - #keys - 1) % #keys) + 1
      out[i] = keys:sub(a, a) .. keys:sub(b, b)
    end
  end
  return out
end

-- ─── Click by keyboard ──────────────────────────────────────────

local function onScreen(frame, screenFrame)
  return frame and frame.w > 4 and frame.h > 4
     and frame.x + frame.w > screenFrame.x and frame.x < screenFrame.x + screenFrame.w
     and frame.y + frame.h > screenFrame.y and frame.y < screenFrame.y + screenFrame.h
end

local function clickable(el)
  local role = el:attributeValue("AXRole")
  if M.config.hintRoles[role] then return true end
  for _, a in ipairs(el:actionNames() or {}) do
    if a == "AXPress" then return true end
  end
  return false
end

local function collect(el, screenFrame, acc, depth)
  if depth > 12 or #acc > 200 then return acc end
  for _, child in ipairs(el:attributeValue("AXChildren") or {}) do
    local frame = child:attributeValue("AXFrame")
    if onScreen(frame, screenFrame) then
      if clickable(child) then acc[#acc + 1] = { el = child, frame = frame } end
      collect(child, screenFrame, acc, depth + 1)
    end
  end
  return acc
end

M._hints = nil

local function clearHints()
  if not M._hints then return end
  for _, c in ipairs(M._hints.canvases) do c:delete() end
  if M._hints.tap then M._hints.tap:stop() end
  M._hints = nil
end

-- Label every clickable thing in the focused window and press the one typed.
function M.clickHints()
  clearHints()
  local win = hs.window.focusedWindow()
  if not win then return hs.alert.show("No focused window", 2) end
  local root = ax.windowElement(win)
  if not root then return hs.alert.show("Window is not accessible", 2) end

  local targets = collect(root, win:screen():fullFrame(), {}, 0)
  if #targets == 0 then return hs.alert.show("Nothing clickable found here", 2) end

  local codes, canvases, byCode = labels(#targets), {}, {}
  for i, t in ipairs(targets) do
    canvases[#canvases + 1] = label(t.frame, codes[i])
    byCode[codes[i]] = t
  end

  local typed = ""
  local tap
  tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(ev)
    local ch = hs.keycodes.map[ev:getKeyCode()]
    if ch == "escape" then clearHints() return true end
    if ch == "delete" then typed = typed:sub(1, -2) return true end
    if not ch or #ch ~= 1 then return true end

    typed = typed .. ch
    local hit = byCode[typed]
    if hit then
      clearHints()
      -- AXPress is the honest way; a real click is the fallback for the
      -- elements that advertise no action but still respond to a pointer.
      local ok = pcall(function() return hit.el:performAction("AXPress") end)
      if not ok then
        local f = hit.el:attributeValue("AXFrame")
        hs.eventtap.leftClick({ x = f.x + f.w / 2, y = f.y + f.h / 2 }, 20000)
      end
      return true
    end
    -- No label starts with what has been typed: the guess was wrong, start over
    local possible = false
    for code in pairs(byCode) do
      if code:sub(1, #typed) == typed then possible = true break end
    end
    if not possible then typed = "" end
    return true
  end)
  tap:start()
  M._hints = { canvases = canvases, tap = tap }
end

-- ─── Menu of the focused app, as a list ─────────────────────────

M._menuChooser = nil

local function flatten(items, prefix, out)
  for _, item in ipairs(items or {}) do
    local title = item.AXTitle
    if title and title ~= "" then
      local path = {}
      for _, p in ipairs(prefix) do path[#path + 1] = p end
      path[#path + 1] = title
      if item.AXChildren then
        flatten(item.AXChildren[1], path, out)
      elseif item.AXEnabled ~= false then
        local shortcut = item.AXMenuItemCmdChar
        out[#out + 1] = {
          text    = title,
          subText = table.concat(path, "  →  ", 1, #path - 1) ..
                    (shortcut and shortcut ~= "" and ("     ⌘" .. shortcut) or ""),
          path    = path,
        }
      end
    end
  end
  return out
end

-- Every menu command of the frontmost app, searchable. The menu tree arrives
-- asynchronously — asking for it synchronously stalls the app being queried.
function M.menuPalette()
  local app = hs.application.frontmostApplication()
  if not app then return hs.alert.show("No frontmost app", 2) end

  app:getMenuItems(function(menus)
    if not menus then return hs.alert.show("This app exposes no menu", 2) end
    local choices = flatten(menus, {}, {})
    if #choices == 0 then return hs.alert.show("No menu commands found", 2) end

    M._menuChooser = M._menuChooser or hs.chooser.new(function(choice)
      if not choice then return end
      app:selectMenuItem(choice.path)
    end)
    M._menuChooser:placeholderText(("%s — %d menu commands"):format(app:name(), #choices))
    M._menuChooser:searchSubText(true)
    M._menuChooser:bgDark(true)
    M._menuChooser:width(40)
    M._menuChooser:rows(14)
    M._menuChooser:choices(choices)
    M._menuChooser:show()
  end)
end

-- ─── Cursor under the keyboard ──────────────────────────────────

M._mouseModal = nil

-- For whatever refuses to be pressed: move the pointer and click it. Held as a
-- modal so the keys mean this only while the mode is on, and the alert says so.
function M.mouseKeys()
  if M._mouseModal then
    M._mouseModal:exit()
    return
  end

  local modal = hs.hotkey.modal.new()
  M._mouseModal = modal

  local function move(dx, dy)
    return function()
      local p = hs.mouse.absolutePosition()
      local step = M.config.step
      hs.mouse.absolutePosition({ x = p.x + dx * step, y = p.y + dy * step })
    end
  end
  local function moveBig(dx, dy)
    return function()
      local p = hs.mouse.absolutePosition()
      local step = M.config.bigStep
      hs.mouse.absolutePosition({ x = p.x + dx * step, y = p.y + dy * step })
    end
  end

  for key, d in pairs({ h = { -1, 0 }, j = { 0, 1 }, k = { 0, -1 }, l = { 1, 0 } }) do
    modal:bind({}, key, move(d[1], d[2]), nil, move(d[1], d[2]))
    modal:bind({ "shift" }, key, moveBig(d[1], d[2]), nil, moveBig(d[1], d[2]))
  end

  modal:bind({}, "space", function() hs.eventtap.leftClick(hs.mouse.absolutePosition()) end)
  modal:bind({}, "return", function()
    hs.eventtap.leftClick(hs.mouse.absolutePosition())
    modal:exit()
  end)
  modal:bind({}, "c", function() hs.eventtap.rightClick(hs.mouse.absolutePosition()) end)
  modal:bind({}, "escape", function() modal:exit() end)
  modal:bind({}, "q", function() modal:exit() end)

  function modal:entered()
    hs.alert.show("Mouse keys — hjkl move · ⇧ faster · space click · c right-click · esc out",
      hs.alert.defaultStyle, hs.screen.mainScreen(), 3)
  end
  function modal:exited()
    M._mouseModal = nil
  end

  modal:enter()
end

-- Center the pointer on the focused window, so a mouse-keys session starts
-- somewhere useful rather than wherever it was left.
function M.centerMouse()
  local win = hs.window.focusedWindow()
  if not win then return end
  local f = win:frame()
  hs.mouse.absolutePosition({ x = f.x + f.w / 2, y = f.y + f.h / 2 })
end

-- ─── What is actually arriving ──────────────────────────────────
--
-- Keys typed on a keyboard paired to the *iPad* reach the Mac through Sidecar,
-- and letters land while chords sometimes do not. Guessing why is expensive, so
-- this records the raw stream — keycode, character and the modifier flags — and
-- whether hs.hotkey holds a binding for that exact combination. Run it, press
-- the chord that is not working, and the log says which half is missing.

M.KEYLOG = os.getenv("HOME") .. "/.cache/hs/keys.log"
M._logTap = nil

function M.logKeys()
  if M._logTap then
    M._logTap:stop()
    M._logTap = nil
    hs.alert.show("Key log stopped — " .. M.KEYLOG, 3)
    return
  end

  hs.fs.mkdir(os.getenv("HOME") .. "/.cache/hs")
  local f = io.open(M.KEYLOG, "a")
  if f then
    f:write(("\n=== %s  started ===\n"):format(os.date("%H:%M:%S")))
    f:close()
  end

  local types = { hs.eventtap.event.types.keyDown, hs.eventtap.event.types.flagsChanged }
  M._logTap = hs.eventtap.new(types, function(ev)
    local flags = ev:getFlags()
    local mods = {}
    for _, m in ipairs({ "ctrl", "alt", "shift", "cmd", "fn" }) do
      if flags[m] then mods[#mods + 1] = m end
    end
    local key = hs.keycodes.map[ev:getKeyCode()] or "?"
    local kind = ev:getType() == hs.eventtap.event.types.flagsChanged and "mods " or "key  "
    local line = ("%s %-6s %-10s [%s]  src=%d\n"):format(
      os.date("%H:%M:%S"), kind, key, table.concat(mods, "+"),
      ev:getProperty(hs.eventtap.event.properties.eventSourceUserData) or 0)
    local h = io.open(M.KEYLOG, "a")
    if h then h:write(line) h:close() end
    return false
  end)
  M._logTap:start()
  hs.alert.show("Key log ON — press the chord that fails, then run this again to stop", 5)
end

-- Scroll without reaching for anything, in the window under focus.
function M.scrollDown() hs.eventtap.scrollWheel({ 0, -5 }, {}, "line") end
function M.scrollUp()   hs.eventtap.scrollWheel({ 0,  5 }, {}, "line") end

return M
