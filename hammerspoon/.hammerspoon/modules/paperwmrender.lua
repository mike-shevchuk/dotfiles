-- PaperWM widget: canvas drawing. Owns the persistent hs.canvas and every
-- element built for it. Never touches the mouseCallback (that is interact's
-- job) and never touches pwm internals (that is model's job).
local M = {}

local geom = require("modules.paperwmgeom")
local model = require("modules.paperwmmodel")

-- Single home for the palette — interact sources ACCENT from here too.
M.COLORS = {
  ACCENT   = { red = 0.35, green = 0.65, blue = 1.00, alpha = 1 },
  WARN     = { red = 0.95, green = 0.68, blue = 0.20, alpha = 1 },
  FILL_ON  = { red = 0.13, green = 0.31, blue = 0.53, alpha = 0.95 },
  FILL_OFF = { red = 0.11, green = 0.13, blue = 0.16, alpha = 0.95 },
  FILL_FLT = { red = 0.22, green = 0.17, blue = 0.06, alpha = 0.95 },
  EDGE_OFF = { red = 0.25, green = 0.28, blue = 0.32, alpha = 1 },
  BG       = { red = 0.05, green = 0.06, blue = 0.08, alpha = 0.90 },
}
local ACCENT, WARN, FILL_ON, FILL_OFF, FILL_FLT, EDGE_OFF, BG =
    M.COLORS.ACCENT, M.COLORS.WARN, M.COLORS.FILL_ON, M.COLORS.FILL_OFF,
    M.COLORS.FILL_FLT, M.COLORS.EDGE_OFF, M.COLORS.BG

local DIMS = geom.DIMS
local STRIP_W, BOX_H, PAD = DIMS.STRIP_W, DIMS.BOX_H, DIMS.PAD
local CHIP_H, CHIP_G = DIMS.CHIP_H, DIMS.CHIP_G
local SLIDER_H, SLIDER_MAXW = DIMS.SLIDER_H, DIMS.SLIDER_MAXW
local WIDTH_CHIP, ACT_CHIP = DIMS.WIDTH_CHIP, DIMS.ACT_CHIP

-- persistent canvas: created once, reused (replaceElements) on every redraw
local canvas = nil
local frame = nil -- last frame set on `canvas`, to detect when it must move

-- Two-tier redraw bookkeeping: M.lastTier is the {hash, col} of what's on
-- screen, M.lastGeom is the geometry table handed back to `interact`
-- (unchanged by a "none"/"cheap" redraw), M.boxIdx maps col -> the element
-- indices of that column's box (rect/texts/label) recorded by the last full
-- build, so a "cheap" redraw can restyle just two boxes in place. M.lastPinned
-- is the pinned state of the last full build — pinned toggles the chip
-- row/sliders/EDIT-close button/chevrons and the box rects' mouse-tracking
-- flags, none of which stripHash sees, so a pinned change always forces full.
M.lastTier = nil
M.lastGeom = nil
M.boxIdx = nil
M.lastPinned = nil

-- Element indices for the two things a slider/frame drag previews in place:
-- M.knobIdx.width = {fillIdx, knobIdx, sx, sw, y} (width slider fill+knob),
-- M.knobIdx.vpFrame = {idx, w} (the viewport-frame rectangle). Captured on
-- every full build (below), like M.boxIdx; nil when the strip is unpinned
-- (those elements are not drawn, and drags on them are not possible either).
M.knobIdx = nil

function M.canvas() return canvas end

-- Moves only the given track's own visual in place — a pure element mutation,
-- no `model` call and no window write. Used by `interact` on every mouseMove
-- of a slider/frame drag; the real model.setWidth/scrollTo happens once, on
-- release. track == "width" moves the width slider's own knob+fill; "view"
-- moves the viewport-frame rectangle (the on-strip "screen" outline) — that
-- is the shared visual for both the view slider and dragging the frame itself.
function M.previewKnob(track, frac)
  if not (canvas and M.knobIdx) then return end
  frac = math.max(0, math.min(1, frac))
  if track == "width" then
    local k = M.knobIdx.width
    if not k then return end
    canvas[k.fillIdx].frame = { x = k.sx, y = k.y + SLIDER_H / 2 - 3, w = k.sw * frac, h = 6 }
    canvas[k.knobIdx].center = { x = k.sx + k.sw * frac, y = k.y + SLIDER_H / 2 }
  elseif track == "view" then
    local v = M.knobIdx.vpFrame
    if not v then return end
    canvas[v.idx].frame = { x = PAD + frac * (STRIP_W - v.w), y = PAD - 5, w = v.w, h = BOX_H + 10 }
  end
end

-- Restyles exactly the previously-focused and newly-focused boxes in place
-- (fillColor/strokeColor/text color), via indexed element assignment, using
-- the element indices recorded on the last full build. Either col may be nil
-- (no previous/new focus).
function M.recolorFocus(oldCol, newCol)
  local function style(col, isCurrent)
    local idx = M.boxIdx and M.boxIdx[col]
    if not idx then return end
    canvas[idx.rect].fillColor = isCurrent and FILL_ON or FILL_OFF
    canvas[idx.rect].strokeColor = isCurrent and ACCENT or EDGE_OFF
    canvas[idx.rect].strokeWidth = isCurrent and 2 or 1
    for _, ti in ipairs(idx.texts) do
      canvas[ti].textColor = isCurrent and { white = 1, alpha = 1 } or { white = 0.72, alpha = 1 }
    end
    if idx.label then
      canvas[idx.label].textColor = isCurrent and { white = 0.92, alpha = 1 } or { white = 0.45, alpha = 1 }
    end
  end
  if oldCol then style(oldCol, false) end
  if newCol then style(newCol, true) end
end

function M.hide()
  if canvas then canvas:hide() end
end

local function chipRow(s)
  local chips = {}
  if s.col then
    for _, r in ipairs(model.widthRatios()) do
      chips[#chips + 1] = {
        text = string.format("%d%%", math.floor(r * 100 + 0.5)),
        id = "w:" .. tostring(r), w = WIDTH_CHIP, ratio = r,
      }
    end
    chips[#chips + 1] = { text = "⤢", id = "w:full", w = WIDTH_CHIP }
    chips[#chips + 1] = { gap = true }
    chips[#chips + 1] = { text = "stack", id = "act:slurp", w = ACT_CHIP }
    chips[#chips + 1] = { text = "unstack", id = "act:barf", w = ACT_CHIP }
    chips[#chips + 1] = { text = "float", id = "act:float", w = ACT_CHIP }
  end
  return chips
end

-- Builds the element list for the strip map and (re)draws the persistent
-- canvas. `opts = { pinned, screen }`. Returns the geometry the coordinator
-- publishes for `interact` to read: { boxes, floats, viewport, canvasFrame,
-- slider, scrollSlider, canvas }.
function M.draw(s, opts)
  local pinned = opts.pinned
  local screen = opts.screen

  -- Two-tier redraw: "none" (nothing moved) and "cheap" (only the focused
  -- column changed) skip the full build below. Cheap is restricted to the
  -- unpinned strip — while pinned, the chip row and sliders also read s.col
  -- (active width chip, slider fraction), so those need the full rebuild too.
  -- A pinned-state flip is forced to "full" regardless of hash/col: pinned
  -- gates whole element groups (chips, sliders, EDIT/close, chevrons) and the
  -- box rects' trackMouseDown/Up/Move flags, none of which stripHash covers.
  local newHash = geom.stripHash(s)
  local tier = geom.redrawTier(M.lastTier, { hash = newHash, col = s.col })
  if pinned ~= M.lastPinned then
    tier = "full"
  end
  if tier == "none" and M.lastGeom then
    -- match the full path, which always ends with canvas:show() — a "none"
    -- redraw right after an auto-hidden flash must still bring it back.
    if canvas then canvas:show() end
    return M.lastGeom
  end
  if tier == "cheap" and not pinned and canvas and M.lastGeom and M.lastTier
      and M.boxIdx and M.boxIdx[M.lastTier.col] and M.boxIdx[s.col] then
    M.recolorFocus(M.lastTier.col, s.col)
    M.lastTier = { hash = newHash, col = s.col }
    canvas:show()
    return M.lastGeom
  end

  local boxes, floats, total_w, viewport = geom.layout(s, DIMS)
  local chips = pinned and chipRow(s) or {}
  local has_chips = #chips > 0
  if has_chips then
    total_w = math.max(total_w, geom.chipsWidth(chips, DIMS) + PAD * 2, 440 + PAD * 2)
  end
  local height = PAD * 2 + BOX_H + (has_chips and (CHIP_H + 6 + (SLIDER_H + 4) * 2) or 0)

  local f = screen:frame()
  local cf = {
    x = f.x + (f.w - total_w) / 2,
    y = f.y2 - height - 64,
    w = total_w,
    h = height,
  }

  local els = { {
    type = "rectangle",
    action = "fill",
    fillColor = BG,
    roundedRectRadii = { xRadius = 12, yRadius = 12 },
  } }

  -- faint rail showing the whole strip, so gaps and off-screen space read
  els[#els + 1] = {
    type = "rectangle", action = "fill",
    frame = { x = PAD, y = PAD + BOX_H / 2 - 1, w = STRIP_W, h = 2 },
    fillColor = { white = 0.18, alpha = 1 },
  }

  local newBoxIdx = {}
  local newKnobIdx = {}
  for _, b in ipairs(boxes) do
    local col, e = b.col, b.entry
    local current = (col == s.col)

    els[#els + 1] = {
      type = "rectangle",
      action = "strokeAndFill",
      frame = { x = b.x, y = PAD, w = b.w, h = BOX_H },
      fillColor = current and FILL_ON or FILL_OFF,
      strokeColor = current and ACCENT or EDGE_OFF,
      strokeWidth = current and 2 or 1,
      roundedRectRadii = { xRadius = 7, yRadius = 7 },
      id = "focus:" .. col,
      trackMouseDown = pinned,
      trackMouseUp = pinned,
      trackMouseMove = pinned,
    }
    local rectIdx = #els

    local rows = #e.wins
    local textIdxs = {}
    for row = 1, rows do
      local rh = (BOX_H - 15) / rows
      els[#els + 1] = {
        type = "text",
        frame = { x = b.x + 3, y = PAD + 3 + (row - 1) * rh, w = b.w - 6, h = rh + 2 },
        text = model.shortName(e.wins[row]),
        textSize = 10.5,
        textColor = current and { white = 1, alpha = 1 } or { white = 0.72, alpha = 1 },
        textAlignment = "center",
      }
      textIdxs[#textIdxs + 1] = #els
    end

    -- width readout doubles as the order label
    els[#els + 1] = {
      type = "text",
      frame = { x = b.x, y = PAD + BOX_H - 14, w = b.w, h = 13 },
      text = string.format("%d · %d%%", col, math.floor(e.ratio * 100 + 0.5)),
      textSize = 9,
      textColor = current and { white = 0.92, alpha = 1 } or { white = 0.45, alpha = 1 },
      textAlignment = "center",
    }
    local labelIdx = #els

    newBoxIdx[col] = { rect = rectIdx, texts = textIdxs, label = labelIdx }

    if current and pinned then
      if col > 1 then
        els[#els + 1] = {
          type = "text",
          frame = { x = b.x + 1, y = PAD + 2, w = 14, h = 16 },
          text = "◀", textSize = 11, textColor = ACCENT, textAlignment = "center",
          id = "left:" .. col, trackMouseUp = true,
        }
      end
      if col < s.total then
        els[#els + 1] = {
          type = "text",
          frame = { x = b.x + b.w - 15, y = PAD + 2, w = 14, h = 16 },
          text = "▶", textSize = 11, textColor = ACCENT, textAlignment = "center",
          id = "right:" .. col, trackMouseUp = true,
        }
      end
    end
  end

  -- The screen, drawn over the strip: this is the "how it will look" frame.
  -- Only meaningful when the strip is wider than the screen.
  if viewport and viewport.w < STRIP_W - 2 then
    els[#els + 1] = {
      type = "rectangle",
      action = "stroke",
      frame = { x = viewport.x, y = PAD - 5, w = viewport.w, h = BOX_H + 10 },
      strokeColor = { red = 1, green = 1, blue = 1, alpha = 0.85 },
      strokeWidth = 2,
      roundedRectRadii = { xRadius = 5, yRadius = 5 },
      id = "vp:frame",
      trackMouseDown = pinned,
      trackMouseUp = pinned,
      trackMouseMove = pinned,
    }
    newKnobIdx.vpFrame = { idx = #els, w = viewport.w }
    els[#els + 1] = {
      type = "text",
      frame = { x = viewport.x, y = PAD - 20, w = math.max(60, viewport.w), h = 14 },
      text = pinned and "screen — drag me" or "screen",
      textSize = 9,
      textColor = { white = 0.8, alpha = 1 },
      textAlignment = "center",
    }
  end

  if pinned then
    els[#els + 1] = {
      type = "text",
      frame = { x = total_w - 74, y = 4, w = 40, h = 13 },
      text = "EDIT",
      textSize = 8.5,
      textColor = ACCENT,
      textAlignment = "right",
    }
    -- leaving edit mode should not require the menubar
    els[#els + 1] = {
      type = "rectangle", action = "strokeAndFill",
      frame = { x = total_w - 28, y = 2, w = 18, h = 18 },
      fillColor = { white = 0.16, alpha = 0.95 },
      strokeColor = EDGE_OFF, strokeWidth = 1,
      roundedRectRadii = { xRadius = 5, yRadius = 5 },
      id = "close", trackMouseUp = true,
    }
    els[#els + 1] = {
      type = "text",
      frame = { x = total_w - 28, y = 3, w = 18, h = 16 },
      text = "✕", textSize = 10,
      textColor = { white = 0.8, alpha = 1 }, textAlignment = "center",
    }
  end

  -- floating windows: amber, off to the side, one click away from returning
  for _, b in ipairs(floats) do
    els[#els + 1] = {
      type = "rectangle",
      action = "strokeAndFill",
      frame = { x = b.x, y = PAD, w = b.w, h = BOX_H },
      fillColor = FILL_FLT,
      strokeColor = WARN,
      strokeWidth = 1,
      roundedRectRadii = { xRadius = 7, yRadius = 7 },
      id = "unfloat:" .. b.win:id(),
      trackMouseUp = pinned,
    }
    els[#els + 1] = {
      type = "text",
      frame = { x = b.x + 3, y = PAD + 4, w = b.w - 6, h = 15 },
      text = model.shortName(b.win),
      textSize = 10.5, textColor = { white = 0.95, alpha = 1 }, textAlignment = "center",
    }
    els[#els + 1] = {
      type = "text",
      frame = { x = b.x, y = PAD + BOX_H - 15, w = b.w, h = 14 },
      text = pinned and "⊘ return" or "⊘ floating",
      textSize = 9, textColor = WARN, textAlignment = "center",
    }
  end

  local slider, scrollSlider -- {x, w, col}/{x, w, maxOffset} hit geometry, published below
  if has_chips then
    local cx = (total_w - geom.chipsWidth(chips, DIMS)) / 2
    local cy = PAD + BOX_H + 6
    local cur_ratio = s.col and s.columns[s.col] and s.columns[s.col].ratio or 0
    local fwin = s.col and s.columns[s.col] and s.columns[s.col].wins[1]
    local fmin = fwin and model.floorRatio(fwin) or model.minRatio()

    for _, c in ipairs(chips) do
      if c.gap then
        cx = cx + 12 + CHIP_G
      else
        local active = c.ratio and math.abs(cur_ratio - c.ratio) < 0.03
        -- a width the app will refuse is shown struck-through and does nothing
        local blocked = c.ratio and c.ratio < fmin - 0.005
        els[#els + 1] = {
          type = "rectangle",
          action = "strokeAndFill",
          frame = { x = cx, y = cy, w = c.w, h = CHIP_H },
          fillColor = active and FILL_ON or { white = 0.14, alpha = blocked and 0.5 or 0.95 },
          strokeColor = active and ACCENT or EDGE_OFF,
          strokeWidth = 1,
          roundedRectRadii = { xRadius = 6, yRadius = 6 },
          id = (not blocked) and c.id or nil,
          trackMouseUp = not blocked,
        }
        els[#els + 1] = {
          type = "text",
          frame = { x = cx, y = cy + 4, w = c.w, h = CHIP_H - 4 },
          text = c.text,
          textSize = 11,
          textColor = blocked and { white = 0.32, alpha = 1 }
              or (active and { white = 1, alpha = 1 } or { white = 0.75, alpha = 1 }),
          textAlignment = "center",
        }
        if blocked then
          els[#els + 1] = {
            type = "rectangle", action = "fill",
            frame = { x = cx + 6, y = cy + CHIP_H / 2 - 1, w = c.w - 12, h = 1.5 },
            fillColor = { white = 0.45, alpha = 1 },
          }
        end
        cx = cx + c.w + CHIP_G
      end
    end

    -- Two tracks: how wide the focused window is, and where the screen sits
    -- along the strip. The second is the slider form of dragging the frame.
    local sw = math.min(SLIDER_MAXW, total_w - PAD * 2 - 44)
    local sx = (total_w - sw) / 2 + 20
    local baseY = PAD + BOX_H + 6 + CHIP_H + 4

    local maxOffset = geom.maxOffset(s.stripW, s.canvas.w)
    local curV = maxOffset > 0 and ((s.canvas.x - s.left) / maxOffset) or 0

    slider = { x = sx, w = sw, col = s.col }
    scrollSlider = { x = sx, w = sw, maxOffset = maxOffset }

    -- cur_ratio (focused width) and fmin (learned floor) computed once above
    local tracks = {
      { label = fmin > model.minRatio() + 0.005
          and string.format("width\nmin %d%%", math.floor(fmin * 100 + 0.5)) or "width",
        frac = cur_ratio, id = "slide:track", floor = fmin,
        value = string.format("%d%%", math.floor(cur_ratio * 100 + 0.5)), live = true },
      { label = "view", frac = curV, id = "scroll:track",
        value = maxOffset > 0 and string.format("%d%%", math.floor(curV * 100 + 0.5)) or "all",
        live = maxOffset > 0 },
    }

    for i, t in ipairs(tracks) do
      local y = baseY + (i - 1) * (SLIDER_H + 4)
      local frac = math.max(0, math.min(1, t.frac))
      local dim = t.live and 1 or 0.4

      els[#els + 1] = {
        type = "text",
        frame = { x = sx - 46, y = y - 2, w = 42, h = SLIDER_H + 6 },
        text = t.label, textSize = 9,
        textColor = { white = 0.55 * dim + 0.1, alpha = 1 }, textAlignment = "right",
      }
      els[#els + 1] = {
        type = "rectangle", action = "fill",
        frame = { x = sx, y = y + SLIDER_H / 2 - 3, w = sw, h = 6 },
        fillColor = { white = 0.22, alpha = 1 },
        roundedRectRadii = { xRadius = 3, yRadius = 3 },
      }
      -- the part of the track the app will not honour, marked as unreachable
      if t.floor and t.floor > model.minRatio() + 0.005 then
        els[#els + 1] = {
          type = "rectangle", action = "fill",
          frame = { x = sx, y = y + SLIDER_H / 2 - 3, w = sw * math.min(1, t.floor), h = 6 },
          fillColor = { red = 0.45, green = 0.18, blue = 0.18, alpha = 0.9 },
          roundedRectRadii = { xRadius = 3, yRadius = 3 },
        }
      end
      els[#els + 1] = {
        type = "rectangle", action = "fill",
        frame = { x = sx, y = y + SLIDER_H / 2 - 3, w = sw * frac, h = 6 },
        fillColor = { red = ACCENT.red, green = ACCENT.green, blue = ACCENT.blue, alpha = dim },
        roundedRectRadii = { xRadius = 3, yRadius = 3 },
      }
      local fillIdx = #els
      els[#els + 1] = {
        type = "circle", action = "strokeAndFill",
        center = { x = sx + sw * frac, y = y + SLIDER_H / 2 }, radius = 7,
        fillColor = { white = 0.98, alpha = dim },
        strokeColor = { red = ACCENT.red, green = ACCENT.green, blue = ACCENT.blue, alpha = dim },
        strokeWidth = 2,
      }
      if t.id == "slide:track" then
        newKnobIdx.width = { fillIdx = fillIdx, knobIdx = #els, sx = sx, sw = sw, y = y }
      end
      els[#els + 1] = {
        type = "text",
        frame = { x = sx + sw + 4, y = y + 4, w = 40, h = SLIDER_H },
        text = t.value, textSize = 9.5,
        textColor = { white = 0.55, alpha = 1 }, textAlignment = "left",
      }
      if t.live then
        els[#els + 1] = {
          type = "rectangle", action = "fill",
          frame = { x = sx, y = y, w = sw, h = SLIDER_H },
          fillColor = { white = 1, alpha = 0.005 },
          id = t.id,
          trackMouseDown = true, trackMouseUp = true, trackMouseMove = true,
        }
      end

      -- step buttons, view row only: jump to the neighbouring column
      if t.id == "scroll:track" then
        for _, btn in ipairs({
          { text = "◀", id = "vstep:-1", x = sx - 68 },
          { text = "▶", id = "vstep:1",  x = sx + sw + 48 },
        }) do
          els[#els + 1] = {
            type = "rectangle", action = "strokeAndFill",
            frame = { x = btn.x, y = y, w = 20, h = SLIDER_H },
            fillColor = { white = 0.14, alpha = 0.95 },
            strokeColor = EDGE_OFF, strokeWidth = 1,
            roundedRectRadii = { xRadius = 5, yRadius = 5 },
            id = btn.id, trackMouseUp = true,
          }
          els[#els + 1] = {
            type = "text",
            frame = { x = btn.x, y = y + 4, w = 20, h = SLIDER_H },
            text = btn.text, textSize = 10,
            textColor = { white = t.live and 0.85 or 0.35, alpha = 1 },
            textAlignment = "center",
          }
        end
      end
    end
  end

  -- Persistent canvas: never delete()+new() on a plain redraw — that is what
  -- caused the flicker and killed mouse tracking mid-interaction. Reposition
  -- only when the target frame actually moved; otherwise just swap contents.
  local frameChanged = not canvas
      or frame.x ~= cf.x or frame.y ~= cf.y or frame.w ~= cf.w or frame.h ~= cf.h
  if frameChanged then
    if canvas then
      canvas:frame(cf)
    else
      canvas = hs.canvas.new(cf)
      canvas:level(hs.canvas.windowLevels.overlay)
      canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces |
        hs.canvas.windowBehaviors.stationary)
      -- clicking must not bring Hammerspoon forward; that is what breaks focus
      canvas:clickActivating(false)
    end
    frame = cf
  end
  canvas:replaceElements(els)
  canvas:show()

  M.boxIdx = newBoxIdx
  M.knobIdx = newKnobIdx
  M.lastTier = { hash = newHash, col = s.col }
  M.lastPinned = pinned
  M.lastGeom = {
    boxes = boxes,
    floats = floats,
    viewport = viewport,
    canvasFrame = cf,
    slider = slider,
    scrollSlider = scrollSlider,
    canvas = canvas,
  }
  return M.lastGeom
end

return M
