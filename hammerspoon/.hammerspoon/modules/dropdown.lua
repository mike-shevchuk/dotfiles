-- Quake-style dropdown terminal
-- Press hotkey to slide Ghostty down from top, press again to hide
local M = {}

M.appName = "iTerm2"
M.visible = false
M.width = 0.8   -- 80% of screen width
M.height = 0.45 -- 45% of screen height

function M.toggle()
  local app = hs.application.get(M.appName)

  if not app then
    -- Launch and wait for window
    hs.application.launchOrFocus(M.appName)
    hs.timer.doAfter(1, function()
      app = hs.application.get(M.appName)
      if app then M.positionWindow(app) end
    end)
    M.visible = true
    return
  end

  if M.visible and app:isFrontmost() then
    -- Hide
    app:hide()
    M.visible = false
  else
    -- Show and position
    app:unhide()
    app:activate()
    M.positionWindow(app)
    M.visible = true
  end
end

function M.positionWindow(app)
  local win = app:mainWindow()
  if not win then return end

  local screen = hs.screen.mainScreen():frame()
  local w = math.floor(screen.w * M.width)
  local h = math.floor(screen.h * M.height)
  local x = screen.x + math.floor((screen.w - w) / 2)
  local y = screen.y

  win:setFrame({ x = x, y = y, w = w, h = h }, 0)
end

return M
