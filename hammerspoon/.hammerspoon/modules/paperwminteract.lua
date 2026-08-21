-- PaperWM widget: mouse/drag interaction — the map's only click surface.
-- Owns the mouseCallback, drag state, and the drop caret. Reads geometry
-- through the ctx getters the coordinator supplies; never rebuilds the map.
local M = {}

local geom = require("modules.paperwmgeom")
local model = require("modules.paperwmmodel")
local render = require("modules.paperwmrender")

local ACCENT = render.COLORS.ACCENT

local ctx = nil -- { boxes(), viewport(), sliders(), canvasFrame(), pinned(), togglePin(), afterUpdate(fn) }
local attachedCanvas = nil -- last canvas M.attach was installed on

local dragging = false
local drag = nil        -- {col, x0, moved}
local dragGuard = nil
local vpDrag = nil       -- {x0, offset0, maxOffset} while the screen frame is being dragged
local lastDrag = 0
local caret = nil        -- separate canvas: the main one cannot be rebuilt mid-drag

-- Slider/frame drags preview on every move (render.previewKnob — a pure
-- element mutation, no window write) and commit the one real window mutation
-- on mouseUp. Set >0 to also push a throttled real write during the drag
-- itself; 0 (default) is release-only.
M.LIVE_MS = 0

local pendingWin, pendingRatio = nil, nil -- width slider: committed on mouseUp
local pendingOffset = nil                 -- view slider / frame: committed on mouseUp

function M.isDragging()
  return dragging
end

local function maybeLiveWrite(fn)
  if M.LIVE_MS <= 0 then return end
  local now = hs.timer.secondsSinceEpoch()
  if now - lastDrag < M.LIVE_MS / 1000 then return end
  lastDrag = now
  fn()
end

-- Width slider: ratio for x, floor-clamped to what the window will accept.
-- The same value doubles as the preview frac and the eventual setWidth arg.
local function widthRatioAt(x)
  local sl = ctx.sliders()
  if not sl then return nil, nil end
  local cur = model.strip()
  local e = cur and sl.col and cur.columns[sl.col]
  local win = e and e.wins[1]
  if not win then return nil, nil end
  return win, math.max(model.floorRatio(win), math.min(1.0, (x - sl.x) / sl.w))
end

-- View slider: fraction along the strip's scrollable range for x, plus the
-- range itself so callers can turn the frac back into an absolute offset.
local function viewFracAt(x)
  local _, sl = ctx.sliders()
  if not (sl and sl.maxOffset and sl.maxOffset > 0) then return nil, nil end
  return math.max(0, math.min(1, (x - sl.x) / sl.w)), sl.maxOffset
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
        local frac, maxOffset = viewFracAt(x)
        if frac then
          pendingOffset = frac * maxOffset
          render.previewKnob("view", frac)
        end
      elseif message == "mouseMove" then
        if dragging then
          local frac, maxOffset = viewFracAt(x)
          if frac then
            pendingOffset = frac * maxOffset
            render.previewKnob("view", frac)
            maybeLiveWrite(function() model.scrollTo(pendingOffset) end)
          end
        end
      elseif message == "mouseUp" then
        dragging = false
        local frac, maxOffset = viewFracAt(x)
        if frac then pendingOffset = frac * maxOffset end
        if pendingOffset then model.scrollTo(pendingOffset) end
        pendingOffset = nil
        hs.timer.doAfter(0.4, function() ctx.afterUpdate() end)
      end
      return
    end

    -- the slider is the only control that tracks press and drag
    if tostring(id) == "slide:track" then
      if message == "mouseDown" then
        dragging = true
        local win, ratio = widthRatioAt(x)
        if ratio then
          pendingWin, pendingRatio = win, ratio
          render.previewKnob("width", ratio)
        end
      elseif message == "mouseMove" then
        if dragging then
          local win, ratio = widthRatioAt(x)
          if ratio then
            pendingWin, pendingRatio = win, ratio
            render.previewKnob("width", ratio)
            maybeLiveWrite(function() model.setWidth(pendingWin, pendingRatio) end)
          end
        end
      elseif message == "mouseUp" then
        dragging = false
        local win, ratio = widthRatioAt(x)
        if ratio then pendingWin, pendingRatio = win, ratio end
        if pendingWin and pendingRatio then model.setWidth(pendingWin, pendingRatio) end
        pendingWin, pendingRatio = nil, nil
        hs.timer.doAfter(0.4, function() ctx.afterUpdate() end)
      end
      return
    end

    -- dragging the screen frame scrolls the row
    if tostring(id) == "vp:frame" then
      if message == "mouseDown" then
        dragging = true
        local viewport = ctx.viewport()
        local _, sl = ctx.sliders()
        vpDrag = { x0 = x, offset0 = viewport and viewport.offset or 0, maxOffset = sl and sl.maxOffset or 0 }
        if dragGuard then dragGuard:stop() end
        dragGuard = hs.timer.doAfter(6, function()
          vpDrag, dragging, pendingOffset = nil, false, nil
          ctx.afterUpdate()
        end)
      elseif message == "mouseMove" then
        local viewport = ctx.viewport()
        if vpDrag and viewport then
          local offset = math.max(0, math.min(vpDrag.offset0 + (x - vpDrag.x0) / viewport.scale, vpDrag.maxOffset))
          pendingOffset = offset
          local frac = vpDrag.maxOffset > 0 and (offset / vpDrag.maxOffset) or 0
          render.previewKnob("view", frac)
          maybeLiveWrite(function() model.scrollTo(pendingOffset) end)
        end
      elseif message == "mouseUp" then
        local d = vpDrag
        local viewport = ctx.viewport()
        vpDrag, dragging = nil, false
        if dragGuard then dragGuard:stop(); dragGuard = nil end
        if d and viewport then
          pendingOffset = math.max(0, math.min(d.offset0 + (x - d.x0) / viewport.scale, d.maxOffset))
        end
        if pendingOffset then model.scrollTo(pendingOffset) end
        pendingOffset = nil
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

-- Reinstalling the callback on every redraw is unnecessary now that the
-- canvas is persistent — only do it when the canvas identity actually changes
-- (first draw, or a rare rebuild).
function M.ensureAttached(canvas, c)
  if canvas == attachedCanvas then return end
  attachedCanvas = canvas
  M.attach(canvas, c)
end

return M
