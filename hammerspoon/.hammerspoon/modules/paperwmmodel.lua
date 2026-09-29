-- PaperWM adapter: the only module that touches PaperWM/paperwmfit internals.
-- paperwmui reads/writes the strip exclusively through this API.
local M = {}

local paperwm = require("modules.paperwm")
local paperwmfit = require("modules.paperwmfit")
local geom = require("modules.paperwmgeom")

-- ── reading PaperWM state ───────────────────────────────────────
function M.shortName(win)
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

function M.invalidate() stripCacheAt = 0 end

-- A window whose app has quit abruptly can linger in PaperWM's list: its id no
-- longer resolves to a live window. It surfaces as a phantom "0%" column you
-- cannot focus, and touching its dead Accessibility element can stall — a real
-- source of the sluggishness. Detect purely by id against ONE snapshot of live
-- ids per pass: hs.window.get(id) re-scans every app's windows on each call.
local function liveIds()
  local set = {}
  for _, w in ipairs(hs.window.allWindows()) do set[w:id()] = w end
  return set
end

local function isDead(w, live)
  if not w then return true end
  local id = w:id()
  return not id or not live[id]
end

-- Prune dead windows from PaperWM's own state so the phantom column disappears
-- everywhere — widget count AND focus navigation. refreshWindows() does NOT fix
-- this (it re-adds them), so we remove them directly, BY ID ONLY: this mirrors
-- PaperWM's removeWindow minus its focus loop and its title() logging, both of
-- which touch the dead AX element and can hang. One at a time (removals shift
-- indices), bounded so a stubborn entry never loops forever.
local lastPrune = 0
function M.pruneDead(space)
  local pwm = paperwm.pwm
  if not pwm then return false end
  space = space or hs.spaces.focusedSpace()
  local removed = false
  local live = liveIds()
  for _ = 1, 12 do
    local list = pwm.state.windowList(space)
    if not list then break end
    local target, tcol, trow
    for c = 1, #list do
      for r = 1, #list[c] do
        if isDead(list[c][r], live) then target, tcol, trow = list[c][r], c, r; break end
      end
      if target then break end
    end
    if not target then break end
    pwm.state.windowIndex(target, true)                 -- drop from the id index (by id)
    -- through the column proxy: its __newindex drops an emptied column and
    -- re-runs update_index, so the surviving rows keep correct indices
    table.remove(pwm.state.windowList(space, tcol), trow)
    pcall(function() pwm.state.xPositions(space)[target:id()] = nil end)
    pcall(function() pwm.state.uiWatcherDelete(target:id()) end)
    removed = true
  end
  if removed then pcall(function() pwm:tileSpace(space) end) end
  return removed
end

