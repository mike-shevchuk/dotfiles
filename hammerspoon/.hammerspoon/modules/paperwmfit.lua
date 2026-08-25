-- Fit mode: squeeze the row to fit the screen (keep-focus strategy).
--
-- PaperWM lets the row grow longer than the screen and parks the overflow in a
-- 1px margin — you get a sliver of a window instead of a window. Fit prevents
-- that: when the columns' wanted widths exceed the screen, the FOCUSED column
-- keeps its width and every other column shrinks by one proportional factor
-- (each floored at MIN), so the whole row fits and nothing is crushed just for
-- being last. Switching focus is the only thing that reshuffles widths.
--
-- Fit defaults OFF and remembers your choice; off, windows keep their widths and
-- PaperWM scrolls the overflow (the widget map shows where off-screen windows are).
-- The width computation itself lives in geom.fitWidths (pure, unit-tested).
local geom = require("modules.paperwmgeom")

local M = {}

-- injected by modules.paperwm to avoid a require cycle
M.pw = nil
function M.init(pw) M.pw = pw end

local ENABLED_KEY <const> = "PaperWM_fit_enabled"
M.enabled = hs.settings.get(ENABLED_KEY) == true  -- default OFF (per your preference)
M.MIN = 0.10        -- narrowest a squeezed column may get, as a share of the canvas
M.APP_CAP = 0.85    -- never remember an app wider than this: one app can't claim the whole row
M.desired = {}      -- window id -> width the user actually wants, as a share
M.applied = {}      -- window id -> width in px we last wrote, to spot user edits
M.floor = {}        -- window id -> narrowest width the app actually accepts
M.floorSeen = {}    -- id -> candidate awaiting a second, confirming observation
M.FLOOR_CAP = 0.6   -- a real minimum above this share of the screen is a misread
M.lastCol = nil
M.lastSureCol = nil -- last column we positively knew was focused
M.timer = nil
M.filter = nil

-- Window ids die with the session, so a width set today was gone after the next
-- reload and fit re-seeded it from whatever the layout happened to be. Remember
-- widths per APP instead and persist them: that survives reloads and restarts,
-- and a freshly opened window of a known app starts at the width you like.
local WIDTH_KEY <const> = "PaperWM_app_widths"

M.appWidth = hs.settings.get(WIDTH_KEY) or {}

-- Neutralise any previously-saved oversize widths (e.g. Thorium/Code at 100%),
-- which used to force those apps to fill the row and push neighbours off-screen.
do
  local capped = false
  for name, ratio in pairs(M.appWidth) do
    if ratio > M.APP_CAP then M.appWidth[name] = M.APP_CAP; capped = true end
  end
  if capped then hs.settings.set(WIDTH_KEY, M.appWidth) end
end

local function appOf(win)
  local app = win and win:application()
  return app and app:name() or nil
end

local function rememberApp(win, ratio)
  local name = appOf(win)
  if not name then return end
  M.appWidth[name] = math.min(ratio, M.APP_CAP)
  hs.settings.set(WIDTH_KEY, M.appWidth)
end

-- A resize made with the keyboard lands, and ~0.2s later fit recomputes from
-- the OLD remembered width and puts it straight back — the change was gone
-- before captureFocused could record it. Holding fit off for a moment lets the
-- new width survive long enough to become the remembered one.
function M.hold(sec)
  M.heldUntil = hs.timer.secondsSinceEpoch() + (sec or 0.7)
end

