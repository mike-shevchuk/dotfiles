-- Highlight the focused window with a border.
-- Drawn as four thin strips placed just OUTSIDE the window frame, in the gap
-- PaperWM leaves between windows — a single canvas covering the window would
-- risk swallowing clicks over its whole area.
-- Colour doubles as a state readout: blue = tiled, amber = floating.
local M = {}

local paperwm = require("modules.paperwm")

local THICK = 3
local TILED    = { red = 0.35, green = 0.65, blue = 1.00, alpha = 0.95 }
local FLOATING = { red = 0.95, green = 0.68, blue = 0.20, alpha = 0.95 }

M.enabled = true
M.edges = nil
M.filter = nil
M.lastWin = nil
M.settleTimer = nil

local function makeEdges()
  local edges = {}
  for i = 1, 4 do
    local c = hs.canvas.new({ x = 0, y = 0, w = 1, h = 1 })
    c:level(hs.canvas.windowLevels.floating)
    c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces |
      hs.canvas.windowBehaviors.stationary)
    c:clickActivating(false)
    -- no element tracks the mouse, so clicks pass straight through
    c:canvasMouseEvents(false, false, false, false)
    c:appendElements({ type = "rectangle", action = "fill",
      fillColor = TILED, roundedRectRadii = { xRadius = 1.5, yRadius = 1.5 } })
    edges[i] = c
  end
  return edges
end

local function hide()
  if not M.edges then return end
  for _, c in ipairs(M.edges) do c:hide() end
end

local function paint(frame, color)
  if not M.edges then M.edges = makeEdges() end
  local t = THICK

  local rects = {
    { x = frame.x - t,     y = frame.y - t,     w = frame.w + t * 2, h = t },        -- top
    { x = frame.x - t,     y = frame.y + frame.h, w = frame.w + t * 2, h = t },      -- bottom
    { x = frame.x - t,     y = frame.y,         w = t,               h = frame.h },  -- left
    { x = frame.x + frame.w, y = frame.y,       w = t,               h = frame.h },  -- right
  }

  for i, c in ipairs(M.edges) do
    c:frame(rects[i])
    c[1].fillColor = color
    c:show()
  end
end

function M.refresh()
  if not M.enabled then hide(); return end

  local win = hs.window.focusedWindow()
  -- focusedWindow() is intermittently nil; keep the last one rather than
  -- letting the border flicker off
  if win then
    M.lastWin = win
  else
    win = M.lastWin
  end

  if not (win and win:isStandard() and win:isVisible()) then hide(); return end

  local pwm = paperwm.pwm
  local floating = pwm and pwm.floating.isFloating(win) or false
  -- an untracked window is not worth outlining as "tiled"
  if pwm and paperwm.running and not floating and not pwm.state.isTiled(win:id()) then
    hide()
    return
  end

  paint(win:frame(), floating and FLOATING or TILED)
end

-- windows animate into place, so repaint once the movement has landed
local function refreshSoon()
  M.refresh()
  if M.settleTimer then M.settleTimer:stop() end
  M.settleTimer = hs.timer.doAfter(0.28, M.refresh)
end

function M.toggle()
  M.enabled = not M.enabled
  M.refresh()
  hs.alert.show(M.enabled and "▢ focus border on" or "▢ focus border off", 1)
end

function M.start()
  M.edges = makeEdges()

  M.filter = paperwm.subscribe({
    hs.window.filter.windowFocused,
    hs.window.filter.windowUnfocused,
    hs.window.filter.windowMoved,
    hs.window.filter.windowCreated,
    hs.window.filter.windowDestroyed,
  }, refreshSoon)

  -- screen layout changes move every window at once
  M.screenWatcher = hs.screen.watcher.new(refreshSoon):start()

  M.refresh()
end

return M
