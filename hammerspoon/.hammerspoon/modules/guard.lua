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

-- Convenience: bind a hotkey and register it with the guard
function M.bind(mods, key, fn)
  local hk = hs.hotkey.bind(mods, key, fn)
  return M.addHotkey(hk)
end

return M
