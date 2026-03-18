-- Window management
local M = {}

local positions = {
  left_half        = { x = 0, y = 0, w = 0.5, h = 1 },
  right_half       = { x = 0.5, y = 0, w = 0.5, h = 1 },
  left_third       = { x = 0, y = 0, w = 0.33, h = 1 },
  center_third     = { x = 0.33, y = 0, w = 0.34, h = 1 },
  right_third      = { x = 0.66, y = 0, w = 0.34, h = 1 },
  left_two_thirds  = { x = 0, y = 0, w = 0.66, h = 1 },
  right_two_thirds = { x = 0.33, y = 0, w = 0.67, h = 1 },
  center_half      = { x = 0.25, y = 0, w = 0.5, h = 1 },
  top_half         = { x = 0, y = 0, w = 1, h = 0.5 },
  bottom_half      = { x = 0, y = 0.5, w = 1, h = 0.5 },
}

function M.move(pos_name)
  return function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local rect = positions[pos_name]
    if rect then
      win:moveToUnit(rect, 0)
    end
  end
end

function M.maximize()
  local win = hs.window.focusedWindow()
  if win then win:maximize(0) end
end

function M.center()
  local win = hs.window.focusedWindow()
  if win then win:centerOnScreen(nil, true, 0) end
end

function M.screenLeft()
  local win = hs.window.focusedWindow()
  if win then win:moveOneScreenWest(nil, true, 0) end
end

function M.screenRight()
  local win = hs.window.focusedWindow()
  if win then win:moveOneScreenEast(nil, true, 0) end
end

return M
