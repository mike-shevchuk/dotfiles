-- Audio device auto-switching
local M = {}

-- Priority lists: first match wins (highest priority)
-- Edit these to match your devices
M.output_priority = {
  "WH-1000XM3",
  "External Headphones",
  "CalDigit Thunderbolt 3 Audio",
  "MacBook Pro Speakers",
}

M.input_priority = {
  "ATR2100x-USB Microphone",
  "WH-1000XM3",
  "HD Pro Webcam C920",
  "MacBook Pro Microphone",
}

local function getPriority(device, priority_list)
  local name = device:name()
  for i, pname in ipairs(priority_list) do
    if name == pname then return i end
  end
  -- Built-in devices get a default low priority
  if device:transportType() == "Built-in" then
    return #priority_list + 1
  end
  return #priority_list + 2
end

local function selectBest(devices, priority_list, setCb)
  local best, bestPri = nil, math.huge
  for _, dev in ipairs(devices) do
    local pri = getPriority(dev, priority_list)
    if pri < bestPri then
      best, bestPri = dev, pri
    end
  end
  if best then setCb(best) end
end

function M.start()
  hs.audiodevice.watcher.setCallback(function(event)
    if event ~= "dev#" then return end

    selectBest(hs.audiodevice.allOutputDevices(), M.output_priority, function(dev)
      local current = hs.audiodevice.defaultOutputDevice()
      if current:name() ~= dev:name() then
        dev:setDefaultOutputDevice()
        hs.alert.show("🔊 " .. dev:name(), 1.5)
      end
    end)

    selectBest(hs.audiodevice.allInputDevices(), M.input_priority, function(dev)
      local current = hs.audiodevice.defaultInputDevice()
      if current:name() ~= dev:name() then
        dev:setDefaultInputDevice()
        hs.alert.show("🎤 " .. dev:name(), 1.5)
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
