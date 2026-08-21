-- PaperWM widget: mouse/drag interaction — the map's only click surface.
-- Owns the mouseCallback, drag state, and the drop caret. Reads geometry
-- through the ctx getters the coordinator supplies; never rebuilds the map.
local M = {}

local geom = require("modules.paperwmgeom")
local model = require("modules.paperwmmodel")

local ACCENT = { red = 0.35, green = 0.65, blue = 1.00, alpha = 1 }

local ctx = nil -- { boxes(), viewport(), sliders(), canvasFrame(), pinned(), togglePin(), afterUpdate(fn) }

local dragging = false
local drag = nil        -- {col, x0, moved}
local dragGuard = nil
local vpDrag = nil       -- {x0, offset0} while the screen frame is being dragged
local lastDrag = 0
local caret = nil        -- separate canvas: the main one cannot be rebuilt mid-drag

function M.isDragging()
  return dragging
end

-- Slider: any percentage, not just the preset chips. x is canvas-relative.
function M.applySlider(x)
  local sl = ctx.sliders()
  if not sl then return end
  local cur = model.strip()
  local e = cur and sl.col and cur.columns[sl.col]
  local win = e and e.wins[1]
  if not win then return end
  local ratio = math.max(model.floorRatio(win), math.min(1.0, (x - sl.x) / sl.w))
  model.setWidth(win, ratio)
end

-- View slider: maps the track onto the scrollable range of the strip.
function M.applyScroll(x)
  local _, sl = ctx.sliders()
  if not (sl and sl.maxOffset and sl.maxOffset > 0) then return end
  local frac = math.max(0, math.min(1, (x - sl.x) / sl.w))
  model.scrollTo(frac * sl.maxOffset)
end

-- The drop marker lives on its own canvas so it can follow the pointer without
-- rebuilding the map, which would kill the mouse tracking mid-drag.
local function caretShow(col, toRight)
  local boxes, canvasFrame = ctx.boxes(), ctx.canvasFrame()
  if not (boxes and canvasFrame) then return end
  local b
  for _, box in ipairs(boxes) do if box.col == col then b = box end end
  if not b then return end

  if not caret then
    caret = hs.canvas.new({ x = 0, y = 0, w = 3, h = 10 })
    caret:level(hs.canvas.windowLevels.overlay)
    caret:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces |
      hs.canvas.windowBehaviors.stationary)
    caret:clickActivating(false)
    caret:canvasMouseEvents(false, false, false, false)
    caret:appendElements({ type = "rectangle", action = "fill", fillColor = ACCENT,
      roundedRectRadii = { xRadius = 2, yRadius = 2 } })
  end

  caret:frame({
    x = canvasFrame.x + (toRight and (b.x + b.w + 1) or (b.x - 4)),
    y = canvasFrame.y + geom.DIMS.PAD - 3,
    w = 3,
    h = geom.DIMS.BOX_H + 6,
  })
  caret:show()
end

local function caretHide()
  if caret then caret:hide() end
end

-- Resolve a drop: which column is under x, and move `from` there.
-- Public so the behaviour can be verified without synthesising mouse events.
function M.dropAt(from, x)
  local cur = model.strip()
  local to = geom.columnAt(x, ctx.boxes())
  if cur and to then model.moveColumn(cur.space, from, to) end
  return to
end

