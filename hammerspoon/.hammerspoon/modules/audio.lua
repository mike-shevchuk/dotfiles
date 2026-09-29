-- Audio device auto-switching
local M = {}

-- Priority lists: first match wins (highest priority)
-- Each entry: { name = "system device name", label = "display label" }
M.output_priority = {
  { name = "WH-1000XM3",                  label = "Sony XM3"   },
  { name = "External Headphones",         label = "Headphones" },
  { name = "CalDigit Thunderbolt 3 Audio",label = "CalDigit"   },
  { name = "MacBook Pro Speakers",        label = "Built-in"   },
}

M.input_priority = {
  { name = "ATR2100x-USB Microphone",     label = "ATR2100x"   },
  { name = "WH-1000XM3",                  label = "Sony XM3"   },
  { name = "HD Pro Webcam C920",          label = "Webcam Mic" },
  { name = "MacBook Pro Microphone",      label = "Built-in"   },
}

local function entryName(e)  return type(e) == "table" and e.name  or e end
local function entryLabel(e) return type(e) == "table" and e.label or entryName(e) end

local function getPriority(device, list)
  local name = device:name()
  for i, entry in ipairs(list) do
    if name == entryName(entry) then return i end
  end
  if device:transportType() == "Built-in" then return #list + 1 end
  return #list + 2
end

local function getLabel(device, list)
  local name = device:name()
  for _, entry in ipairs(list) do
    if name == entryName(entry) then return entryLabel(entry) end
  end
  return name
end

local function selectBest(devices, list, cb)
  local best, bestPri = nil, math.huge
  for _, dev in ipairs(devices) do
    local pri = getPriority(dev, list)
    if pri < bestPri then best, bestPri = dev, pri end
  end
  if best then cb(best) end
end

function M.stop()
  hs.audiodevice.watcher.stop()
  hs.audiodevice.watcher.setCallback(nil)
end

function M.start()
  M.stop()  -- clear any stale watcher before (re)starting

  hs.audiodevice.watcher.setCallback(function(event)
    if event ~= "dev#" then return end

    selectBest(hs.audiodevice.allOutputDevices(), M.output_priority, function(dev)
      local current = hs.audiodevice.defaultOutputDevice()
      if current:name() ~= dev:name() then
        dev:setDefaultOutputDevice()
        hs.alert.show("🔊 " .. getLabel(dev, M.output_priority), 1.5)
      end
    end)

    selectBest(hs.audiodevice.allInputDevices(), M.input_priority, function(dev)
      local current = hs.audiodevice.defaultInputDevice()
      if current:name() ~= dev:name() then
        dev:setDefaultInputDevice()
        hs.alert.show("🎤 " .. getLabel(dev, M.input_priority), 1.5)
      end
    end)
  end)

  hs.audiodevice.watcher.start()
end

function M.toggleMute()
  local dev = hs.audiodevice.defaultOutputDevice()
  if not dev then return end
  local muted = dev:mute()
  dev:setMute(not muted)
  hs.alert.show(not muted and "🔇 Muted" or "🔊 Unmuted", 1)
end

return M
