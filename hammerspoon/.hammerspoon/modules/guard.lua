-- Master on/off toggle via menubar icon
-- When disabled, all managed hotkeys are suspended
local M = {}

M.enabled = true
M.hotkeys = {}  -- list of hs.hotkey objects to manage
M.menubar = nil
M.onUpdate = nil  -- external callback for menubar updates

local function updateIcon()
  if M.menubar then
    if M.enabled then
      M.menubar:setTitle("🔨")
    else
      M.menubar:setTitle("⛔")
    end
  end
  if M.onUpdate then M.onUpdate() end
end

function M.addHotkey(hk)
  M.hotkeys[#M.hotkeys + 1] = hk
  if not M.enabled then hk:disable() end
  return hk
end

function M.toggle()
  M.enabled = not M.enabled
  for _, hk in ipairs(M.hotkeys) do
    if M.enabled then
      hk:enable()
    else
      hk:disable()
    end
  end
  updateIcon()
  hs.alert.show(M.enabled and "🔨 Hammerspoon ON" or "⛔ Hammerspoon OFF", 1.5)
end

function M.start(skipMenubar)
  if not skipMenubar then
    M.menubar = hs.menubar.new()
    if M.menubar then
      M.menubar:setClickCallback(M.toggle)
    end
  end
  updateIcon()
end

-- Convenience: bind a hotkey and register it with the guard.
--
-- Letters/digits/punctuation go through a FIXED US-ANSI keycode table, not
-- hs.keycodes.map: that map is built from the ACTIVE layout, so a reload while
-- Cyrillic is active has no "o" in it and hs.hotkey throws, aborting init.lua.
-- Named keys (Space, return, Left…) are layout-independent and use the map.
local ANSI = {
  a = 0, s = 1, d = 2, f = 3, h = 4, g = 5, z = 6, x = 7, c = 8, v = 9,
  b = 11, q = 12, w = 13, e = 14, r = 15, y = 16, t = 17, ["1"] = 18,
  ["2"] = 19, ["3"] = 20, ["4"] = 21, ["6"] = 22, ["5"] = 23, ["="] = 24,
  ["9"] = 25, ["7"] = 26, ["-"] = 27, ["8"] = 28, ["0"] = 29, ["]"] = 30,
  o = 31, u = 32, ["["] = 33, i = 34, p = 35, l = 37, j = 38, ["'"] = 39,
  k = 40, [";"] = 41, ["\\"] = 42, [","] = 43, ["/"] = 44, n = 45, m = 46,
  ["."] = 47, ["`"] = 50,
}

function M.bind(mods, key, fn)
  local code = key
  if type(key) == "string" then
    code = ANSI[key:lower()] or hs.keycodes.map[key] or hs.keycodes.map[key:lower()] or key
  end
  local hk = hs.hotkey.bind(mods, code, fn)
  return M.addHotkey(hk)
end

return M
