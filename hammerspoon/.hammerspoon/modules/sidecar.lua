-- Display management via displayplacer
local M = {}

-- Parse displayplacer list output into structured data
local function getDisplays()
  local output = hs.execute("/opt/homebrew/bin/displayplacer list 2>/dev/null")
  if not output then return {} end

  local displays = {}
  local current = nil

  for line in output:gmatch("[^\n]+") do
    local id = line:match("^Persistent screen id:%s*(.+)")
    if id then
      current = { id = id, modes = {} }
      displays[#displays + 1] = current
    elseif current then
      local k, v = line:match("^(%w[%w ]-): (.+)")
      if k then
        if k == "Type" then current.type = v
        elseif k == "Resolution" then current.resolution = v
        elseif k == "Hertz" then current.hertz = v
        elseif k == "Scaling" then current.scaling = v
        elseif k == "Origin" then
          current.origin = v
          current.isMain = v:match("main display") ~= nil
        end
      end
      -- Parse current mode marker
      if line:match("<%-%-") and line:match("current mode") then
        local mode = line:match("mode (%d+):")
        if mode then current.currentMode = mode end
      end
    end
  end

  -- Match with hs.screen names
  local screens = hs.screen.allScreens()
  for _, disp in ipairs(displays) do
    for _, scr in ipairs(screens) do
      if scr:getUUID() == disp.id then
        disp.name = scr:name()
        break
      end
    end
    if not disp.name then
      disp.name = disp.type or "Unknown"
    end
  end

  return displays
end

-- Get the best native mode for a display to be the primary/optimized one
local function getBestMode(displayId)
  local output = hs.execute("/opt/homebrew/bin/displayplacer list 2>/dev/null")
  if not output then return nil end

  -- Find this display's section and its current mode marker
  local inDisplay = false
  local currentMode = nil

  for line in output:gmatch("[^\n]+") do
    if line:match("^Persistent screen id:") then
      inDisplay = line:match(displayId) ~= nil
    end
    if inDisplay and line:match("<%-%-") and line:match("current mode") then
      currentMode = line:match("mode (%d+):")
    end
  end

  return currentMode
end

-- Apply: make a display the "optimized" one by setting it as main
local function optimizeFor(display)
  -- Build the displayplacer command
  -- Set the selected display as origin (0,0) = main display
  local displays = getDisplays()
  local args = {}

  for _, d in ipairs(displays) do
    if d.id == display.id then
      -- Selected display becomes main at (0,0)
      local res = d.resolution or "1920x1080"
      local hz = d.hertz or "60"
      local scaling = d.scaling or "off"
      args[#args + 1] = string.format(
        '"id:%s res:%s hz:%s color_depth:8 scaling:%s origin:(0,0)"',
        d.id, res, hz, scaling
      )
    else
      -- Other displays shift to the side
      local res = d.resolution or "1920x1080"
      local hz = d.hertz or "60"
      local scaling = d.scaling or "off"
      -- Put to the right of main
      local originX = 0
      if display.resolution then
        originX = tonumber(display.resolution:match("^(%d+)")) or 2560
      end
      args[#args + 1] = string.format(
        '"id:%s res:%s hz:%s color_depth:8 scaling:%s origin:(%d,0)"',
        d.id, res, hz, scaling, originX
      )
      originX = originX + (tonumber(res:match("^(%d+)")) or 1920)
    end
  end

  local cmd = "/opt/homebrew/bin/displayplacer " .. table.concat(args, " ")
  print("Running: " .. cmd)
  hs.execute(cmd)
  hs.alert.show("Main display: " .. display.name, 1.5)
end

-- ─── Display Chooser ───────────────────────────────────────────

M.displayChooser = hs.chooser.new(function(choice)
  if not choice or choice.unusable then return end

  local displays = getDisplays()
  for _, d in ipairs(displays) do
    if d.id == choice.displayId then
      optimizeFor(d)
      return
    end
  end
  hs.alert.show("Display not found", 1.5)
end)

function M.showDisplayChooser()
  local displays = getDisplays()
  local items = {}

  for _, d in ipairs(displays) do
    local main = d.isMain and " ★ main" or ""
    local sub = string.format("%s @ %sHz  scaling:%s%s",
      d.resolution or "?",
      d.hertz or "?",
      d.scaling or "?",
      main
    )
    items[#items + 1] = {
      text = d.name,
      subText = sub,
      displayId = d.id,
    }
    print(string.format("Display: %s — %s", d.name, sub))
  end

  if #items == 0 then
    items[#items + 1] = { text = "No displays found", unusable = true }
  end

  M.displayChooser:placeholderText("Set as main display…")
  M.displayChooser:choices(items)
  M.displayChooser:show()
end

-- ─── Mirror/Extend toggle ───────────────────────────────────────
function M.toggleMirror()
  hs.eventtap.keyStroke({ "fn", "cmd" }, "1", 0)
  hs.alert.show("Mirror/Extend toggled", 1)
end

return M
