--
-- Hammerspoon Config
-- All hotkeys use alt+shift as the modifier
-- Master toggle via menubar icon (hammer/stop)
--

local guard       = require("modules.guard")
local windows     = require("modules.windows")
local apps        = require("modules.apps")
local audio       = require("modules.audio")
local clipboard   = require("modules.clipboard")
local system      = require("modules.system")
local sidecar     = require("modules.sidecar")
local mousefinder = require("modules.mousefinder")
local scratchpad  = require("modules.scratchpad")
local brightness  = require("modules.brightness")
local notetaker   = require("modules.notetaker")
local gitpanel    = require("modules.gitpanel")
local launcher    = require("modules.launcher")
local pomodoro    = require("modules.pomodoro")
local screenshot  = require("modules.screenshot")
local dropdown    = require("modules.dropdown")
local linear      = require("modules.linear")
local todoist     = require("modules.todoist")
local bookmarks   = require("modules.bookmarks")
local sysmonitor  = require("modules.sysmonitor")
local paperwm     = require("modules.paperwm")
local paperwmui   = require("modules.paperwmui")
local focusborder = require("modules.focusborder")
local paperwmfit  = require("modules.paperwmfit")
local winjump     = require("modules.winjump")

-- `hs -c "..."` CLI (binary comes from the hammerspoon brew formula)
require("hs.ipc")

-- ─── Master toggle (integrated into sysmonitor menubar) ─────────
guard.start(true)

-- ─── Hyper modifier ─────────────────────────────────────────────
local hyper = { "alt", "shift" }

-- ─── App Launchers ──────────────────────────────────────────────
-- ` (backtick) = dropdown terminal (Quake-style Ghostty)
guard.bind(hyper, "`", dropdown.toggle)
guard.bind(hyper, "G", apps.toggle("Ghostty"))
guard.bind(hyper, "B", apps.toggle("Thorium"))
guard.bind(hyper, "S", apps.toggle("Safari"))

-- ─── Window Management ─────────────────────────────────────────
-- Halves
guard.bind(hyper, "Left",  windows.move("left_half"))
guard.bind(hyper, "Right", windows.move("right_half"))
guard.bind(hyper, "Up",    windows.maximize)
guard.bind(hyper, "Down",  windows.center)

-- Thirds (use ctrl+alt+shift for less common layouts)
local hyper2 = { "ctrl", "alt", "shift" }
guard.bind(hyper2, "Left",  windows.move("left_third"))
guard.bind(hyper2, "Right", windows.move("right_third"))
guard.bind(hyper2, "Up",    windows.move("left_two_thirds"))
guard.bind(hyper2, "Down",  windows.move("right_two_thirds"))

-- Move to other screen
guard.bind(hyper, "[", windows.screenLeft)
guard.bind(hyper, "]", windows.screenRight)

-- ─── PaperWM (scrollable tiling) ────────────────────────────────
-- Own chord: ctrl+alt+cmd (+shift). O = toggle tiling on/off, because while
-- tiling is on it re-tiles windows and overrides the halves/thirds above.
paperwm.start(true)
guard.bind(hyper, "O", paperwm.toggle)

-- U = flash the strip map (or unpin it); menubar shows position, e.g. 📄 3/6
paperwmui.start()
guard.bind(hyper, "U", paperwmui.show)

-- X = border around the focused window: blue when tiled, amber when floating
focusborder.start()
guard.bind(hyper, "X", focusborder.toggle)

-- Fit mode: squeeze the row to fit the screen instead of clipping at the edge
paperwmfit.start()

-- ctrl+alt+cmd+Space = jump to any window by app or tab name
-- (mirrors alt+shift+Space, which is the app launcher)
guard.bind({ "ctrl", "alt", "cmd" }, "Space", winjump.show)

-- ctrl+alt+cmd+F = full WIDTH (stays in the row), and back to previous width
guard.bind({ "ctrl", "alt", "cmd" }, "F", paperwmui.toggleFullWidth)

-- ctrl+alt+cmd+Return = full SCREEN for the focused window, and back
guard.bind({ "ctrl", "alt", "cmd" }, "return", paperwmui.toggleFullscreen)

-- ─── Clipboard ──────────────────────────────────────────────────
clipboard.start()
guard.bind(hyper, "V", clipboard.toggle)

-- Paste bypass (type clipboard contents to defeat paste-blockers)
guard.bind(hyper, "K", apps.pasteBypass)

-- ─── Audio ──────────────────────────────────────────────────────
audio.start()
guard.bind(hyper, "M", audio.toggleMute)

-- ─── System ─────────────────────────────────────────────────────
guard.bind(hyper, "L", system.toggleDarkMode)
guard.bind(hyper, "T", system.emptyTrash)
guard.bind(hyper, "P", system.togglePinchZoom)