local function held()
  return M.heldUntil and hs.timer.secondsSinceEpoch() < M.heldUntil
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Recompute widths for one space and lay it out.
function M.fit(space)
  local pwm = M.pw and M.pw.pwm
  if not (M.enabled and pwm and M.pw.running) then return end
  if held() then return end

  space = space or hs.spaces.focusedSpace()
  local list = pwm.state.windowList(space)
  if not list or #list < 2 then return end

  local n = #list
  local first = list[1][1]
  if not first then return end

  local canvas = pwm.windows.getCanvas(first:screen())
  local gap = pwm.windows.getGap("right")
  local avail = canvas.w - (n - 1) * gap
  local minpx = math.floor(M.MIN * canvas.w)

  -- with this many columns even the minimum will not fit; let PaperWM scroll
  if n * minpx > avail then return end

  -- Which column keeps its width. A column the user just resized wins over the
  -- focused one: clicking a width control on the overlay can drop focus, and
  -- without this the very window you widened is the one that gets squeezed.
  -- `sure` records whether we actually know which column is focused. A guess
  -- must never be trusted to mean "the last column is active", or the row is
  -- left overflowing the screen on a bad focus read.
  -- A failed focus read is not evidence that focus moved — macOS just didn't
  -- answer. Treating it as "focus is elsewhere" made the last column shrink
  -- while it was actually the active one, so it never got its width back.
  local focused = hs.window.focusedWindow()
  local index = focused and pwm.state.windowIndex(focused) or nil
  local fcol, sure
  if M.pinCol and M.pinCol.space == space then
    fcol, sure = M.pinCol.col, true
  elseif index and index.space == space then
    fcol, sure = index.col, true
    M.lastSureCol = fcol
  elseif M.lastSureCol and list[M.lastSureCol] then
    fcol, sure = M.lastSureCol, true
  else
    fcol, sure = M.lastCol, false
  end
  if not (fcol and list[fcol]) then fcol, sure = 1, false end
  M.lastCol = fcol
  M.pinCol = nil

  -- Intent is never re-read from the screen: the widths on screen are partly
  -- our own compression, so inferring from them feeds back on itself. A window
  -- is measured once, when first seen; after that only an explicit width change
  -- updates it (see captureFocused / setDesired).
  --
  -- floors are per-app truths we learn the hard way: Chromium refuses to go
  -- below roughly 500px no matter what we set, so pretending it can shrink to
  -- 10% just pushes the row off the screen again.
  local want, floor = {}, {}
  for i = 1, n do
    local win = list[i][1]
    local id = win:id()
    if M.desired[id] == nil then
      M.desired[id] = M.appWidth[appOf(win)] or (win:frame().w / canvas.w)
    end
    floor[i] = math.max(minpx, M.floor[id] or 0)
    want[i] = clamp(M.desired[id] * canvas.w, floor[i], avail)
  end


  -- Keep-focus fit: the focused column keeps its width; the others shrink
  -- proportionally (each floored) so the row fits. Nothing is crushed to MIN
  -- just for being last. On a bad focus read (`sure` false) fall back to the
  -- last column as the anchor rather than trusting a guess. (geom.fitWidths is
  -- pure + unit-tested; it returns `want` unchanged when the row already fits.)
  local widths = geom.fitWidths(want, floor, avail, sure and fcol or n)

  local total = 0
  for i = 1, n do total = total + widths[i] end
  local fits = total <= avail

  -- apply: tileColumn takes a column's width from its first window, and
  -- tileSpace lays every other column out from the anchor, so setting the
  -- first window of each column plus the anchor's x is enough
  for i = 1, n do
    local win = list[i][1]
    local f = win:frame()
    if math.abs(f.w - widths[i]) > 1 then
      f.w = widths[i]
      pwm.windows.moveWindow(win, f)
    end
    M.applied[win:id()] = widths[i]
  end

  -- Pin the row to the left edge only when the whole thing fits. If it does
  -- not (the last column is focused, or floors won the argument), leave the
  -- anchor alone so PaperWM scrolls the way it normally would.
  if fits then
    local x = canvas.x
    for i = 1, fcol - 1 do x = x + widths[i] + gap end
    local anchor = list[fcol][1]
    local af = anchor:frame()
    if math.abs(af.x - x) > 1 or math.abs(af.w - widths[fcol]) > 1 then
      af.x, af.w = x, widths[fcol]
      pwm.windows.moveWindow(anchor, af)
    end
  end

  -- setFrame is animated. tileSpace reads each column's width straight off its
  -- first window, so calling it now would read the pre-animation width and
  -- quietly undo everything above — wait for the resize to land.
  if M.tileTimer then M.tileTimer:stop() end
  M.tileTimer = hs.timer.doAfter(hs.window.animationDuration + 0.05, function()
    -- An app that came out wider than we asked has told us its minimum — but
    -- only if we can trust the reading. A resize still in flight looks exactly
    -- like a refusal, and one bad sample used to stick forever (a whole
    -- 1904px "minimum" was recorded that way, blocking every width).
    -- So: ignore implausibly large values, and require two agreeing samples.
    local learned = false
    local cap = M.FLOOR_CAP * canvas.w
    -- this runs a quarter-second later: a window may have closed and the column
    -- count shrunk, so re-check every lookup rather than trusting the old n
    for i = 1, math.min(n, #list) do
      local win = list[i] and list[i][1]
      local frame = win and win:frame()
      if not frame then goto continue end
      local id = win:id()
      local actual = frame.w
      if actual > widths[i] + 4 and actual <= cap then
        local seen = M.floorSeen[id]
        if seen and math.abs(seen - actual) <= 8 then
          if (M.floor[id] or 0) < actual then
            M.floor[id] = actual
            learned = true
          end
          M.floorSeen[id] = nil
        else
          M.floorSeen[id] = actual
        end
      else
        M.floorSeen[id] = nil
      end
      M.applied[id] = actual
      ::continue::
    end
    pwm:tileSpace(space)
    -- recompute once with the new knowledge, but never loop on it
    if learned and not M.relearning then
      M.relearning = true
      if M.relearnTimer then M.relearnTimer:stop() end
      M.relearnTimer = hs.timer.doAfter(0.35, function()
        M.relearning = false
        M.fit(space)
      end)
    end
  end)
end

-- the widget and the hotkeys change widths; give the move time to land
function M.refit()
  if M.timer then M.timer:stop() end
  M.timer = hs.timer.doAfter(0.22, function() M.fit() end)
end

-- called when the user picks a width explicitly, so we do not mistake our own
-- compression for their intent
function M.setDesired(win, ratio)
  if not win then return end
  M.desired[win:id()] = ratio
  rememberApp(win, ratio)
  local pwm = M.pw and M.pw.pwm
  local idx = pwm and pwm.state.windowIndex(win)
  if idx then M.pinCol = { space = idx.space, col = idx.col } end
end

-- The focused column is the one we never compress, so whatever width it has
-- right now is what the user meant. Call this after a keyboard width change.
-- `win` is passed in by the keyboard wrappers, which grab it before acting.
-- Reading focusedWindow() here instead was the last hole: when macOS answered
-- nil the new width was never recorded, the hold expired, and fit restored the
-- old width — which is exactly what "⌃⌥⌘F does nothing" looked like.
function M.captureFocused(win)
  local pwm = M.pw and M.pw.pwm
  win = win or hs.window.focusedWindow()
  if not (pwm and win) then
    M.heldUntil = nil
    return
  end
  local canvas = pwm.windows.getCanvas(win:screen())
  if canvas.w <= 0 then return end

  -- Only record a width the user actually produced. If the window still sits at
  -- the width we last wrote, nothing was changed by hand and capturing would
  -- just bake in our own compression as if it were their choice.
  local id, actual = win:id(), win:frame().w
  if M.applied[id] and math.abs(actual - M.applied[id]) <= 12 then return end

  -- Deliberately per-window only: a keyboard nudge is transient tweaking, not a
  -- preference. Persisting it here meant one ⌃⌥⌘R on any Thorium window rewrote
  -- the remembered width for EVERY Thorium window, and the next re-seed dragged
  -- them all to it — which is exactly how a width you had set "reset" itself.
  -- Only an explicit pick in the widget (setDesired) is worth remembering.
  M.desired[id] = actual / canvas.w

  -- Pin it, the same way an explicit pick in the widget does. Without this the
  -- very next fit treated the freshly-resized window as fair game and squeezed
  -- it straight back — which is why ⌃⌥⌘F looked like it did nothing.
  local idx = pwm.state.windowIndex(win)
  if idx then M.pinCol = { space = idx.space, col = idx.col } end

  M.heldUntil = nil
  M.refit()
end

-- clears remembered widths and re-measures everything from the current layout
function M.reset()
  M.desired, M.applied = {}, {}
  M.fit()
end

-- forget the learned per-app minimums, so a bad reading can be undone
function M.clearFloors()
  M.floor, M.floorSeen = {}, {}
  M.fit()
  hs.alert.show("⇔ learned minimums cleared", 1.2)
end

-- forget saved per-app widths (and current per-window intents), so sizes stop
-- being re-forced from a stale remembered value
function M.clearAppWidths()
  M.appWidth = {}
  hs.settings.set(WIDTH_KEY, {})
  M.desired = {}
  M.fit()
  hs.alert.show("⇔ saved window widths cleared", 1.2)
end

function M.forget(win)
  if not win then return end
  local id = win:id()
  M.desired[id], M.applied[id] = nil, nil
  M.floor[id], M.floorSeen[id] = nil, nil
end

function M.toggle()
  M.enabled = not M.enabled
  hs.settings.set(ENABLED_KEY, M.enabled)  -- remember the choice across reloads
  if M.enabled then
    M.fit()
    hs.alert.show("⇔ fit mode on — windows squeeze to fit", 1.5)
  else
    -- give everyone their real width back and let PaperWM scroll again
    local pwm = M.pw and M.pw.pwm
    if pwm and M.pw.running then
      local space = hs.spaces.focusedSpace()
      local list = pwm.state.windowList(space)
      local canvas = list and list[1] and pwm.windows.getCanvas(list[1][1]:screen())
      if list and canvas then
        for i = 1, #list do
          local win = list[i][1]
          local want = M.desired[win:id()]
          if want then
            local f = win:frame()
            f.w = want * canvas.w
            pwm.windows.moveWindow(win, f)
          end
          M.applied[win:id()] = nil
        end
        pwm:tileSpace(space)
      end
    end
    hs.alert.show("⇔ fit mode off — windows scroll off-screen", 1.5)
  end
end

function M.start()
  if not M.pw then return end

  M.filter = M.pw.subscribe({
    hs.window.filter.windowFocused,
    hs.window.filter.windowCreated,
    hs.window.filter.windowDestroyed,
  }, function() M.refit() end)

  -- Prune by checking whether the id still resolves, rather than trusting a
  -- destroy event to fire: an id that no longer maps to a window is stale, and
  -- macOS recycles ids, so a leftover entry could hand a new window someone
  -- else's width.
  M.pruneTimer = hs.timer.doEvery(120, function()
    for id in pairs(M.desired) do
      if not hs.window.get(id) then
        M.desired[id], M.applied[id] = nil, nil
        M.floor[id], M.floorSeen[id] = nil, nil
      end
    end
  end)

  M.startTimer = hs.timer.doAfter(1.0, function() M.fit() end)
end

return M
