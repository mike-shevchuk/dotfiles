-- Clipboard manager with history
local M = {}

local HISTORY_SIZE = 50
local IMAGE_LIMIT = 20
local IMAGE_DIR = os.getenv("HOME") .. "/.cache/hs/clip/"
local history = hs.settings.get("clipboard_history") or {}
-- copy times (s) parallel to history; legacy entries without one sort below images
local times = hs.settings.get("clipboard_history_t") or {}
local images = {} -- newest first: { path, t, w, h, thumb }
local lastChange = hs.pasteboard.changeCount()

local function loadImage(path, t)
  local img = hs.image.imageFromPath(path)
  if not img then return nil end
  local size = img:size()
  local h = 48
  local w = math.max(1, math.floor(size.w * h / math.max(size.h, 1)))
  return { path = path, t = t, w = size.w, h = size.h,
           thumb = img:bitmapRepresentation({ w = w, h = h }) }
end

local function trimImages()
  while #images > IMAGE_LIMIT do
    os.remove(table.remove(images).path)
  end
end

local function loadImages()
  os.execute("mkdir -p '" .. IMAGE_DIR .. "'")
  local files = {}
  for f in hs.fs.dir(IMAGE_DIR) do
    local ms = f:match("^(%d+)%.png$")
    if ms then files[#files + 1] = tonumber(ms) end
  end
  table.sort(files, function(a, b) return a > b end)
  for _, ms in ipairs(files) do
    local path = IMAGE_DIR .. ms .. ".png"
    if #images < IMAGE_LIMIT then
      images[#images + 1] = loadImage(path, ms / 1000)
    else
      os.remove(path)
    end
  end
end

local function addImage()
  -- hash the raw pasteboard bytes: re-encoded PNGs differ even for the same picture
  local data = hs.pasteboard.readDataForUTI(nil, "public.png")
    or hs.pasteboard.readDataForUTI(nil, "public.tiff")
  if not data then return false end
  local hash = hs.hash.MD5(data)
  data = nil
  if hash == hs.settings.get("clipboard_img_hash") then return false end
  local img = hs.pasteboard.readImage()
  if not img then return false end
  local now = hs.timer.secondsSinceEpoch()
  local path = IMAGE_DIR .. math.floor(now * 1000) .. ".png"
  if not img:saveToFile(path) then return false end
  hs.settings.set("clipboard_img_hash", hash)
  local item = loadImage(path, now)
  if item then
    table.insert(images, 1, item)
    trimImages()
  end
  return true
end

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
  local ti, ii = 1, 1
  -- merge two newest-first lists by time
  while history[ti] or images[ii] do
    local img = images[ii]
    if img and (not history[ti] or img.t > (times[ti] or 0)) then
      items[#items + 1] = {
        text = string.format("🖼 %dx%d · %s", img.w, img.h, os.date("%H:%M", math.floor(img.t))),
        subText = img.path,
        image = img.thumb,
        imagePath = img.path,
      }
      ii = ii + 1
    else
      local item = history[ti]
      items[#items + 1] = {
        text = formatItem(item),
        fullText = item,
        subText = string.format("#%d  (%d chars)", ti, #item),
      }
      ti = ti + 1
    end
  end
  if #items == 0 then
    items[#items + 1] = { text = "No clipboard history", unusable = true }
  end
  M.chooser:choices(items)
end

M.chooser = hs.chooser.new(function(choice)
  if not choice or choice.unusable then return end
  if choice.imagePath then
    local img = hs.image.imageFromPath(choice.imagePath)
    if not img then return end
    hs.pasteboard.writeObjects(img)
    lastChange = hs.pasteboard.changeCount() -- our own write: don't re-save it
    hs.alert.show("картинка в буфері — Ctrl+V", 1)
    return
  end
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
      if i <= #times then table.remove(times, i) end
      break
    end
  end
  table.insert(history, 1, text)
  table.insert(times, 1, hs.timer.secondsSinceEpoch())
  while #history > HISTORY_SIZE do
    table.remove(history)
  end
  while #times > #history do
    table.remove(times)
  end
  hs.settings.set("clipboard_history", history)
  hs.settings.set("clipboard_history_t", times)
  updateChooser()
end

function M.start()
  M.timer = hs.timer.doEvery(0.5, function()
    local count = hs.pasteboard.changeCount()
    if count ~= lastChange then
      lastChange = count
      local text = hs.pasteboard.getContents()
      if text and text ~= "" then
        addItem(text)
      else
        local types = hs.pasteboard.contentTypes() or {}
        for _, t in ipairs(types) do
          if t == "public.png" or t == "public.tiff" then
            if addImage() then updateChooser() end
            break
          end
        end
      end
    end
  end)
  loadImages()
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
  times = {}
  hs.settings.set("clipboard_history", history)
  hs.settings.set("clipboard_history_t", times)
  updateChooser()
  hs.alert.show("Clipboard history cleared", 1)
end

M.images = images

return M
