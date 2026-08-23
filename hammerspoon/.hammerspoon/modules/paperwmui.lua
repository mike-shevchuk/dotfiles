-- PaperWM widget: menubar counter + interactive map of the window strip
-- Answers what tiling never shows you: where am I in the row, how wide is
-- each window, and what fell out of the row entirely. Pinned, it is also a
-- control panel: click a box to focus, ◀ ▶ to reorder, chips to resize,
-- stack/unstack to build columns, and ⊘ boxes to pull floating windows back.
local M = {}

local paperwm = require("modules.paperwm")
local focusborder = require("modules.focusborder")
local model = require("modules.paperwmmodel")
local render = require("modules.paperwmrender")
local interact = require("modules.paperwminteract")

-- frozen public API: re-export the mutations that moved into the model
M.toggleFullWidth  = model.toggleFullWidth
M.toggleFullscreen = model.toggleFullscreen

local CHEATSHEET = "file://" .. os.getenv("HOME") ..
    "/zettelkasten/claude_code/tools/paperwm-cheatsheet.html"

local FLASH_SEC = 1.6

M.menubar = nil
M.pinned = false
M.hideTimer = nil
M.filter = nil
M._geom = nil -- geometry published each draw; interact reads it via ctx getters

-- ctx getters interact needs; built once and reused across draws since
-- interact only re-attaches when the canvas identity changes
M.ctx = {
  boxes       = function() return M._geom.boxes end,
  viewport    = function() return M._geom.viewport end,
  sliders     = function() return M._geom.slider, M._geom.scrollSlider end,
  canvasFrame = function() return M._geom.canvasFrame end,
  pinned      = function() return M.pinned end,
  togglePin   = function() M.togglePin() end,
  afterUpdate = function() M.update() end,
}

function M.screenForDraw()
  local win = hs.window.focusedWindow()
  return (win and win:screen()) or hs.screen.mainScreen()
end

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
function M.draw()
  if interact.isDragging() then return end
  local s = model.strip()
  if not s then render.hide(); return end
  local g = render.draw(s, { pinned = M.pinned, screen = M.screenForDraw() })
  M._geom = g
  interact.ensureAttached(render.canvas(), M.ctx)
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

  if M.pinned or (render.canvas() and render.canvas():isShowing()) then M.draw() end
end

-- show briefly, the way a volume HUD does
local function flash()
  if M.pinned then M.update(); return end
  M.draw()
  if M.hideTimer then M.hideTimer:stop() end
  M.hideTimer = hs.timer.doAfter(FLASH_SEC, function()
    if not M.pinned then render.hide() end
  end)
end

-- pinned = stays up and accepts clicks
function M.togglePin()
  M.pinned = not M.pinned
  if M.hideTimer then M.hideTimer:stop() end
  if M.pinned then M.draw() else render.hide() end
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
