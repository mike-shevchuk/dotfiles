-- Jump straight to a window by name.
-- With six-plus windows on the strip, walking there one arrow at a time is the
-- slow part. Type a few letters instead. For a browser the window title IS the
-- tab title, so this doubles as a tab switcher across every open browser window.
local M = {}

local paperwm = require("modules.paperwm")

M.chooser = nil

local function label(win)
  local title = win:title() or ""
  local app = win:application()
  local appName = app and app:name() or "?"
  if title == "" then title = appName end
  return appName, title
end

-- where the window sits, so identical titles stay tellable apart
local function whereIs(win, currentSpace)
  local pwm = paperwm.pwm
  if not pwm then return "" end
  if pwm.floating.isFloating(win) then return "floating" end
  local idx = pwm.state.windowIndex(win)
  if not idx then return "not tiled" end
  if idx.space == currentSpace then
    return string.format("column %d", idx.col)
  end
  return string.format("space %d · column %d", idx.space, idx.col)
end

local function buildChoices()
  local pwm = paperwm.pwm
  if not pwm then return {} end

  local currentSpace = hs.spaces.focusedSpace()
  local choices = {}

  for _, win in ipairs(pwm.window_filter:getWindows()) do
    local appName, title = label(win)
    local app = win:application()
    local bundle = app and app:bundleID()
    choices[#choices + 1] = {
      text = title,
      subText = appName .. "  ·  " .. whereIs(win, currentSpace),
      image = bundle and hs.image.imageFromAppBundle(bundle) or nil,
      id = win:id(),
      -- windows on this space first, then in strip order
      sortKey = (function()
        local idx = pwm.state.windowIndex(win)
        if idx and idx.space == currentSpace then return idx.col end
        if idx then return 1000 + idx.space * 100 + idx.col end
        return 2000
      end)(),
    }
  end

  table.sort(choices, function(a, b) return a.sortKey < b.sortKey end)
  return choices
end

function M.show()
  if M.chooser and M.chooser:isVisible() then
    M.chooser:hide()
    return
  end

  if not M.chooser then
    M.chooser = hs.chooser.new(function(choice)
      if not choice then return end
      local win = hs.window.get(choice.id)
      if win then win:focus() end
    end)
    M.chooser:placeholderText("jump to window — app or tab name")
    M.chooser:width(40)
    M.chooser:searchSubText(true)
  end

  M.chooser:choices(buildChoices())
  M.chooser:query(nil)
  M.chooser:show()
end

return M