-- { columns = { { wins, ratio } … }, floating = { win … }, col, total, space }
local function computeStrip()
  local pwm = paperwm.pwm
  if not pwm then return nil end

  local focused = hs.window.focusedWindow()
  local index = focused and pwm.state.windowIndex(focused) or nil
  local space = index and index.space or hs.spaces.focusedSpace()

  local list = pwm.state.windowList(space)

  -- Heal zombie columns (an app that quit left a dead window behind). Debounced
  -- so a prune that can't fully clear one never thrashes; the column loop below
  -- also skips any dead entry defensively, so the widget never renders or
  -- measures one even before the prune lands.
  local live = liveIds()
  if list then
    for c = 1, #list do
      if isDead(list[c] and list[c][1], live) then
        local now = hs.timer.secondsSinceEpoch()
        if now - lastPrune > 3 then
          lastPrune = now
          M.pruneDead(space)
          list = pwm.state.windowList(space) -- re-read the healed list
        end
        break
      end
    end
  end

  -- width is measured against PaperWM's canvas, not the raw screen
  local screen = focused and focused:screen() or hs.screen.mainScreen()
  local canvas = pwm.windows.getCanvas(screen)

  -- PaperWM keeps a virtual x for every window, which is where the column
  -- really sits on the strip even when macOS has parked it in the edge margin.
  -- That is what lets the map show what is off-screen.
  local xpos = pwm.state.xPositions(space)
  local columns = {}
  local stripOf = {} -- PaperWM column -> strip column (they differ past a dead one)
  local left, right
  if list then
    for col = 1, #list do
      if not isDead(list[col][1], live) then
        stripOf[col] = #columns + 1
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
          pcol = col,
        }
        left = left and math.min(left, vx) or vx
        right = right and math.max(right, vx + w) or (vx + w)
      end
    end
  end

  -- floating windows vanish from the strip, which is exactly why they are
  -- hard to get back — surface them next to it
  local floating = {}
  for id, _ in pairs(pwm.state.is_floating) do
    local w = live[id]
    if w and w:isVisible() and (hs.spaces.windowSpaces(w) or {})[1] == space then
      floating[#floating + 1] = w
    end
  end
  table.sort(floating, function(a, b) return M.shortName(a) < M.shortName(b) end)

  if #columns == 0 and #floating == 0 then return nil end

  -- macOS intermittently reports no focused window (notably right after a
  -- click on an overlay). Fall back to the last column we knew about, so the
  -- map keeps its chips and chevrons instead of going blank.
  local col = index and stripOf[index.col] or nil
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

function M.strip()
  local now = hs.timer.secondsSinceEpoch()
  if stripCache and (now - stripCacheAt) < STRIP_TTL then return stripCache end
  stripCache, stripCacheAt = computeStrip(), now
  return stripCache
end

function M.minRatio() return paperwmfit.MIN end

-- Fit-mode menu toggles: not window mutations, but still paperwmfit internals
-- the coordinator must not touch directly.
function M.fitEnabled() return paperwmfit.enabled end
function M.toggleFit() paperwmfit.toggle() end
function M.clearFloors() paperwmfit.clearFloors() end
function M.clearAppWidths() paperwmfit.clearAppWidths() end

-- The preset width chips/menu entries are driven by PaperWM's own list.
function M.widthRatios()
  local pwm = paperwm.pwm
  return pwm and pwm.window_ratios or {}
end

function M.refreshWindows()
  if paperwm.pwm then paperwm.pwm.windows.refreshWindows() end
end

-- ── mutations ───────────────────────────────────────────────────
-- The coordinator (paperwmui) registers one coalesced redraw callback here;
-- every mutation fires it after changing state.
function M.onChange(fn) M.changeCb = fn end

local function afterChange()
  if M.changeCb then M.changeCb() end
end

-- exact ratio, mirroring how PaperWM's own cycleWindowSize computes it
function M.setWidth(win, ratio)
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

-- widget chip / menu: same toggle (and same memory) as the hotkey
function M.fullWidth(win) M.toggleFullWidth(win) end

-- Some apps refuse to shrink past a hard minimum (Chromium stops at ~500px).
-- On a narrow display that can be 40%+ of the screen, so a width you pick below
-- it simply cannot happen — the UI has to say so instead of ignoring you.
function M.floorRatio(win)
  local pwm = paperwm.pwm
  if not (pwm and win) then return paperwmfit.MIN end
  local canvas = pwm.windows.getCanvas(win:screen())
  local px = paperwmfit.floor[win:id()]
  if not (px and canvas.w > 0) then return paperwmfit.MIN end
  return math.max(paperwmfit.MIN, px / canvas.w)
end

-- Scroll the row so the screen shows the slice starting at `offset` px from
-- the strip's left edge. tileSpace takes an explicit anchor, so we pick a
-- column that will actually be on screen and pin it at the right spot.
function M.scrollToStrip(s, offset)
  local pwm = paperwm.pwm
  if not (pwm and s) then return end
  offset = geom.clampOffset(offset, s.stripW, s.canvas.w)

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
  M.invalidate()
end

-- Public wrapper: scroll the row to an absolute offset. Also lets the
-- behaviour be verified without synthesising mouse drags.
function M.scrollTo(offset)
  local cur = M.strip()
  if cur then M.scrollToStrip(cur, offset) end
  return cur and cur.canvas.x - cur.left or nil
end

-- Nudge the view for the ◀ ▶ buttons. Stepping to the next column boundary
-- was too coarse — columns are often half the screen wide — so move by a fixed
-- slice of the screen instead and let the view land wherever it lands.
M.STEP = 0.15  -- share of the screen width per press

function M.scrollStep(dir)
  local cur = M.strip()
  if not cur then return end
  local offset = cur.canvas.x - cur.left
  M.scrollTo(offset + dir * cur.canvas.w * M.STEP)
end

-- Move a column to a given position. swapWindows() would be the obvious call
-- but it acts on the focused window, and focus is exactly what a click on an
-- overlay disturbs — this list surgery works no matter what holds focus.
function M.moveColumn(space, from, to)
  local pwm = paperwm.pwm
  if not pwm or from == to then return end
  -- callers pass strip indices; translate to PaperWM's (dead columns are skipped)
  local s = M.strip()
  local a, b = s and s.columns[from], s and s.columns[to]
  if not (a and b) then return end
  from, to = a.pcol, b.pcol
  local list = pwm.state.windowList(space)
  if not (list and list[from] and list[to]) then return end
  local column = table.remove(list, from)
  table.insert(list, to, column)
  pwm:tileSpace(space)
  afterChange()
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

function M.stack(win)
  local pwm = paperwm.pwm
  if not pwm then return end
  withFocus(win, pwm.windows.slurpWindow)
end

function M.unstack(win)
  local pwm = paperwm.pwm
  if not pwm then return end
  withFocus(win, pwm.windows.barfWindow)
end

-- toggleFloating() takes an explicit window, so moving one in or out of the
-- floating layer never depends on focus
function M.toggleFloat(win)
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

function M.toggleFullWidth(win)
  local pwm = paperwm.pwm
  if not pwm then return end

  win = win or hs.window.focusedWindow()
  if not win then
    local cur = M.strip()
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
    M.setWidth(win, back)
    hs.alert.show(string.format("⇔ back to %d%%", math.floor(back * 100 + 0.5)), 0.7)
  else
    M.beforeFull[id] = intent
    M.setWidth(win, 1.0)
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
    if prev.floating then
      -- it floated before the zoom: stay floating, just give the frame back
      win:setFrame(prev.frame)
      afterChange()
      hs.alert.show("⤢ back", 0.8)
      return
    end
    if pwm.floating.isFloating(win) then pwm.floating.toggleFloating(win) end
    -- setWidth, not setDesired+refit: refit is a no-op while fit mode is off,
    -- and the window rejoins the row at its full-screen frame. Wait for the
    -- retile toggleFloating kicks off, as the zoom path does.
    hs.timer.doAfter(hs.window.animationDuration + 0.08, function()
      M.setWidth(win, prev.ratio or 0.5)
    end)
    hs.alert.show("⤢ back to the row", 0.8)
    return
  end

  local canvas = pwm.windows.getCanvas(win:screen())
  M.zoomed[id] = {
    ratio = canvas.w > 0 and (win:frame().w / canvas.w) or nil,
    floating = pwm.floating.isFloating(win),
    frame = win:frame(),
  }

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

return M
