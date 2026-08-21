-- PaperWM widget: menubar counter + interactive map of the window strip
-- Answers what tiling never shows you: where am I in the row, how wide is
-- each window, and what fell out of the row entirely. Pinned, it is also a
-- control panel: click a box to focus, ◀ ▶ to reorder, chips to resize,
-- stack/unstack to build columns, and ⊘ boxes to pull floating windows back.
local M = {}

local paperwm = require("modules.paperwm")
local focusborder = require("modules.focusborder")
local geom = require("modules.paperwmgeom")
local model = require("modules.paperwmmodel")
local interact = require("modules.paperwminteract")

-- frozen public API: re-export the mutations that moved into the model
M.toggleFullWidth  = model.toggleFullWidth
M.toggleFullscreen = model.toggleFullscreen

local CHEATSHEET = "file://" .. os.getenv("HOME") ..
    "/zettelkasten/claude_code/tools/paperwm-cheatsheet.html"

local STRIP_W = 560 -- drawing width shared by the tiled boxes
local BOX_H, GAP, PAD = 42, 6, 22
local MIN_BOX, FLOAT_W, SEP = 46, 74, 18
local CHIP_H, CHIP_G = 22, 5
local SLIDER_H, SLIDER_MAXW = 24, 420
local FLASH_SEC = 1.6

local ACCENT   = { red = 0.35, green = 0.65, blue = 1.00, alpha = 1 }
local WARN     = { red = 0.95, green = 0.68, blue = 0.20, alpha = 1 }
local FILL_ON  = { red = 0.13, green = 0.31, blue = 0.53, alpha = 0.95 }
local FILL_OFF = { red = 0.11, green = 0.13, blue = 0.16, alpha = 0.95 }
local FILL_FLT = { red = 0.22, green = 0.17, blue = 0.06, alpha = 0.95 }
local EDGE_OFF = { red = 0.25, green = 0.28, blue = 0.32, alpha = 1 }
local BG       = { red = 0.05, green = 0.06, blue = 0.08, alpha = 0.90 }

M.menubar = nil
M.canvas = nil
M.pinned = false
M.hideTimer = nil
M.filter = nil
M._geom = nil -- geometry published each draw; interact reads it via ctx getters

-- Every mutation used to spawn its own redraw timer, so a slider drag queued a
-- pile of them and the map redrew far more often than it had to. Coalesce.
local refreshTimer
model.onChange(function()
  model.invalidate()
  if refreshTimer then refreshTimer:stop() end
  refreshTimer = hs.timer.doAfter(0.25, function()
    M.update()
    if M.pinned then M.draw() end
  end)
end)

-- ── menubar ─────────────────────────────────────────────────────
local function columnMenu(entry, col, space)
  local win = entry.wins[1]
  local items = {
    { title = "Focus", fn = function() win:focus() end },
    { title = "-" },
    { title = "Move left",  fn = function() model.moveColumn(space, col, col - 1) end },
    { title = "Move right", fn = function() model.moveColumn(space, col, col + 1) end },
    { title = "-" },
    { title = "Stack into column on the left",
      fn = function() model.stack(win) end },
    { title = "Unstack into its own column",
      fn = function() model.unstack(win) end },
    { title = "-" },
  }
  for _, r in ipairs(model.widthRatios()) do
    items[#items + 1] = {
      title = string.format("Width %d%%", math.floor(r * 100 + 0.5)),
      fn = function() model.setWidth(win, r) end,
    }
  end
  items[#items + 1] = { title = "Full width", fn = function() model.fullWidth(win) end }
  items[#items + 1] = {
    title = model.zoomed[win:id()] and "Leave full screen" or "Full screen",
    fn = function() win:focus(); hs.timer.doAfter(0.15, M.toggleFullscreen) end,
  }
  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = "Make floating", fn = function() model.toggleFloat(win) end }
  return items
end