-- Installs the mouse callback on the render canvas. `c` supplies thin getters
-- so interact reads live draw geometry without owning it.
function M.attach(canvas, c)
  ctx = c

  canvas:mouseCallback(function(_, message, id, x, y)
    if not id then return end

    if tostring(id) == "close" then
      if message == "mouseUp" and ctx.pinned() then ctx.togglePin() end
      return
    end

    if tostring(id) == "vstep:-1" or tostring(id) == "vstep:1" then
      if message == "mouseUp" then
        model.scrollStep(tostring(id) == "vstep:1" and 1 or -1)
        hs.timer.doAfter(0.4, function() ctx.afterUpdate() end)
      end
      return
    end

    if tostring(id) == "scroll:track" then
      if message == "mouseDown" then
        dragging = true
        M.applyScroll(x)
      elseif message == "mouseMove" then
        if dragging then
          local now = hs.timer.secondsSinceEpoch()
          if now - lastDrag > 0.08 then
            lastDrag = now
            M.applyScroll(x)
          end
        end
      elseif message == "mouseUp" then
        dragging = false
        M.applyScroll(x)
        hs.timer.doAfter(0.4, function() ctx.afterUpdate() end)
      end
      return
    end

    -- the slider is the only control that tracks press and drag
    if tostring(id) == "slide:track" then
      if message == "mouseDown" then
        dragging = true
        M.applySlider(x)
      elseif message == "mouseMove" then
        if dragging then
          local now = hs.timer.secondsSinceEpoch()
          if now - lastDrag > 0.12 then
            lastDrag = now
            M.applySlider(x)
          end
        end
      elseif message == "mouseUp" then
        dragging = false
        M.applySlider(x)
        hs.timer.doAfter(0.4, function() ctx.afterUpdate() end)
      end
      return
    end

    -- dragging the screen frame scrolls the row
    if tostring(id) == "vp:frame" then
      if message == "mouseDown" then
        dragging = true
        local viewport = ctx.viewport()
        vpDrag = { x0 = x, offset0 = viewport and viewport.offset or 0 }
        if dragGuard then dragGuard:stop() end
        dragGuard = hs.timer.doAfter(6, function()
          vpDrag, dragging = nil, false
          ctx.afterUpdate()
        end)
      elseif message == "mouseMove" then
        local viewport = ctx.viewport()
        if vpDrag and viewport then
          local now = hs.timer.secondsSinceEpoch()
          if now - lastDrag > 0.06 then
            lastDrag = now
            local cur2 = model.strip()
            if cur2 then
              model.scrollToStrip(cur2, vpDrag.offset0 + (x - vpDrag.x0) / viewport.scale)
            end
          end
        end
      elseif message == "mouseUp" then
        local d = vpDrag
        local viewport = ctx.viewport()
        vpDrag, dragging = nil, false
        if dragGuard then dragGuard:stop(); dragGuard = nil end
        local cur2 = model.strip()
        if d and cur2 and viewport then
          model.scrollToStrip(cur2, d.offset0 + (x - d.x0) / viewport.scale)
        end
        hs.timer.doAfter(0.4, function() ctx.afterUpdate() end)
      end
      return
    end

    -- dragging a column box to reorder it
    local dk, dcol = tostring(id):match("^(focus):(%d+)$")
    if dk then
      dcol = tonumber(dcol)
      if message == "mouseDown" then
        dragging = true
        drag = { col = dcol, x0 = x, y0 = y, moved = false }
        -- if the release never arrives (mouse let go off-canvas) do not freeze
        if dragGuard then dragGuard:stop() end
        dragGuard = hs.timer.doAfter(6, function()
          drag, dragging = nil, false
          caretHide(); ctx.afterUpdate()
        end)
        return
      elseif message == "mouseMove" then
        if drag then
          if math.abs(x - drag.x0) > 6 then drag.moved = true end
          if drag.moved then
            local t = geom.columnAt(x, ctx.boxes())
            if t then caretShow(t, t >= drag.col) end
          end
        end
        return
      elseif message == "mouseUp" then
        local d = drag
        drag, dragging = nil, false
        if dragGuard then dragGuard:stop(); dragGuard = nil end
        caretHide()
        if d and d.moved then
          local dy = y - (d.y0 or y)
          local dx = x - d.x0
          if math.abs(dy) > math.abs(dx) and math.abs(dy) > 18 then
            -- a mostly-vertical drag changes the column stack instead of order:
            -- up folds the window into the column on its left, down pulls it out
            local cur2 = model.strip()
            local e = cur2 and cur2.columns[d.col]
            local win = e and e.wins[1]
            if win then
              if dy < 0 then model.stack(win) else model.unstack(win) end
            end
          else
            M.dropAt(d.col, x)
          end
        else
          -- never moved: it was a plain click, so just focus that column
          local cur2 = model.strip()
          local e = cur2 and cur2.columns[dcol]
          if e and e.wins[1] then e.wins[1]:focus() end
        end
        ctx.afterUpdate()
        return
      end
    end

    if message ~= "mouseUp" then return end
    local cur = model.strip()
    if not cur then return end

    local kind, arg = tostring(id):match("^(%a+):(.+)$")

    -- focus:N is handled above by the drag branch
    if kind == "left" or kind == "right" then
      local c = tonumber(arg)
      model.moveColumn(cur.space, c, c + ((kind == "left") and -1 or 1))
    elseif kind == "unfloat" then
      local w = hs.window.get(tonumber(arg))
      if w then model.toggleFloat(w) end
    elseif kind == "w" then
      local e = cur.col and cur.columns[cur.col]
      if not (e and e.wins[1]) then return end
      if arg == "full" then model.fullWidth(e.wins[1]) else model.setWidth(e.wins[1], tonumber(arg)) end
    elseif kind == "act" then
      local e = cur.col and cur.columns[cur.col]
      local win = e and e.wins[1]
      if not win then return end
      if arg == "slurp" then
        model.stack(win)
      elseif arg == "barf" then
        model.unstack(win)
      elseif arg == "float" then
        model.toggleFloat(win)
      end
    end
  end)
end

return M