-- ─── Displays ───────────────────────────────────────────────────
-- I = pick a display to set as main (via displayplacer)
-- N = toggle mirror <-> extended display
guard.bind(hyper, "I", sidecar.showDisplayChooser)
guard.bind(hyper, "N", sidecar.toggleMirror)

-- ─── Mouse Finder ───────────────────────────────────────────────
-- F = flash crosshair at mouse position
guard.bind(hyper, "F", mousefinder.find)

-- ─── Scratchpad ─────────────────────────────────────────────────
-- J = toggle floating notepad (persists across reloads)
guard.bind(hyper, "J", scratchpad.toggle)

-- ─── Brightness ─────────────────────────────────────────────────
-- D = brightness sliders for all monitors
guard.bind(hyper, "D", brightness.toggle)

-- ─── Notetaker (Zettelkasten) ────────────────────────────────────
-- Y = daily/weekly note panel (saves to ~/zettelkasten/comb-notes/)
guard.bind(hyper, "Y", notetaker.toggle)

-- ─── Git Panel ───────────────────────────────────────────────────
-- Z = floating git panel: status, commit msg, pull/commit/push buttons
guard.bind(hyper, "Z", gitpanel.toggle)

-- ─── Launcher (command palette) ─────────────────────────────────
-- Space = app launcher + commands with fuzzy search
guard.bind(hyper, "Space", launcher.show)

-- ─── Bookmarks ──────────────────────────────────────────────────
-- Q = quick URL bookmarks with fuzzy search
guard.bind(hyper, "Q", bookmarks.show)

-- ─── Pomodoro ───────────────────────────────────────────────────
-- W = start/stop pomodoro timer (integrated into sysmonitor menubar)
guard.bind(hyper, "W", pomodoro.toggle)

-- ─── Screenshot + Annotate ──────────────────────────────────────
-- A = capture area, annotate with arrows/rects/text, copy
guard.bind(hyper, "A", screenshot.capture)

-- ─── Task Widgets (Linear + Todoist) ────────────────────────────
-- Menubar: "Tasks" dropdown to toggle/switch individual widgets
-- E = toggle both widgets at once
linear.start()
todoist.start(linear)
guard.bind(hyper, "E", function()
  linear.toggle()
  todoist.toggle()
end)

-- ─── Show Desktop ───────────────────────────────────────────────
-- C = toggle show desktop (minimize all / restore all)
local _minimizedWindows = {}
guard.bind(hyper, "C", function()
  if #_minimizedWindows > 0 then
    -- Restore previously minimized windows
    for _, w in ipairs(_minimizedWindows) do
      if w:isMinimized() then w:unminimize() end
    end
    _minimizedWindows = {}
  else
    -- Minimize all visible windows
    local wins = hs.window.orderedWindows()
    _minimizedWindows = wins
    for _, w in ipairs(wins) do w:minimize() end
  end
end)

-- ─── System Monitor ────────────────────────────────────────────
-- Menubar: RAM% | pomodoro | caffeine, click for processes + controls
sysmonitor.start()

-- ─── Ctrl-tap-as-Escape ────────────────────────────────────────
system.startCtrlEscape()

-- ─── Brightness on AC power ────────────────────────────────────
system.startPowerWatcher()

-- ─── Console & Reload ───────────────────────────────────────────
guard.bind(hyper, "H", hs.toggleConsole)
-- Reload is NOT guarded (always available even when disabled)
hs.hotkey.bind(hyper, "R", hs.reload)

-- ─── Shift+Backspace → Forward Delete ──────────────────────────
guard.addHotkey(hs.hotkey.bind({ "shift" }, "delete", function()
  hs.eventtap.keyStroke({}, "forwarddelete", 0)
end))

hs.alert.show("🔨 Hammerspoon loaded", 1.5)

-- ─── Command palette ────────────────────────────────────────────
-- ctrl+alt+shift+Space = every command there is, by category
-- ctrl+alt+shift+F     = click anything by keyboard
-- ctrl+alt+shift+H     = open any cheatsheet
local palette     = require("modules.palette")
local keyboard    = require("modules.keyboard")
local cheatsheets = require("modules.cheatsheets")
guard.bind({ "ctrl", "alt", "shift" }, "Space", palette.open)
guard.bind({ "ctrl", "alt", "shift" }, "F", keyboard.clickHints)
guard.bind({ "ctrl", "alt", "shift" }, "H", cheatsheets.show)

-- ctrl+alt+cmd+Space opens the palette too: it used to be the window jumper,
-- which the Windows tab (⌥3) now covers. Binding it last wins over the earlier
-- one, and the earlier one is disabled outright so nothing lingers.
for _, hk in ipairs(hs.hotkey.getHotkeys()) do
  if tostring(hk.msg or ""):find("⌘⌃⌥SPACE") and hk.disable then hk:disable() end
end
guard.bind({ "ctrl", "alt", "cmd" }, "Space", palette.open)
