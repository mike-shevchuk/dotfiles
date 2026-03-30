-- Command palette with fuzzy search
-- Categories: System, Hammerspoon, Tools, Display, Window, Shell
-- Type ">" prefix to run shell commands
local M = {}

M.chooser = nil

-- Shell command history (persisted)
local HISTORY_KEY = "launcher_shell_history"
local MAX_HISTORY = 30

local function getHistory()
  return hs.settings.get(HISTORY_KEY) or {}
end

local function addHistory(cmd)
  local history = getHistory()
  -- Remove duplicate
  for i, h in ipairs(history) do
    if h == cmd then table.remove(history, i); break end
  end
  table.insert(history, 1, cmd)
  while #history > MAX_HISTORY do table.remove(history) end
  hs.settings.set(HISTORY_KEY, history)
end

-- Run a shell command and show output
local function runShell(cmd)
  addHistory(cmd)
  local output, status, _, rc = hs.execute("/bin/zsh -l -c " .. hs.http.encodeForQuery(cmd) .. " 2>&1", true)

  -- Show result in a floating webview
  output = output or "(no output)"
  local escaped = output:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
  local statusColor = status and "#a6e3a1" or "#f38ba8"
  local statusText = status and "exit 0" or ("exit " .. tostring(rc))

  local html = string.format([[
<!DOCTYPE html>
<html><head><style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: SF Mono, Menlo, monospace; font-size: 12px; background: #1e1e2e; color: #cdd6f4; }
  .header { padding: 8px 12px; background: #181825; border-bottom: 1px solid #45475a; display: flex; justify-content: space-between; }
  .cmd { color: #89b4fa; }
  .status { color: %s; }
  pre { padding: 12px; white-space: pre-wrap; word-wrap: break-word; line-height: 1.5; max-height: calc(100vh - 35px); overflow-y: auto; }
</style></head><body>
  <div class="header">
    <span class="cmd">$ %s</span>
    <span class="status">%s</span>
  </div>
  <pre>%s</pre>
</body></html>
  ]], statusColor, cmd:gsub("<", "&lt;"), statusText, escaped)

  -- Calculate height based on output lines
  local lines = 1
  for _ in output:gmatch("\n") do lines = lines + 1 end
  local height = math.min(math.max(lines * 16 + 50, 120), 500)

  if M.outputView then M.outputView:delete() end
  local screen = hs.screen.mainScreen():frame()
  M.outputView = hs.webview.new(
    { x = screen.x + (screen.w - 600) / 2, y = screen.y + 80, w = 600, h = height },
    { developerExtrasEnabled = false }
  )
  M.outputView:windowStyle({ "titled", "closable", "resizable", "utility" })
  M.outputView:level(hs.canvas.windowLevels.floating)
  M.outputView:html(html)
  M.outputView:show()

  -- Reopen launcher after showing output
  hs.timer.doAfter(0.3, function() M.show() end)
end

local function getApps()
  local apps = {}
  local seen = {}
  local dirs = {
    "/Applications",
    "/System/Applications",
    "/System/Applications/Utilities",
    os.getenv("HOME") .. "/Applications",
    "/Applications/Utilities",
  }
  for _, dir in ipairs(dirs) do
    local output = hs.execute("ls '" .. dir .. "' 2>/dev/null")
    if output then
      for name in output:gmatch("[^\n]+") do
        if name:match("%.app$") then
          local appName = name:gsub("%.app$", "")
          if not seen[appName] then
            seen[appName] = true
            apps[#apps + 1] = {
              text = appName,
              subText = "App — " .. dir,
              path = dir .. "/" .. name,
              type = "app",
            }
          end
        end
      end
    end
  end
  table.sort(apps, function(a, b) return a.text < b.text end)
  return apps
end

M._commands = {}

local function buildCommands()
  local cmds = {
    -- System
    { text = "Lock Screen",            subText = "System", fn = function() hs.caffeinate.lockScreen() end },
    { text = "Sleep",                  subText = "System", fn = function() hs.caffeinate.systemSleep() end },
    { text = "Restart",                subText = "System", fn = function() hs.caffeinate.restartSystem() end },
    { text = "Dark Mode Toggle",       subText = "System", fn = function() hs.osascript.applescript('tell application "System Events" to tell appearance preferences to set dark mode to not dark mode') end },
    { text = "Empty Trash",            subText = "System", fn = function() hs.osascript.applescript('tell application "Finder" to empty trash'); hs.alert.show("Trash emptied", 1) end },

    -- Hammerspoon
    { text = "Reload Config",          subText = "Hammerspoon", fn = function() hs.reload() end },
    { text = "Open Console",           subText = "Hammerspoon", fn = function() hs.toggleConsole() end },
    { text = "Toggle Hammerspoon",     subText = "Hammerspoon", fn = function() require("modules.guard").toggle() end },

    -- Display
    { text = "Brightness Panel",       subText = "Display", fn = function() require("modules.brightness").toggle() end },
    { text = "Display Chooser",        subText = "Display", fn = function() require("modules.sidecar").showDisplayChooser() end },
    { text = "Mirror/Extend Toggle",   subText = "Display", fn = function() require("modules.sidecar").toggleMirror() end },

    -- Tools
    { text = "Clipboard History",      subText = "Tools", fn = function() require("modules.clipboard").toggle() end },
    { text = "Scratchpad",             subText = "Tools", fn = function() require("modules.scratchpad").toggle() end },
    { text = "Notetaker",              subText = "Tools — Zettelkasten", fn = function() require("modules.notetaker").toggle() end },
    { text = "Find Mouse",             subText = "Tools", fn = function() require("modules.mousefinder").find() end },
    { text = "Pomodoro Start/Stop",    subText = "Tools", fn = function() require("modules.pomodoro").toggle() end },
    { text = "Screenshot Annotate",    subText = "Tools", fn = function() require("modules.screenshot").capture() end },
    { text = "Bookmarks",             subText = "Tools", fn = function() require("modules.bookmarks").show() end },
    { text = "Linear Widget Toggle",  subText = "Linear", fn = function() require("modules.linear").toggle() end },

    -- Audio
    { text = "Mute/Unmute",            subText = "Audio", fn = function() require("modules.audio").toggleMute() end },

    -- Window
    { text = "Window Left Half",       subText = "Window", fn = function() require("modules.windows").move("left_half")() end },
    { text = "Window Right Half",      subText = "Window", fn = function() require("modules.windows").move("right_half")() end },
    { text = "Window Maximize",        subText = "Window", fn = function() require("modules.windows").maximize() end },
    { text = "Window Center",          subText = "Window", fn = function() require("modules.windows").center() end },
    { text = "Window Left Third",      subText = "Window", fn = function() require("modules.windows").move("left_third")() end },
    { text = "Window Right Third",     subText = "Window", fn = function() require("modules.windows").move("right_third")() end },
    { text = "Window Move Screen Left",  subText = "Window", fn = function() require("modules.windows").screenLeft() end },
    { text = "Window Move Screen Right", subText = "Window", fn = function() require("modules.windows").screenRight() end },

    -- Trackpad
    { text = "Pinch Zoom Toggle",      subText = "Trackpad", fn = function() require("modules.system").togglePinchZoom() end },

    -- Screenshot
    { text = "Screenshot Selection",   subText = "Screenshot", fn = function() hs.eventtap.keyStroke({"cmd","shift"}, "4") end },
    { text = "Screenshot Window",      subText = "Screenshot", fn = function() hs.eventtap.keyStroke({"cmd","shift"}, "4"); hs.timer.doAfter(0.3, function() hs.eventtap.keyStroke({}, "space") end) end },
    { text = "Screenshot Full Screen", subText = "Screenshot", fn = function() hs.eventtap.keyStroke({"cmd","shift"}, "3") end },
  }

  -- Shell quick commands
  local shellQuick = {
    { cmd = "top -l 1 | head -20",            label = "System Load (top)" },
    { cmd = "df -h",                          label = "Disk Usage" },
    { cmd = "ifconfig | grep 'inet '",        label = "IP Addresses" },
    { cmd = "networksetup -getairportnetwork en0", label = "WiFi Network" },
    { cmd = "pmset -g batt",                  label = "Battery Status" },
    { cmd = "ps aux | sort -rk 3 | head -10", label = "Top CPU Processes" },
    { cmd = "du -sh ~/Desktop ~/Downloads ~/Documents 2>/dev/null", label = "Folder Sizes" },
    { cmd = "brew update && brew upgrade",    label = "Brew Update All" },
    { cmd = "brew cleanup",                   label = "Brew Cleanup" },
    { cmd = "softwareupdate -l",              label = "Check macOS Updates" },
    { cmd = "networksetup -setairportpower en0 off && sleep 1 && networksetup -setairportpower en0 on", label = "Restart WiFi" },
    { cmd = "killall Finder",                 label = "Restart Finder" },
    { cmd = "killall Dock",                   label = "Restart Dock" },
    { cmd = "open .",                         label = "Open Current Dir in Finder" },
  }
  for _, sq in ipairs(shellQuick) do
    cmds[#cmds + 1] = {
      text = sq.label,
      subText = "Shell — " .. sq.cmd,
      fn = function() runShell(sq.cmd) end,
    }
  end

  -- Shell history
  local history = getHistory()
  for _, h in ipairs(history) do
    local short = #h > 60 and h:sub(1, 57) .. "..." or h
    cmds[#cmds + 1] = {
      text = "> " .. short,
      subText = "Shell History",
      fn = function() runShell(h) end,
    }
  end

  M._commands = cmds
  return cmds
end

-- Fuzzy match: each char in query must appear in order in target
-- Returns score (higher = better) or nil if no match
local function fuzzyScore(query, target)
  if query == "" then return 1 end
  local q = query:lower()
  local t = target:lower()
  local qi = 1
  local score = 0
  local prevMatch = false

  for ti = 1, #t do
    if qi <= #q and t:sub(ti, ti) == q:sub(qi, qi) then
      -- Bonus for consecutive matches
      if prevMatch then score = score + 5 end
      -- Bonus for match at start of word
      if ti == 1 or t:sub(ti - 1, ti - 1):match("[%s%-%_/]") then
        score = score + 10
      end
      -- Bonus for match at start of string
      if ti == qi then score = score + 3 end
      score = score + 1
      qi = qi + 1
      prevMatch = true
    else
      prevMatch = false
    end
  end

  if qi <= #q then return nil end -- not all chars matched
  return score
end

local function fuzzyMatch(query, item)
  local s1 = fuzzyScore(query, item.text or "")
  local s2 = fuzzyScore(query, item.subText or "")
  if s1 or s2 then
    return (s1 or 0) + (s2 or 0) * 0.5
  end
  return nil
end

-- Build all items (cached between shows)
M._allItems = nil

local function getAllItems()
  if M._allItems then return M._allItems end

  local items = {}

  -- Commands
  local cmds = buildCommands()
  for i, cmd in ipairs(cmds) do
    items[#items + 1] = {
      text = cmd.text,
      subText = cmd.subText,
      type = "cmd",
      cmdIdx = i,
    }
  end

  -- Apps
  for _, app in ipairs(getApps()) do
    items[#items + 1] = app
  end

  M._allItems = items
  return items
end

function M.show()
  -- Rebuild items each time (picks up new history)
  M._allItems = nil

  if not M.chooser then
    M.chooser = hs.chooser.new(function(choice)
      if not choice then return end
      if choice.type == "app" then
        hs.application.launchOrFocus(choice.path)
      elseif choice.type == "cmd" and choice.cmdIdx then
        local cmd = M._commands[choice.cmdIdx]
        if cmd and cmd.fn then cmd.fn() end
      elseif choice.type == "shell" then
        runShell(choice.shellCmd)
      end
    end)
    M.chooser:placeholderText("> shell cmd  |  search apps & commands")
    M.chooser:width(40)

    M.chooser:queryChangedCallback(function(query)
      if not query or query == "" then
        M.chooser:choices(getAllItems())
        return
      end

      -- Shell mode: ">" prefix
      if query:match("^>%s*") then
        local shellCmd = query:gsub("^>%s*", "")
        if shellCmd == "" then
          M.chooser:choices(getAllItems())
          return
        end

        local items = {
          {
            text = "Run: " .. shellCmd,
            subText = "Shell — press Enter to execute",
            type = "shell",
            shellCmd = shellCmd,
          },
        }
        -- Fuzzy match history
        local history = getHistory()
        for _, h in ipairs(history) do
          if fuzzyScore(shellCmd, h) then
            items[#items + 1] = {
              text = "> " .. h,
              subText = "Shell History",
              type = "shell",
              shellCmd = h,
            }
          end
        end
        M.chooser:choices(items)
        return
      end

      -- Fuzzy filter all items
      local scored = {}
      for _, item in ipairs(getAllItems()) do
        local score = fuzzyMatch(query, item)
        if score then
          scored[#scored + 1] = { item = item, score = score }
        end
      end

      -- Sort by score descending
      table.sort(scored, function(a, b) return a.score > b.score end)

      local results = {}
      for i, s in ipairs(scored) do
        if i > 30 then break end -- limit results
        results[#results + 1] = s.item
      end

      M.chooser:choices(results)
    end)
  end

  M.chooser:choices(getAllItems())
  M.chooser:show()
end

return M
