-- Clipboard manager with history
local M = {}

local HISTORY_SIZE = 50
local history = hs.settings.get("clipboard_history") or {}
local lastChange = hs.pasteboard.changeCount()

local function formatItem(text)
  if not text then return "" end
  local display = text:gsub("[\r\n]+", " "):gsub("%s+", " ")
  if #display > 100 then
    display = display:sub(1, 97) .. "..."
  end
  return display
end

local function updateChooser()
  local items = {}
  for i, item in ipairs(history) do
    items[#items + 1] = {
      text = formatItem(item),
      fullText = item,
      subText = string.format("#%d  (%d chars)", i, #item),
    }
  end
  if #items == 0 then
    items[#items + 1] = { text = "No clipboard history", unusable = true }
  end
  M.chooser:choices(items)
end

M.chooser = hs.chooser.new(function(choice)
  if not choice or choice.unusable then return end
  hs.pasteboard.setContents(choice.fullText)
  hs.timer.doAfter(0.1, function()
    hs.eventtap.keyStroke({ "cmd" }, "v")
  end)
end)

local function addItem(text)
  if not text or text:match("^%s*$") then return end
  -- Remove duplicate
  for i, existing in ipairs(history) do
    if existing == text then
      table.remove(history, i)
      break
    end
  end
  table.insert(history, 1, text)
  while #history > HISTORY_SIZE do
    table.remove(history)
  end
  hs.settings.set("clipboard_history", history)
  updateChooser()
end

function M.start()
  M.timer = hs.timer.doEvery(0.5, function()
    local count = hs.pasteboard.changeCount()
    if count ~= lastChange then
      lastChange = count
      local text = hs.pasteboard.getContents()
      if text and text ~= "" then addItem(text) end
    end
  end)
  updateChooser()
end

function M.toggle()
  if M.chooser:isVisible() then
    M.chooser:hide()
  else
    updateChooser()
    M.chooser:show()
  end
end

function M.clear()
  history = {}
  hs.settings.set("clipboard_history", history)
  updateChooser()
  hs.alert.show("Clipboard history cleared", 1)
end

return M