local function menuTable()
  local items = {}
  local s = model.strip()

  if s then
    for col, entry in ipairs(s.columns) do
      local titles = {}
      for _, w in ipairs(entry.wins) do titles[#titles + 1] = model.shortName(w) end
      items[#items + 1] = {
        title = string.format("%s %d. %s  ·  %d%%", (col == s.col) and "▸" or "  ",
          col, table.concat(titles, " / "), math.floor(entry.ratio * 100 + 0.5)),
        menu = columnMenu(entry, col, s.space),
      }
    end

    if #s.floating > 0 then
      items[#items + 1] = { title = "-" }
      items[#items + 1] = { title = "Floating (outside the strip)", disabled = true }
      for _, w in ipairs(s.floating) do
        items[#items + 1] = {
          title = "  ⊘ " .. model.shortName(w) .. " — return to tiling",
          fn = function() model.toggleFloat(w) end,
        }
      end
      if #s.floating > 1 then
        items[#items + 1] = {
          title = "  ⊘ Return all to tiling",
          fn = function()
            -- space them out: each toggle retiles, and PaperWM needs the
            -- previous retile to land before the next add
            for i, w in ipairs(s.floating) do
              hs.timer.doAfter((i - 1) * 0.4, function() model.toggleFloat(w) end)
            end
          end,
        }
      end
    end
    items[#items + 1] = { title = "-" }
  end

  items[#items + 1] = {
    title = paperwm.running and "Tiling is ON — turn off" or "Tiling is OFF — turn on",
    fn = function() paperwm.toggle(); M.update() end,
  }
  items[#items + 1] = {
    title = M.pinned and "Unpin strip map" or "Pin strip map (clickable)",
    fn = function() M.togglePin() end,
  }
  items[#items + 1] = {
    title = model.fitEnabled() and "Fit mode is ON — windows squeeze"
        or "Fit mode is OFF — windows scroll off-screen",
    fn = function() model.toggleFit(); M.update() end,
  }
  items[#items + 1] = {
    title = focusborder.enabled and "Focus border is ON — turn off"
        or "Focus border is OFF — turn on",
    fn = function() focusborder.toggle(); M.update() end,
  }
  items[#items + 1] = {
    title = "Forget learned min widths",
    fn = function() model.clearFloors(); M.update() end,
  }
  items[#items + 1] = {
    title = "Refresh layout",
    fn = function()
      model.refreshWindows()
      M.update()
    end,
  }
  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = "Open cheatsheet", fn = function() hs.urlevent.openURL(CHEATSHEET) end }
  return items
end

-- ── strip map canvas ────────────────────────────────────────────
local WIDTH_CHIP, ACT_CHIP = 44, 60

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

function M.draw()
  if interact.isDragging() then return end
  local s = model.strip()
  if not s then
    if M.canvas then M.canvas:hide() end
    return
  end

  local boxes, floats, total_w, viewport = geom.layout(s, geom.DIMS)
  local chips = M.pinned and chipRow(s) or {}
  local has_chips = #chips > 0
  if has_chips then
    total_w = math.max(total_w, geom.chipsWidth(chips, geom.DIMS) + PAD * 2, 440 + PAD * 2)
  end
  local height = PAD * 2 + BOX_H + (has_chips and (CHIP_H + 6 + (SLIDER_H + 4) * 2) or 0)

  local screen = (hs.window.focusedWindow() and hs.window.focusedWindow():screen())
      or hs.screen.mainScreen()
  local f = screen:frame()

  if M.canvas then M.canvas:delete() end
  local canvasFrame = {
    x = f.x + (f.w - total_w) / 2,
    y = f.y2 - height - 64,
    w = total_w,
    h = height,
  }
  M.canvas = hs.canvas.new(canvasFrame)
  M.canvas:level(hs.canvas.windowLevels.overlay)
  M.canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces |
    hs.canvas.windowBehaviors.stationary)
  -- clicking must not bring Hammerspoon forward; that is what breaks focus
  M.canvas:clickActivating(false)

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
      trackMouseDown = M.pinned,
      trackMouseUp = M.pinned,
      trackMouseMove = M.pinned,
    }

    local rows = #e.wins
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

    if current and M.pinned then
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
      trackMouseDown = M.pinned,
      trackMouseUp = M.pinned,
      trackMouseMove = M.pinned,
    }
    els[#els + 1] = {
      type = "text",
      frame = { x = viewport.x, y = PAD - 20, w = math.max(60, viewport.w), h = 14 },
      text = M.pinned and "screen — drag me" or "screen",
      textSize = 9,
      textColor = { white = 0.8, alpha = 1 },
      textAlignment = "center",
    }
  end

  if M.pinned then
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
      trackMouseUp = M.pinned,
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
      text = M.pinned and "⊘ return" or "⊘ floating",
      textSize = 9, textColor = WARN, textAlignment = "center",
    }
  end

  local slider, scrollSlider -- {x, w, col}/{x, w, maxOffset} hit geometry, published below
  if has_chips then
    local cx = (total_w - geom.chipsWidth(chips, geom.DIMS)) / 2
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

    local curW = s.col and s.columns[s.col] and s.columns[s.col].ratio or 0
    local maxOffset = math.max(0, s.stripW - s.canvas.w)
    local curV = maxOffset > 0 and ((s.canvas.x - s.left) / maxOffset) or 0

    slider = { x = sx, w = sw, col = s.col }
    scrollSlider = { x = sx, w = sw, maxOffset = maxOffset }

    local wmin = fwin and model.floorRatio(fwin) or model.minRatio()
    local tracks = {
      { label = wmin > model.minRatio() + 0.005
          and string.format("width\nmin %d%%", math.floor(wmin * 100 + 0.5)) or "width",
        frac = curW, id = "slide:track", floor = wmin,
        value = string.format("%d%%", math.floor(curW * 100 + 0.5)), live = true },
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
      els[#els + 1] = {
        type = "circle", action = "strokeAndFill",
        center = { x = sx + sw * frac, y = y + SLIDER_H / 2 }, radius = 7,
        fillColor = { white = 0.98, alpha = dim },
        strokeColor = { red = ACCENT.red, green = ACCENT.green, blue = ACCENT.blue, alpha = dim },
        strokeWidth = 2,
      }
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

  M.canvas:appendElements(els)

  -- publish this draw's geometry and (re)attach the interaction layer; it
  -- reads live geometry through these getters instead of owning it
  M._geom = { boxes = boxes, viewport = viewport, canvasFrame = canvasFrame,
              slider = slider, scrollSlider = scrollSlider }
  interact.attach(M.canvas, {
    boxes       = function() return M._geom.boxes end,
    viewport    = function() return M._geom.viewport end,
    sliders     = function() return M._geom.slider, M._geom.scrollSlider end,
    canvasFrame = function() return M._geom.canvasFrame end,
    pinned      = function() return M.pinned end,
    togglePin   = function() M.togglePin() end,
    afterUpdate = function() M.update() end,
  })

  M.canvas:show()
end

-- ── refresh ─────────────────────────────────────────────────────
function M.update()
  local s = model.strip()

  if M.menubar then
    local title
    if not paperwm.running then
      title = "⛔"
    elseif s and s.col then
      title = string.format("📄 %d/%d · %d%%", s.col, s.total,
        math.floor((s.columns[s.col] and s.columns[s.col].ratio or 0) * 100 + 0.5))
    elseif s then
      title = string.format("📄 –/%d", s.total)
    else
      title = "📄"
    end
    -- a floating window is invisible in the strip, so count it in the title
    if s and #s.floating > 0 then title = title .. " ⊘" .. #s.floating end
    M.menubar:setTitle(title)
    M.menubar:setMenu(menuTable)
  end

  if M.pinned or (M.canvas and M.canvas:isShowing()) then M.draw() end
end

-- show briefly, the way a volume HUD does
local function flash()
  if M.pinned then M.update(); return end
  M.draw()
  if M.hideTimer then M.hideTimer:stop() end
  M.hideTimer = hs.timer.doAfter(FLASH_SEC, function()
    if M.canvas and not M.pinned then M.canvas:hide() end
  end)
end

-- pinned = stays up and accepts clicks
function M.togglePin()
  M.pinned = not M.pinned
  if M.hideTimer then M.hideTimer:stop() end
  if M.pinned then M.draw() elseif M.canvas then M.canvas:hide() end
  M.update()
  hs.alert.show(M.pinned and "📄 strip map pinned — clickable" or "📄 strip map off", 1)
end

M.show = function() M.togglePin() end

function M.start()
  M.menubar = hs.menubar.new()

  local lastCol, lastTotal, lastFloat

  M.filter = paperwm.subscribe({
    hs.window.filter.windowFocused,
    hs.window.filter.windowCreated,
    hs.window.filter.windowDestroyed,
  }, function()
    -- watchers fire before PaperWM finishes retiling; let it settle
    hs.timer.doAfter(0.12, function()
      M.update()
      -- only surface the map when the position actually moved, otherwise it
      -- pops up on every stray click
      local s = model.strip()
      local col, total = s and s.col, s and s.total
      local nfloat = s and #s.floating or 0
      if paperwm.running and (col ~= lastCol or total ~= lastTotal or nfloat ~= lastFloat) then
        flash()
      end
      lastCol, lastTotal, lastFloat = col, total, nfloat
    end)
  end)

  M.update()
end

return M
