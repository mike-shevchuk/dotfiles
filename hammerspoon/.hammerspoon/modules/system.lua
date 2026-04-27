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

local _PINCH_KEY  = "hs.pinchZoomBlocked"
local _SCROLL_KEY = "hs.scrollMultiplier"

M._scrollMult  = 1.0
M._scrollTap   = nil
local _scrollPanel = nil

-- ─── Pinch Zoom ─────────────────────────────────────────────────

-- Write system trackpad defaults so browsers/terminals also respect the block.
-- This is equivalent to toggling "Zoom in or out" in System Settings → Trackpad.
local function _setSystemPinch(enabled)
  local v = enabled and 1 or 0
  -- Write to both built-in and Bluetooth trackpad domains.
  -- killall -HUP cfprefsd forces the preferences daemon to re-read from disk
  -- so already-running apps (Chrome, Terminal) pick it up without restart.
  hs.execute(string.format(
    "defaults write com.apple.AppleMultitouchTrackpad TrackpadPinch -int %d && " ..
    "defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadPinch -int %d && " ..
    "killall -HUP cfprefsd",
    v, v
  ))
end

function M.isPinchZoomBlocked()
  return M._pinchTap ~= nil
end

function M.togglePinchZoom()
  if M._pinchTap then
    M._pinchTap:stop()
    M._pinchTap = nil
    _setSystemPinch(true)
    hs.settings.set(_PINCH_KEY, false)
    hs.alert.show("Pinch Zoom ON", 1)
  else
    -- NSEventTypeMagnify = 30, NSEventTypeSmartMagnify = 32
    M._pinchTap = hs.eventtap.new({ 30, 32 }, function()
      return true -- block at CGEvent level (fast path for most apps)
    end)
    M._pinchTap:start()
    _setSystemPinch(false)  -- also block at driver/defaults level (browsers, terminals)
    hs.settings.set(_PINCH_KEY, true)
    hs.alert.show("Pinch Zoom OFF", 1)
  end
end

-- ─── Scroll Speed ───────────────────────────────────────────────

-- Single long-lived eventtap; reads M._scrollMult dynamically each event.
local function _applyScrollMult(evt)
  if M._scrollMult == 1.0 then return false end
  local p = hs.eventtap.event.properties
  for _, axis in ipairs({
    p.scrollWheelEventPointDeltaAxis1,
    p.scrollWheelEventPointDeltaAxis2,
    p.scrollWheelEventFixedPtDeltaAxis1,
    p.scrollWheelEventFixedPtDeltaAxis2,
  }) do
    evt:setProperty(axis, evt:getProperty(axis) * M._scrollMult)
  end
  return false
end

function M.getScrollMultiplier() return M._scrollMult end

-- silent=true skips the alert (used by the slider panel during dragging)
function M.setScrollMultiplier(mult, silent)
  M._scrollMult = mult
  hs.settings.set(_SCROLL_KEY, mult)
  if mult == 1.0 then
    if M._scrollTap then M._scrollTap:stop(); M._scrollTap = nil end
  elseif not M._scrollTap then
    M._scrollTap = hs.eventtap.new({ hs.eventtap.event.types.scrollWheel }, _applyScrollMult)
    M._scrollTap:start()
  end
  if not silent then hs.alert.show(string.format("Scroll: %.1fx", mult), 1) end
end

-- ─── Scroll Speed Panel (floating slider) ───────────────────────

local _SCROLL_HTML = [[
<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  :root{color-scheme:dark}
  *{box-sizing:border-box;margin:0;padding:0}
  body{
    font-family:-apple-system,sans-serif;
    background:#242424;color:#e8e8e8;
    padding:14px 16px 12px;
    display:flex;flex-direction:column;gap:6px;
  }
  .val{font-size:32px;font-weight:700;text-align:center;color:#fff;letter-spacing:-1px}
  input[type=range]{
    -webkit-appearance:none;width:100%;height:4px;
    background:#484848;border-radius:2px;outline:none;margin:4px 0;
  }
  input[type=range]::-webkit-slider-thumb{
    -webkit-appearance:none;width:20px;height:20px;
    border-radius:50%;background:#4a9eff;cursor:pointer;
    box-shadow:0 1px 4px rgba(0,0,0,.5);
  }
  .ticks{display:flex;justify-content:space-between;font-size:10px;color:#666}
  .reset{
    font-size:12px;padding:5px 16px;background:transparent;
    color:#4a9eff;border:1px solid rgba(74,158,255,.35);border-radius:6px;
    cursor:pointer;align-self:center;margin-top:4px;
  }
  .reset:hover{background:rgba(74,158,255,.15)}
</style></head><body>
  <div class="val" id="val">__MULTx__</div>
  <input type="range" id="sl" min="0.2" max="5.0" step="0.1" value="__MULT__"
         oninput="slide(this.value)">
  <div class="ticks">
    <span>0.2x</span><span>1x</span><span>2x</span><span>3x</span><span>5x</span>
  </div>
  <button class="reset" onclick="reset()">Reset to 1x</button>
  <script>
    function slide(v){
      v=parseFloat(v);
      document.getElementById('val').textContent=v.toFixed(1)+'x';
      window.webkit.messageHandlers.scrollPanel.postMessage({action:'set',value:v});
    }
    function reset(){document.getElementById('sl').value=1.0;slide(1.0)}
  </script>
</body></html>
]]

function M.showScrollPanel()
  if _scrollPanel then
    pcall(function() _scrollPanel:delete() end)
    _scrollPanel = nil
    return
  end

  local uc = hs.webview.usercontent.new("scrollPanel")
  uc:setCallback(function(msg)
    local b = msg.body
    if b.action == "set" then
      M.setScrollMultiplier(b.value, true) -- silent while dragging
    end
  end)

  local mult = M._scrollMult
  local multFmt = string.format("%.1f", mult)
  local html = _SCROLL_HTML
    :gsub("__MULTx__", multFmt .. "x")
    :gsub("__MULT__",  multFmt)

  local screen = hs.screen.mainScreen():frame()
  local w, h = 260, 148
  _scrollPanel = hs.webview.new(
    { x = screen.x + screen.w - w - 20, y = screen.y + 28, w = w, h = h },
    { developerExtrasEnabled = false },
    uc
  )
  _scrollPanel:windowStyle({ "titled", "closable" })
  _scrollPanel:windowTitle("Scroll Speed")
  _scrollPanel:level(hs.drawing.windowLevels.floating)
  _scrollPanel:html(html)
  _scrollPanel:show()
end

-- ─── Restore persisted trackpad settings after reload ───────────
do
  if hs.settings.get(_PINCH_KEY) then
    M._pinchTap = hs.eventtap.new({ 30, 32 }, function() return true end)
    M._pinchTap:start()
    _setSystemPinch(false) -- keep system defaults in sync
  else
    _setSystemPinch(true)  -- ensure defaults are clean on reload
  end
  local savedMult = hs.settings.get(_SCROLL_KEY) or 1.0
  if savedMult ~= 1.0 then M.setScrollMultiplier(savedMult, true)
  else M._scrollMult = 1.0 end
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
