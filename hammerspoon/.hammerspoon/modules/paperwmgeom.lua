-- Pure geometry + redraw-tier math for the PaperWM widget.
-- Zero dependencies: loads under plain `lua`, calls no hs.* — so every function
-- here is unit-testable without a running Hammerspoon.
local M = {}

M.DIMS = {
  STRIP_W = 560, BOX_H = 42, GAP = 6, PAD = 22,
  MIN_BOX = 46, FLOAT_W = 74, SEP = 18,
  CHIP_H = 22, CHIP_G = 5, SLIDER_H = 24, SLIDER_MAXW = 420,
  WIDTH_CHIP = 44, ACT_CHIP = 60,
}

-- The map covers the whole strip; every column keeps its true proportion and a
-- frame marks the visible slice. (moved from paperwmui.layout)
function M.layout(s, dims)
  dims = dims or M.DIMS
  local PAD, STRIP_W, GAP, FLOAT_W, SEP = dims.PAD, dims.STRIP_W, dims.GAP, dims.FLOAT_W, dims.SEP
  local mapW = STRIP_W
  local scale = s.stripW > 0 and (mapW / s.stripW) or 1

  local boxes = {}
  for col, e in ipairs(s.columns) do
    boxes[#boxes + 1] = {
      col = col, entry = e,
      x = PAD + (e.vx - s.left) * scale,
      w = math.max(8, e.px * scale),
    }
  end

  local viewport = {
    x = PAD + (s.canvas.x - s.left) * scale,
    w = s.canvas.w * scale,
    offset = s.canvas.x - s.left,
    scale = scale,
  }

  local x = PAD + mapW
  local floats = {}
  if #s.floating > 0 then
    x = x + SEP
    for _, w in ipairs(s.floating) do
      floats[#floats + 1] = { x = x, w = FLOAT_W, win = w }
      x = x + FLOAT_W + GAP
    end
    x = x - GAP
  end

  return boxes, floats, x + PAD, viewport
end

-- which column the pointer is over (moved from paperwmui.columnAt, boxes param)
function M.columnAt(x, boxes)
  if not boxes or #boxes == 0 then return nil end
  for _, b in ipairs(boxes) do
    if x >= b.x and x <= b.x + b.w then return b.col end
  end
  return x < boxes[1].x and boxes[1].col or boxes[#boxes].col
end

function M.chipsWidth(chips, dims)
  dims = dims or M.DIMS
  local total = 0
  for i, c in ipairs(chips) do
    total = total + (c.gap and 12 or c.w)
    if i < #chips then total = total + dims.CHIP_G end
  end
  return total
end

function M.clampOffset(offset, stripW, canvasW)
  local maxOffset = math.max(0, stripW - canvasW)
  return math.max(0, math.min(offset, maxOffset))
end

-- Stable string fingerprint of what the map draws. Order is by each column's
-- first-window id so a reorder changes the hash; widths are rounded to the px so
-- sub-pixel jitter does not force a redraw. Floating ids are sorted.
function M.stripHash(s)
  local parts = { "c=" .. tostring(s.col) }
  for _, e in ipairs(s.columns) do
    local first = e.wins and e.wins[1]
    local id = first and (first.id and (type(first.id) == "function" and first:id() or first.id)) or "?"
    parts[#parts + 1] = tostring(id) .. ":" .. tostring(math.floor((e.px or 0) + 0.5))
  end
  local fids = {}
  for _, w in ipairs(s.floating or {}) do
    fids[#fids + 1] = tostring(w.id and (type(w.id) == "function" and w:id() or w.id) or "?")
  end
  table.sort(fids)
  parts[#parts + 1] = "f=" .. table.concat(fids, ",")
  return table.concat(parts, "|")
end

function M.redrawTier(prevHash, newHash)
  if prevHash == newHash then return "none" end
  return "full"
end

return M
