-- System utilities
local M = {}

-- Ctrl-tap-as-Escape
function M.startCtrlEscape()
  local sendEscape = false
  local lastMods = {}

  local timer = hs.timer.delayed.new(0.15, function()
    sendEscape = false
  end)

  M.ctrlTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(evt)
    local newMods = evt:getFlags()
    if lastMods["ctrl"] == newMods["ctrl"] then return false end
    if not lastMods["ctrl"] then
      lastMods = newMods
      sendEscape = true
      timer:start()
    else
      lastMods = newMods
      timer:stop()
      if sendEscape then
        return true, {
          hs.eventtap.event.newKeyEvent({}, "escape", true),
          hs.eventtap.event.newKeyEvent({}, "escape", false),
        }
      end
    end
    return false
  end)

  M.otherTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function()
    sendEscape = false
    return false
  end)

  M.ctrlTap:start()
  M.otherTap:start()
end

-- Brightness to 100% when plugging in
function M.startPowerWatcher()
  local lastSource = hs.battery.powerSource()
  M.powerWatcher = hs.battery.watcher.new(function()
    local current = hs.battery.powerSource()
    if lastSource ~= "AC Power" and current == "AC Power" then
      hs.brightness.set(100)
      hs.alert.show("⚡ Charging — brightness 100%", 1.5)
    end
    lastSource = current
  end)
  M.powerWatcher:start()
end

function M.toggleDarkMode()
  hs.osascript.applescript(
    'tell application "System Events" to tell appearance preferences to set dark mode to not dark mode'
  )
end

function M.emptyTrash()
  hs.osascript.applescript('tell application "Finder" to empty trash')
  hs.alert.show("Trash emptied", 1)
end

function M.togglePinchZoom()
  if M._pinchTap then
    M._pinchTap:stop()
    M._pinchTap = nil
    hs.alert.show("Pinch Zoom ON", 1)
  else
    -- NSEventTypeMagnify = 30, NSEventTypeSmartMagnify = 32
    M._pinchTap = hs.eventtap.new({ 30, 32 }, function()
      return true -- block all magnify/pinch events
    end)
    M._pinchTap:start()
    hs.alert.show("Pinch Zoom OFF", 1)
  end
end

function M.toggleSidecar(deviceName)
  deviceName = deviceName or "iPad"
  local script = string.format([[
    tell application "System Events"
      tell process "ControlCenter"
        try
          click menu bar item "Control Center" of menu bar 1
          delay 0.8
          set mirroringButton to (first checkbox of group 1 of window "Control Center" whose title contains "Mirroring")
          click mirroringButton
          delay 0.8
          set ipadItem to (first checkbox of scroll area 1 of group 1 of window "Control Center" whose title is "%s")
          click ipadItem
          delay 0.5
          key code 53
          return "ok"
        on error err
          key code 53
          return "error: " & err
        end try
      end tell
    end tell
  ]], deviceName)
  local ok, result = hs.osascript.applescript(script)
  if ok and result == "ok" then
    hs.alert.show("Sidecar: " .. deviceName, 1.5)
  else
    hs.alert.show("Sidecar failed — check console", 2)
  end
end

return M
