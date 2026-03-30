-- Mouse finder: show a pulsing circle around the cursor
local M = {}

local canvas = nil
local timer = nil
local SIZE = 120

function M.find()
  -- Clean up any existing highlight
  if canvas then canvas:delete() end
  if timer then timer:stop() end

  local pos = hs.mouse.absolutePosition()
  local x = pos.x - SIZE / 2
  local y = pos.y - SIZE / 2

  canvas = hs.canvas.new({ x = x, y = y, w = SIZE, h = SIZE })
  canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  canvas:level(hs.canvas.windowLevels.overlay)

  -- Outer ring
  canvas[1] = {
    type = "circle",
    center = { x = SIZE / 2, y = SIZE / 2 },
    radius = SIZE / 2 - 4,
    action = "stroke",
    strokeColor = { red = 1, green = 0.3, blue = 0.1, alpha = 0.9 },
    strokeWidth = 4,
  }
  -- Inner ring
  canvas[2] = {
    type = "circle",
    center = { x = SIZE / 2, y = SIZE / 2 },
    radius = SIZE / 4,
    action = "stroke",
    strokeColor = { red = 1, green = 0.5, blue = 0, alpha = 0.7 },
    strokeWidth = 3,
  }
  -- Crosshair horizontal
  canvas[3] = {
    type = "segments",
    coordinates = {
      { x = 0, y = SIZE / 2 },
      { x = SIZE, y = SIZE / 2 },
    },
    action = "stroke",
    strokeColor = { red = 1, green = 0.3, blue = 0.1, alpha = 0.6 },
    strokeWidth = 2,
  }
  -- Crosshair vertical
  canvas[4] = {
    type = "segments",
    coordinates = {
      { x = SIZE / 2, y = 0 },
      { x = SIZE / 2, y = SIZE },
    },
    action = "stroke",
    strokeColor = { red = 1, green = 0.3, blue = 0.1, alpha = 0.6 },
    strokeWidth = 2,
  }

  canvas:show()

  -- Fade out after 1.5 seconds
  local step = 0
  timer = hs.timer.doEvery(0.05, function()
    step = step + 1
    if step > 30 then
      if canvas then canvas:delete(); canvas = nil end
      if timer then timer:stop(); timer = nil end
      return
    end
    local alpha = 1 - (step / 30)
    if canvas then
      canvas[1].strokeColor.alpha = 0.9 * alpha
      canvas[2].strokeColor.alpha = 0.7 * alpha
      canvas[3].strokeColor.alpha = 0.6 * alpha
      canvas[4].strokeColor.alpha = 0.6 * alpha
      -- Follow mouse
      local p = hs.mouse.absolutePosition()
      canvas:topLeft({ x = p.x - SIZE / 2, y = p.y - SIZE / 2 })
    end
  end)
end

return M
