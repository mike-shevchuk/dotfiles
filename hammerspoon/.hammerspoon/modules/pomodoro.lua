-- Pomodoro timer in menubar
local M = {}

M.menubar = nil
M.timer = nil
M.remaining = 0  -- seconds
M.state = "idle" -- idle, work, break
M.sessions = 0   -- completed work sessions today
M.onUpdate = nil  -- external callback for menubar updates

local WORK_MIN = 25
local BREAK_MIN = 5
local LONG_BREAK_MIN = 15

local function formatTime(secs)
  local m = math.floor(secs / 60)
  local s = secs % 60
  return string.format("%02d:%02d", m, s)
end

local function updateMenubar()
  if M.menubar then
    if M.state == "idle" then
      M.menubar:setTitle("🍅 " .. M.sessions)
    elseif M.state == "work" then
      M.menubar:setTitle("🍅 " .. formatTime(M.remaining))
    elseif M.state == "break" then
      M.menubar:setTitle("☕ " .. formatTime(M.remaining))
    end
  end
  if M.onUpdate then M.onUpdate() end
end

local function tick()
  M.remaining = M.remaining - 1
  updateMenubar()

  if M.remaining <= 0 then
    if M.timer then M.timer:stop(); M.timer = nil end

    if M.state == "work" then
      M.sessions = M.sessions + 1
      hs.alert.show("🍅 Work done! Take a break (" .. M.sessions .. " sessions)", 3)
      -- Auto-start break
      local breakMin = (M.sessions % 4 == 0) and LONG_BREAK_MIN or BREAK_MIN
      M.state = "break"
      M.remaining = breakMin * 60
      M.timer = hs.timer.doEvery(1, tick)
      updateMenubar()

      -- Sound notification
      hs.sound.getByName("Glass"):play()
    elseif M.state == "break" then
      M.state = "idle"
      updateMenubar()
      hs.alert.show("☕ Break over! Ready for next session", 3)
      hs.sound.getByName("Purr"):play()
    end
  end
end

local function startWork()
  M.state = "work"
  M.remaining = WORK_MIN * 60
  if M.timer then M.timer:stop() end
  M.timer = hs.timer.doEvery(1, tick)
  updateMenubar()
  hs.alert.show("🍅 Focus time!", 1.5)
end

local function stopTimer()
  if M.timer then M.timer:stop(); M.timer = nil end
  M.state = "idle"
  M.remaining = 0
  updateMenubar()
  hs.alert.show("Pomodoro stopped", 1)
end

local function buildMenu()
  local items = {}

  if M.state == "idle" then
    items[#items + 1] = {
      title = "Start Work (25 min)",
      fn = startWork,
    }
  else
    items[#items + 1] = {
      title = "Stop",
      fn = stopTimer,
    }
    if M.state == "work" then
      items[#items + 1] = {
        title = "Skip to Break",
        fn = function()
          M.remaining = 0
          tick()
        end,
      }
    elseif M.state == "break" then
      items[#items + 1] = {
        title = "Skip Break",
        fn = function()
          if M.timer then M.timer:stop(); M.timer = nil end
          M.state = "idle"
          updateMenubar()
          hs.alert.show("Break skipped", 1)
        end,
      }
    end
  end

  items[#items + 1] = { title = "-" }
  items[#items + 1] = {
    title = "Sessions today: " .. M.sessions,
    disabled = true,
  }
  items[#items + 1] = {
    title = "Reset count",
    fn = function()
      M.sessions = 0
      updateMenubar()
    end,
  }

  return items
end

function M.start(skipMenubar)
  if not skipMenubar then
    M.menubar = hs.menubar.new()
    if not M.menubar then return end
    M.menubar:setMenu(buildMenu)
  end
  updateMenubar()
end

function M.getTitle()
  if M.state == "work" then
    return "🍅 " .. formatTime(M.remaining)
  elseif M.state == "break" then
    return "☕ " .. formatTime(M.remaining)
  elseif M.sessions > 0 then
    return "🍅 " .. M.sessions
  end
  return nil
end

function M.getMenuItems()
  return buildMenu()
end

-- Hotkey: start/stop toggle
function M.toggle()
  if M.state == "idle" then
    startWork()
  else
    stopTimer()
  end
end

return M
