-- PaperWM.spoon — scrollable tiling window manager
-- https://github.com/mogenson/PaperWM.spoon (cloned to ~/.hammerspoon/Spoons/)
--
-- Base chord is ctrl+alt+cmd, NOT the upstream default alt+cmd: Chromium
-- browsers use cmd+alt+left/right for tab switching and a global Hammerspoon
-- hotkey would shadow it everywhere.
local guard = require("modules.guard")
local paperwmfit = require("modules.paperwmfit")

local M = {}

local mod  = { "ctrl", "alt", "cmd" }
local mods = { "ctrl", "alt", "cmd", "shift" }

M.pwm = nil
M.running = false

-- PaperWM silently drops a keypress (logs "focused index not found") when the
-- focused window is not in its index yet — happens right after ⌘Tab to a
-- hidden app or un-minimising, before the window watcher catches up. Re-index
-- once first so the key always does something. refreshWindows() is synchronous.
local function healed(fn)
  return function()
    local w = hs.window.focusedWindow()
    if w and w:isStandard()
        and not M.pwm.state.isTiled(w:id())
        and not M.pwm.floating.isFloating(w) then
      M.pwm.windows.refreshWindows()
    end
    fn()
  end
end

-- A width changed with the keyboard is the user's intent. Fit mode must not
-- mistake its own compression for that, so record the focused width once the
-- resize has landed.
local function sized(fn)
  local run = healed(fn)
  return function()
    -- Keep fit off our back until the new width has been recorded as intent.
    -- The window animates AND PaperWM re-tiles the row afterwards, so reading
    -- the result one animation later was still too early: it captured the old
    -- width and fit then dutifully restored it.
    -- grab the target now, while focus is still readable
    local target = hs.window.focusedWindow()
    paperwmfit.hold(1.1)
    run()
    hs.timer.doAfter(hs.window.animationDuration * 2 + 0.25, function()
      paperwmfit.captureFocused(target)
    end)
  end
end

local function bindHotkeys()
  local a = M.pwm.actions.actions()

  -- focus: arrows and vim keys
  guard.bind(mod, "left",  healed(a.focus_left))
  guard.bind(mod, "right", healed(a.focus_right))
  guard.bind(mod, "up",    healed(a.focus_up))
  guard.bind(mod, "down",  healed(a.focus_down))
  guard.bind(mod, "H", healed(a.focus_left))
  guard.bind(mod, "J", healed(a.focus_down))
  guard.bind(mod, "K", healed(a.focus_up))
  guard.bind(mod, "L", healed(a.focus_right))

  -- swap window with its neighbour
  guard.bind(mods, "H", healed(a.swap_left))
  guard.bind(mods, "J", healed(a.swap_down))
  guard.bind(mods, "K", healed(a.swap_up))
  guard.bind(mods, "L", healed(a.swap_right))

  -- Arrows reorder inside the row, like the vim keys above. They used to throw
  -- the window at another display, which on a single screen just looked broken.
  guard.bind(mods, "left",  healed(a.swap_left))
  guard.bind(mods, "right", healed(a.swap_right))
  guard.bind(mods, "up",    healed(a.swap_up))
  guard.bind(mods, "down",  healed(a.swap_down))

  -- send the window to another display, on the brackets that already mean
  -- "other screen" in this config (hyper [ and ])
  guard.bind(mods, "[", healed(a.move_window_l))
  guard.bind(mods, "]", healed(a.move_window_r))

  -- size and position
  guard.bind(mod,  "C", healed(a.center_window))
  -- mod+F (full width) is bound in init.lua to paperwmui.toggleFullWidth
  guard.bind(mod,  "R", sized(a.cycle_width))
  guard.bind(mods, "R", healed(a.cycle_height))
  guard.bind(mod,  "=", sized(a.increase_width))
  guard.bind(mod,  "-", sized(a.decrease_width))
  guard.bind(mods, ",", healed(a.anchor_window_left))
  guard.bind(mods, ".", healed(a.anchor_window_right))

  -- columns: pull neighbour in / push window out
  guard.bind(mod, "I", healed(a.slurp_in))
  guard.bind(mod, "O", healed(a.barf_out))
  guard.bind(mod, "S", healed(a.split_screen))

  -- floating layer
  guard.bind(mods, "escape", a.toggle_floating)
  guard.bind(mods, "F",      a.focus_floating)

  -- spaces: ,/. step left/right, digits jump, shift+digit throws the window
  guard.bind(mod, ",", a.switch_space_l)
  guard.bind(mod, ".", a.switch_space_r)
  for i = 1, 9 do
    guard.bind(mod,  tostring(i), a["switch_space_" .. i])
    guard.bind(mods, tostring(i), healed(a["move_window_" .. i]))
  end

  guard.bind(mod, "0", a.refresh_windows)
end

-- One window-event filter shared by the widget, the focus border and fit mode.
-- Each used to build its own hs.window.filter, so every window event was
-- watched and dispatched three times over — pure overhead on every focus
-- change, and part of why the overlay felt sluggish.
M.events = nil

function M.subscribe(events, fn)
  if not M.events then
    M.events = hs.window.filter.new():setOverrideFilter({ visible = true })
  end
  M.events:subscribe(events, fn)
  return M.events
end

-- Toggle tiling without touching the hotkeys — off restores free-floating
-- windows so modules/windows.lua halves and thirds work again.
function M.toggle()
  if M.running then
    M.pwm:stop()
    M.running = false
    hs.alert.show("📄 PaperWM OFF", 1)
  else
    M.pwm:start()
    M.running = true
    hs.alert.show("📄 PaperWM ON", 1)
  end
end

function M.start(autostart)
  M.pwm = hs.loadSpoon("PaperWM")

  M.pwm.window_gap = 8
  M.pwm.window_ratios = { 1 / 3, 1 / 2, 2 / 3 }
  M.pwm.infinite_loop_window = true

  -- keep the floating HS panels (scratchpad, gitpanel, notetaker, …) untiled
  M.pwm.window_filter:rejectApp("Hammerspoon")

  paperwmfit.init(M)
  bindHotkeys()

  if autostart then
    M.pwm:start()
    M.running = true
  end
end

return M
