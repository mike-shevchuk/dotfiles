-- PaperWM widget: menubar counter + interactive map of the window strip
-- Answers what tiling never shows you: where am I in the row, how wide is
-- each window, and what fell out of the row entirely. Pinned, it is also a
-- control panel: click a box to focus, ◀ ▶ to reorder, chips to resize,
-- stack/unstack to build columns, and ⊘ boxes to pull floating windows back.
local M = {}

local paperwm = require("modules.paperwm")
local focusborder = require("modules.focusborder")
local paperwmfit = require("modules.paperwmfit")
local geom = require("modules.paperwmgeom")

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
M.lastCol = nil
M.dragging = false
M.slider = nil        -- {x, w, col} hit geometry for the width slider
M.scrollSlider = nil  -- {x, w, maxOffset} hit geometry for the view slider
M.lastDrag = 0
M.boxes = nil        -- drawn column geometry, for hit-testing during a drag
M.canvasFrame = nil  -- absolute frame of the map, to place the drop caret
M.caret = nil        -- separate canvas: the main one cannot be rebuilt mid-drag
M.drag = nil         -- {col, x0, moved}
M.dragGuard = nil
M.vpDrag = nil       -- {x0, offset0} while the screen frame is being dragged
M.viewport = nil     -- {x, w, offset, scale} of the visible-area frame
M.scrollAnchor = nil -- window we last anchored a scroll on, to avoid refocusing

-- ── reading PaperWM state ───────────────────────────────────────
local function shortName(win)
  if not win then return "?" end
  local app = win:application()
  local name = app and app:name() or (win:title() or "?")
  return #name > 10 and name:sub(1, 10) or name
end

-- Reading the strip means an Accessibility round-trip per window, and the drag
-- handlers used to call it several times per mouse event — that is where the
-- jerkiness came from. Cache it briefly; every mutation clears the cache.
local stripCache, stripCacheAt = nil, 0
local STRIP_TTL = 0.25

local function invalidate() stripCacheAt = 0 end

-- { columns = { { wins, ratio } … }, floating = { win … }, col, total, space }
local function computeStrip()
  local pwm = paperwm.pwm
  if not pwm then return nil end

  local focused = hs.window.focusedWindow()
  local index = focused and pwm.state.windowIndex(focused) or nil
  local space = index and index.space or hs.spaces.focusedSpace()

  local list = pwm.state.windowList(space)

  -- width is measured against PaperWM's canvas, not the raw screen
  local screen = focused and focused:screen() or hs.screen.mainScreen()
  local canvas = pwm.windows.getCanvas(screen)

  -- PaperWM keeps a virtual x for every window, which is where the column
  -- really sits on the strip even when macOS has parked it in the edge margin.
  -- That is what lets the map show what is off-screen.
  local xpos = pwm.state.xPositions(space)
  local columns = {}
  local left, right
  if list then
    for col = 1, #list do
      local wins = {}
      for row = 1, #list[col] do wins[#wins + 1] = list[col][row] end
      local first = wins[1]
      local w = first and first:frame().w or 0
      local vx = first and (xpos[first:id()] or first:frame().x) or 0
      columns[#columns + 1] = {
        wins = wins,
        ratio = canvas.w > 0 and (w / canvas.w) or 0,
        vx = vx,
        px = w,
      }
      left = left and math.min(left, vx) or vx
      right = right and math.max(right, vx + w) or (vx + w)
    end
  end

  -- floating windows vanish from the strip, which is exactly why they are
  -- hard to get back — surface them next to it
  local floating = {}
  for id, _ in pairs(pwm.state.is_floating) do
    local w = hs.window.get(id)
    if w and w:isVisible() and (hs.spaces.windowSpaces(w) or {})[1] == space then
      floating[#floating + 1] = w
    end
  end
  table.sort(floating, function(a, b) return shortName(a) < shortName(b) end)

  if #columns == 0 and #floating == 0 then return nil end

  -- macOS intermittently reports no focused window (notably right after a
  -- click on an overlay). Fall back to the last column we knew about, so the
  -- map keeps its chips and chevrons instead of going blank.
  local col = index and index.col or nil
  if col then
    M.lastCol = col
  elseif M.lastCol and M.lastCol <= #columns then
    col = M.lastCol
  end

  -- the strip always covers at least the screen, so the viewport frame has
  -- something to sit inside even when a single window is up
  left = math.min(left or canvas.x, canvas.x)
  right = math.max(right or canvas.x2, canvas.x + canvas.w)

  return {
    columns = columns,
    floating = floating,
    col = col,
    total = #columns,
    space = space,
    canvas = canvas,
    left = left,
    stripW = right - left,
  }
end

local function strip()
  local now = hs.timer.secondsSinceEpoch()
  if stripCache and (now - stripCacheAt) < STRIP_TTL then return stripCache end
  stripCache, stripCacheAt = computeStrip(), now
  return stripCache
end

-- ── mutations ───────────────────────────────────────────────────
-- Every mutation used to spawn its own redraw timer, so a slider drag queued a
-- pile of them and the map redrew far more often than it had to. Coalesce.
local refreshTimer

local function afterChange()
  invalidate()
  if refreshTimer then refreshTimer:stop() end
  refreshTimer = hs.timer.doAfter(0.25, function()
    M.update()
    if M.pinned then M.draw() end
  end)
end

-- exact ratio, mirroring how PaperWM's own cycleWindowSize computes it
local function setWidth(win, ratio)
  local pwm = paperwm.pwm
  if not (pwm and win) then return end
  local canvas = pwm.windows.getCanvas(win:screen())
  local gap = (pwm.windows.getGap("left") + pwm.windows.getGap("right")) / 2
  local frame = win:frame()
  local new_w = ratio * (canvas.w + gap) - gap
  frame.x = frame.x + ((frame.w - new_w) // 2)
  frame.w = new_w
  pwm.windows.moveWindow(win, frame)
  local space = (hs.spaces.windowSpaces(win) or {})[1]
  if space then pwm:tileSpace(space) end
  paperwmfit.setDesired(win, ratio)
  paperwmfit.refit()
  afterChange()
end

-- PaperWM's own full_width action reads hs.window.focusedWindow(), which is
-- intermittently nil right after a click on an overlay — keep our own memory
-- of the previous width instead so the widget never depends on focus
local prevRatio = {}

local function fullWidth(win)
  local pwm = paperwm.pwm
  if not (pwm and win) then return end
  local canvas = pwm.windows.getCanvas(win:screen())
  local cur = win:frame().w / canvas.w
  if cur > 0.97 and prevRatio[win:id()] then
    setWidth(win, prevRatio[win:id()])
    prevRatio[win:id()] = nil
  else
    prevRatio[win:id()] = cur
    setWidth(win, 1.0)
  end
end

-- Some apps refuse to shrink past a hard minimum (Chromium stops at ~500px).
-- On a narrow display that can be 40%+ of the screen, so a width you pick below
-- it simply cannot happen — the UI has to say so instead of ignoring you.
local function floorRatio(win)
  local pwm = paperwm.pwm
  if not (pwm and win) then return paperwmfit.MIN end
  local canvas = pwm.windows.getCanvas(win:screen())
  local px = paperwmfit.floor[win:id()]
  if not (px and canvas.w > 0) then return paperwmfit.MIN end
  return math.max(paperwmfit.MIN, px / canvas.w)
end

-- Slider: any percentage, not just the preset chips. x is canvas-relative.
function M.applySlider(x)
  local sl = M.slider
  if not sl then return end
  local cur = strip()
  local e = cur and sl.col and cur.columns[sl.col]
  local win = e and e.wins[1]
  if not win then return end
  local ratio = math.max(floorRatio(win), math.min(1.0, (x - sl.x) / sl.w))
  setWidth(win, ratio)
end

-- View slider: maps the track onto the scrollable range of the strip.
function M.applyScroll(x)
  local sl = M.scrollSlider
  if not (sl and sl.maxOffset and sl.maxOffset > 0) then return end
  local frac = math.max(0, math.min(1, (x - sl.x) / sl.w))
  M.scrollTo(frac * sl.maxOffset)
end

-- Nudge the view for the ◀ ▶ buttons. Stepping to the next column boundary
-- was too coarse — columns are often half the screen wide — so move by a fixed
-- slice of the screen instead and let the view land wherever it lands.
M.STEP = 0.15  -- share of the screen width per press

function M.scrollStep(dir)
  local cur = strip()
  if not cur then return end
  local offset = cur.canvas.x - cur.left
  -- via the module table: the local scrollTo is defined further down
  M.scrollTo(offset + dir * cur.canvas.w * M.STEP)
end

-- Scroll the row so the screen shows the slice starting at `offset` px from
-- the strip's left edge. tileSpace takes an explicit anchor, so we pick a
-- column that will actually be on screen and pin it at the right spot.
local function scrollTo(s, offset)
  local pwm = paperwm.pwm
  if not (pwm and s) then return end
  offset = math.max(0, math.min(offset, math.max(0, s.stripW - s.canvas.w)))

  -- Anchor on whichever column lands nearest the middle of the viewport.
  -- Anchoring on the left-most one made PaperWM's on-screen clamp fight the
  -- target position, so far scrolls kept falling short.
  local centre = offset + s.canvas.w / 2
  local anchorCol, best
  for col, e in ipairs(s.columns) do
    local mid = (e.vx - s.left) + e.px / 2
    local d = math.abs(mid - centre)
    if not best or d < best then anchorCol, best = col, d end
  end
  anchorCol = anchorCol or 1
  local e = s.columns[anchorCol]
  local win = e and e.wins[1]
  if not win then return end

  local f = win:frame()
  f.x = s.canvas.x + (e.vx - s.left) - offset
  pwm.windows.moveWindow(win, f)
  pwm:tileSpace(s.space, win)

  -- PaperWM re-tiles from the focused window on every move, so a view scrolled
  -- away from it snaps straight back. Moving focus to the column we scrolled to
  -- is what makes the new position stick — and it is where you were heading.
  -- Only when the anchor actually changes though: focusing on every drag step
  -- fired the whole event cascade (fit, border, widget) dozens of times a drag.
  local id = win:id()
  if id ~= M.scrollAnchor then
    M.scrollAnchor = id
    if win ~= hs.window.focusedWindow() then win:focus() end
  end

  -- positions just moved; the next read must not come from the cache
  invalidate()
end

-- Public wrapper: scroll the row to an absolute offset. Also lets the
-- behaviour be verified without synthesising mouse drags.
function M.scrollTo(offset)
  local cur = strip()
  if cur then scrollTo(cur, offset) end
  return cur and cur.canvas.x - cur.left or nil
end

-- Move a column to a given position. swapWindows() would be the obvious call
-- but it acts on the focused window, and focus is exactly what a click on an
-- overlay disturbs — this list surgery works no matter what holds focus.
local function moveColumnTo(space, from, to)
  local pwm = paperwm.pwm
  if not pwm or from == to then return end
  local list = pwm.state.windowList(space)
  if not (list and list[from] and list[to]) then return end
  local column = table.remove(list, from)
  table.insert(list, to, column)
  pwm:tileSpace(space)
  afterChange()
end

-- The drop marker lives on its own canvas so it can follow the pointer without
-- rebuilding the map, which would kill the mouse tracking mid-drag.
local function caretShow(col, toRight)
  if not (M.boxes and M.canvasFrame) then return end
  local b
  for _, box in ipairs(M.boxes) do if box.col == col then b = box end end
  if not b then return end

  if not M.caret then
    M.caret = hs.canvas.new({ x = 0, y = 0, w = 3, h = 10 })
    M.caret:level(hs.canvas.windowLevels.overlay)
    M.caret:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces |
      hs.canvas.windowBehaviors.stationary)
    M.caret:clickActivating(false)
    M.caret:canvasMouseEvents(false, false, false, false)
    M.caret:appendElements({ type = "rectangle", action = "fill", fillColor = ACCENT,
      roundedRectRadii = { xRadius = 2, yRadius = 2 } })
  end

  M.caret:frame({
    x = M.canvasFrame.x + (toRight and (b.x + b.w + 1) or (b.x - 4)),
    y = M.canvasFrame.y + PAD - 3,
    w = 3,
    h = BOX_H + 6,
  })
  M.caret:show()
end

local function caretHide()
  if M.caret then M.caret:hide() end
end

-- Resolve a drop: which column is under x, and move `from` there.
-- Public so the behaviour can be verified without synthesising mouse events.
function M.dropAt(from, x)
  local cur = strip()
  local to = geom.columnAt(x, M.boxes)
  if cur and to then moveColumnTo(cur.space, from, to) end
  return to
end

-- slurp/barf rely on a file-local helper inside the spoon, so they cannot be
-- reimplemented here — focus the window first and let PaperWM do the work
local function withFocus(win, fn)
  if not win then return end
  win:focus()
  hs.timer.doAfter(0.2, function()
    if hs.window.focusedWindow() then
      fn()
      afterChange()
    else
      hs.timer.doAfter(0.3, function() fn(); afterChange() end)
    end
  end)
end

-- toggleFloating() takes an explicit window, so moving one in or out of the
-- floating layer never depends on focus
local function toggleFloat(win)
  local pwm = paperwm.pwm
  if not (pwm and win) then return end
  pwm.floating.toggleFloating(win)
  afterChange()
end

-- Full width, and back to the previous width.
--
-- Deliberately not PaperWM's own full_width action: that one changes the frame
-- and leaves fit to find out about it later, which is a race — when the read
-- came back late or focus read nil, fit restored the old width and the key
-- looked dead. Setting the intent directly has no race at all.
M.beforeFull = {}

function M.toggleFullWidth()
  local pwm = paperwm.pwm
  if not pwm then return end

  local win = hs.window.focusedWindow()
  if not win then
    local cur = strip()
    local e = cur and cur.col and cur.columns[cur.col]
    win = e and e.wins[1]
  end
  if not win then return end

  -- Decide from the remembered intent, not from the measured frame. The frame
  -- is whatever compression happens to have left behind, so reading it made the
  -- toggle pick the wrong branch and set full width twice in a row.
  local id = win:id()
  local canvas = pwm.windows.getCanvas(win:screen())
  local intent = paperwmfit.desired[id] or (canvas.w > 0 and win:frame().w / canvas.w) or 0.5

  if intent >= 0.97 then
    local back = M.beforeFull[id] or 0.5
    M.beforeFull[id] = nil
    setWidth(win, back)
    hs.alert.show(string.format("⇔ back to %d%%", math.floor(back * 100 + 0.5)), 0.7)
  else
    M.beforeFull[id] = intent
    setWidth(win, 1.0)
    hs.alert.show("⇔ full width", 0.7)
  end
end

-- Full screen, and back again.
--
-- A tiled window cannot simply be resized to the whole screen: PaperWM re-lays
-- the row on the very next event and puts it back. So zooming lifts the window
-- out of the tiling layer first, then fills the screen; unzooming drops it back
-- into the row at the width it had before.
M.zoomed = {}

function M.toggleFullscreen()
  local pwm = paperwm.pwm
  local win = hs.window.focusedWindow()
  if not (pwm and win) then return end
  local id = win:id()
  local prev = M.zoomed[id]

  if prev then
    M.zoomed[id] = nil
    if pwm.floating.isFloating(win) then pwm.floating.toggleFloating(win) end
    if prev.ratio then paperwmfit.setDesired(win, prev.ratio) end
    paperwmfit.refit()
    afterChange()
    hs.alert.show("⤢ back to the row", 0.8)
    return
  end

  local canvas = pwm.windows.getCanvas(win:screen())
  M.zoomed[id] = { ratio = canvas.w > 0 and (win:frame().w / canvas.w) or nil }

  if not pwm.floating.isFloating(win) then pwm.floating.toggleFloating(win) end
  -- toggleFloating retiles the space, so fill the screen once that has settled
  hs.timer.doAfter(hs.window.animationDuration + 0.08, function()
    if not M.zoomed[id] then return end
    win:setFrame(win:screen():frame())
    win:raise()
    afterChange()
  end)
  hs.alert.show("⤢ full screen", 0.8)
end

-- ── menubar ─────────────────────────────────────────────────────
local function columnMenu(entry, col, space)
  local pwm = paperwm.pwm
  local win = entry.wins[1]
  local items = {
    { title = "Focus", fn = function() win:focus() end },
    { title = "-" },
    { title = "Move left",  fn = function() moveColumnTo(space, col, col - 1) end },
    { title = "Move right", fn = function() moveColumnTo(space, col, col + 1) end },
    { title = "-" },
    { title = "Stack into column on the left",
      fn = function() withFocus(win, pwm.windows.slurpWindow) end },
    { title = "Unstack into its own column",
      fn = function() withFocus(win, pwm.windows.barfWindow) end },
    { title = "-" },
  }
  for _, r in ipairs(pwm.window_ratios) do
    items[#items + 1] = {
      title = string.format("Width %d%%", math.floor(r * 100 + 0.5)),
      fn = function() setWidth(win, r) end,
    }
  end
  items[#items + 1] = { title = "Full width", fn = function() fullWidth(win) end }
  items[#items + 1] = {
    title = M.zoomed[win:id()] and "Leave full screen" or "Full screen",
    fn = function() win:focus(); hs.timer.doAfter(0.15, M.toggleFullscreen) end,
  }
  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = "Make floating", fn = function() toggleFloat(win) end }
  return items
end

local function menuTable()
  local items = {}
  local s = strip()

  if s then
    for col, entry in ipairs(s.columns) do
      local titles = {}
      for _, w in ipairs(entry.wins) do titles[#titles + 1] = shortName(w) end
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
          title = "  ⊘ " .. shortName(w) .. " — return to tiling",
          fn = function() toggleFloat(w) end,
        }
      end
      if #s.floating > 1 then
        items[#items + 1] = {
          title = "  ⊘ Return all to tiling",
          fn = function()
            -- space them out: each toggle retiles, and PaperWM needs the
            -- previous retile to land before the next add
            for i, w in ipairs(s.floating) do
              hs.timer.doAfter((i - 1) * 0.4, function() toggleFloat(w) end)
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
    title = paperwmfit.enabled and "Fit mode is ON — windows squeeze"
        or "Fit mode is OFF — windows scroll off-screen",
    fn = function() paperwmfit.toggle(); M.update() end,
  }
  items[#items + 1] = {
    title = focusborder.enabled and "Focus border is ON — turn off"
        or "Focus border is OFF — turn on",
    fn = function() focusborder.toggle(); M.update() end,
  }
  items[#items + 1] = {
    title = "Forget learned min widths",
    fn = function() paperwmfit.clearFloors(); M.update() end,
  }
  items[#items + 1] = {
    title = "Refresh layout",
    fn = function()
      if paperwm.pwm then paperwm.pwm.windows.refreshWindows() end
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
    for _, r in ipairs(paperwm.pwm.window_ratios) do
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
  if M.dragging then return end
  local s = strip()
  if not s then
    if M.canvas then M.canvas:hide() end
    return
  end

  local boxes, floats, total_w, viewport = geom.layout(s, geom.DIMS)
  M.viewport = viewport
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
  M.canvasFrame = {
    x = f.x + (f.w - total_w) / 2,
    y = f.y2 - height - 64,
    w = total_w,
    h = height,
  }
  M.boxes = boxes
  M.canvas = hs.canvas.new(M.canvasFrame)
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
        text = shortName(e.wins[row]),
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
      text = shortName(b.win),
      textSize = 10.5, textColor = { white = 0.95, alpha = 1 }, textAlignment = "center",
    }
    els[#els + 1] = {
      type = "text",
      frame = { x = b.x, y = PAD + BOX_H - 15, w = b.w, h = 14 },
      text = M.pinned and "⊘ return" or "⊘ floating",
      textSize = 9, textColor = WARN, textAlignment = "center",
    }
  end

  if has_chips then
    local cx = (total_w - geom.chipsWidth(chips, geom.DIMS)) / 2
    local cy = PAD + BOX_H + 6
    local cur_ratio = s.col and s.columns[s.col] and s.columns[s.col].ratio or 0
    local fwin = s.col and s.columns[s.col] and s.columns[s.col].wins[1]
    local fmin = fwin and floorRatio(fwin) or paperwmfit.MIN

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

    M.slider = { x = sx, w = sw, col = s.col }
    M.scrollSlider = { x = sx, w = sw, maxOffset = maxOffset }

    local wmin = fwin and floorRatio(fwin) or paperwmfit.MIN
    local tracks = {
      { label = wmin > paperwmfit.MIN + 0.005
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
      if t.floor and t.floor > paperwmfit.MIN + 0.005 then
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

  M.canvas:mouseCallback(function(_, message, id, x, y)
    if not id then return end

    if tostring(id) == "close" then
      if message == "mouseUp" and M.pinned then M.togglePin() end
      return
    end

    if tostring(id) == "vstep:-1" or tostring(id) == "vstep:1" then
      if message == "mouseUp" then
        M.scrollStep(tostring(id) == "vstep:1" and 1 or -1)
        hs.timer.doAfter(0.4, function() M.update() end)
      end
      return
    end

    if tostring(id) == "scroll:track" then
      if message == "mouseDown" then
        M.dragging = true
        M.applyScroll(x)
      elseif message == "mouseMove" then
        if M.dragging then
          local now = hs.timer.secondsSinceEpoch()
          if now - M.lastDrag > 0.08 then
            M.lastDrag = now
            M.applyScroll(x)
          end
        end
      elseif message == "mouseUp" then
        M.dragging = false
        M.applyScroll(x)
        hs.timer.doAfter(0.4, function() M.update() end)
      end
      return
    end

    -- the slider is the only control that tracks press and drag
    if tostring(id) == "slide:track" then
      if message == "mouseDown" then
        M.dragging = true
        M.applySlider(x)
      elseif message == "mouseMove" then
        if M.dragging then
          local now = hs.timer.secondsSinceEpoch()
          if now - M.lastDrag > 0.12 then
            M.lastDrag = now
            M.applySlider(x)
          end
        end
      elseif message == "mouseUp" then
        M.dragging = false
        M.applySlider(x)
        hs.timer.doAfter(0.4, function() M.update() end)
      end
      return
    end

    -- dragging the screen frame scrolls the row
    if tostring(id) == "vp:frame" then
      if message == "mouseDown" then
        M.dragging = true
        M.vpDrag = { x0 = x, offset0 = M.viewport and M.viewport.offset or 0 }
        if M.dragGuard then M.dragGuard:stop() end
        M.dragGuard = hs.timer.doAfter(6, function()
          M.vpDrag, M.dragging = nil, false
          M.update()
        end)
      elseif message == "mouseMove" then
        if M.vpDrag and M.viewport then
          local now = hs.timer.secondsSinceEpoch()
          if now - M.lastDrag > 0.06 then
            M.lastDrag = now
            local cur2 = strip()
            if cur2 then
              scrollTo(cur2, M.vpDrag.offset0 + (x - M.vpDrag.x0) / M.viewport.scale)
            end
          end
        end
      elseif message == "mouseUp" then
        local d = M.vpDrag
        M.vpDrag, M.dragging = nil, false
        if M.dragGuard then M.dragGuard:stop(); M.dragGuard = nil end
        local cur2 = strip()
        if d and cur2 and M.viewport then
          scrollTo(cur2, d.offset0 + (x - d.x0) / M.viewport.scale)
        end
        hs.timer.doAfter(0.4, function() M.update() end)
      end
      return
    end

    -- dragging a column box to reorder it
    local dk, dcol = tostring(id):match("^(focus):(%d+)$")
    if dk then
      dcol = tonumber(dcol)
      if message == "mouseDown" then
        M.dragging = true
        M.drag = { col = dcol, x0 = x, y0 = y, moved = false }
        -- if the release never arrives (mouse let go off-canvas) do not freeze
        if M.dragGuard then M.dragGuard:stop() end
        M.dragGuard = hs.timer.doAfter(6, function()
          M.drag, M.dragging = nil, false
          caretHide(); M.update()
        end)
        return
      elseif message == "mouseMove" then
        if M.drag then
          if math.abs(x - M.drag.x0) > 6 then M.drag.moved = true end
          if M.drag.moved then
            local t = geom.columnAt(x, M.boxes)
            if t then caretShow(t, t >= M.drag.col) end
          end
        end
        return
      elseif message == "mouseUp" then
        local d = M.drag
        M.drag, M.dragging = nil, false
        if M.dragGuard then M.dragGuard:stop(); M.dragGuard = nil end
        caretHide()
        if d and d.moved then
          local dy = y - (d.y0 or y)
          local dx = x - d.x0
          if math.abs(dy) > math.abs(dx) and math.abs(dy) > 18 then
            -- a mostly-vertical drag changes the column stack instead of order:
            -- up folds the window into the column on its left, down pulls it out
            local cur2 = strip()
            local e = cur2 and cur2.columns[d.col]
            local win = e and e.wins[1]
            if win then
              withFocus(win, dy < 0 and paperwm.pwm.windows.slurpWindow
                or paperwm.pwm.windows.barfWindow)
            end
          else
            M.dropAt(d.col, x)
          end
        else
          -- never moved: it was a plain click, so just focus that column
          local cur2 = strip()
          local e = cur2 and cur2.columns[dcol]
          if e and e.wins[1] then e.wins[1]:focus() end
        end
        M.update()
        return
      end
    end

    if message ~= "mouseUp" then return end
    local cur = strip()
    if not cur then return end

    local pwm = paperwm.pwm
    local kind, arg = tostring(id):match("^(%a+):(.+)$")

    -- focus:N is handled above by the drag branch
    if kind == "left" or kind == "right" then
      local c = tonumber(arg)
      moveColumnTo(cur.space, c, c + ((kind == "left") and -1 or 1))
    elseif kind == "unfloat" then
      local w = hs.window.get(tonumber(arg))
      if w then toggleFloat(w) end
    elseif kind == "w" then
      local e = cur.col and cur.columns[cur.col]
      if not (e and e.wins[1]) then return end
      if arg == "full" then fullWidth(e.wins[1]) else setWidth(e.wins[1], tonumber(arg)) end
    elseif kind == "act" then
      local e = cur.col and cur.columns[cur.col]
      local win = e and e.wins[1]
      if not win then return end
      if arg == "slurp" then
        withFocus(win, pwm.windows.slurpWindow)
      elseif arg == "barf" then
        withFocus(win, pwm.windows.barfWindow)
      elseif arg == "float" then
        toggleFloat(win)
      end
    end
  end)

  M.canvas:show()
end

-- ── refresh ─────────────────────────────────────────────────────
function M.update()
  local s = strip()

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
      local s = strip()
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
