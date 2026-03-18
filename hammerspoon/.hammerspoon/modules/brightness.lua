-- Brightness panel with per-monitor sliders
-- Uses m1ddc with display name matching (-m flag)
local M = {}

M.webview = nil
M.visible = false

local WIDTH = 340
local HEIGHT_PER_DISPLAY = 70
local HEADER_HEIGHT = 50
local M1DDC = "/opt/homebrew/bin/m1ddc"

-- Stored brightness for displays where DDC get doesn't work
M._stored = {}

local function ddcGet(name)
  local output = hs.execute(string.format('%s get luminance -m "%s" 2>/dev/null', M1DDC, name))
  local val = tonumber(output and output:match("^%-?%d+"))
  if val and val >= 0 then return val end
  return nil -- DDC get not supported
end

local function ddcSet(name, value)
  hs.execute(string.format('%s set luminance %d -m "%s" 2>/dev/null', M1DDC, value, name))
  M._stored[name] = value
end

local function getScreenData()
  local screens = hs.screen.allScreens()
  local data = {}

  for _, scr in ipairs(screens) do
    local name = scr:name()
    local b = scr:getBrightness() -- works for built-in
    local entry = {
      name = name,
      uuid = scr:getUUID(),
      brightness = nil,
      method = "none",
    }

    if b and b >= 0 then
      entry.brightness = math.floor(b * 100)
      entry.method = "native"
    else
      -- Try m1ddc
      local ddcVal = ddcGet(name)
      if ddcVal then
        entry.brightness = ddcVal
        entry.method = "ddc"
      elseif M._stored[name] then
        -- DDC get fails but set works (like T27QD-40)
        entry.brightness = M._stored[name]
        entry.method = "ddc"
      else
        -- Try a set/read test: set to current-ish value
        local testOut = hs.execute(string.format('%s set luminance 100 -m "%s" 2>/dev/null', M1DDC, name))
        local testVal = tonumber(testOut and testOut:match("^%-?%d+"))
        if testVal and testVal >= 0 then
          entry.brightness = testVal
          entry.method = "ddc"
          M._stored[name] = testVal
        end
      end
    end

    data[#data + 1] = entry
  end
  return data
end

local function buildHTML(screens)
  local sliders = {}
  for i, s in ipairs(screens) do
    local val = s.brightness or -1
    local disabled = val < 0
    local disabledAttr = disabled and 'disabled style="opacity:0.3"' or ""
    local valText = disabled and "N/A" or (val .. "%")
    sliders[#sliders + 1] = string.format([[
      <div class="display">
        <div class="label">
          <span class="name">%s</span>
          <span class="val" id="val_%d">%s</span>
        </div>
        <input type="range" min="0" max="100" value="%d" id="slider_%d"
          data-name="%s" data-method="%s" data-uuid="%s" %s
          oninput="update(%d, this.value)">
      </div>
    ]], s.name, i, valText,
        val < 0 and 50 or val, i,
        s.name, s.method, s.uuid, disabledAttr, i)
  end

  return string.format([[
<!DOCTYPE html>
<html>
<head>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: -apple-system, sans-serif;
    background: #1e1e2e;
    color: #cdd6f4;
    padding: 12px 16px;
    user-select: none;
  }
  h2 {
    font-size: 13px;
    color: #a6adc8;
    margin-bottom: 12px;
    font-weight: 500;
  }
  .display { margin-bottom: 14px; }
  .label {
    display: flex;
    justify-content: space-between;
    margin-bottom: 4px;
    font-size: 12px;
  }
  .name { color: #cdd6f4; }
  .val { color: #fab387; font-variant-numeric: tabular-nums; }
  input[type="range"] {
    -webkit-appearance: none;
    width: 100%%;
    height: 6px;
    border-radius: 3px;
    background: #45475a;
    outline: none;
  }
  input[type="range"]::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: 18px;
    height: 18px;
    border-radius: 50%%;
    background: #fab387;
    cursor: pointer;
  }
  input[type="range"]:disabled::-webkit-slider-thumb {
    background: #585b70;
    cursor: not-allowed;
  }
</style>
</head>
<body>
  <h2>Brightness</h2>
  %s
  <script>
    let debounce = {};
    function update(idx, val) {
      document.getElementById('val_' + idx).textContent = val + '%%';
      let slider = document.getElementById('slider_' + idx);
      clearTimeout(debounce[idx]);
      debounce[idx] = setTimeout(function() {
        window.webkit.messageHandlers.brightness.postMessage(
          JSON.stringify({
            name: slider.dataset.name,
            method: slider.dataset.method,
            uuid: slider.dataset.uuid,
            value: parseInt(val)
          })
        );
      }, 50);
    }
  </script>
</body>
</html>
  ]], table.concat(sliders, "\n"))
end

function M.toggle()
  if M.visible and M.webview then
    M.webview:delete()
    M.webview = nil
    M.visible = false
    return
  end

  local screens = getScreenData()
  local panelHeight = HEADER_HEIGHT + (#screens * HEIGHT_PER_DISPLAY)
  local mainScreen = hs.screen.mainScreen():frame()
  local x = mainScreen.x + (mainScreen.w - WIDTH) / 2
  local y = mainScreen.y + (mainScreen.h - panelHeight) / 2

  local uc = hs.webview.usercontent.new("brightness"):setCallback(function(msg)
    local ok, data = pcall(hs.json.decode, msg.body)
    if not ok or not data then return end

    if data.method == "ddc" then
      ddcSet(data.name, data.value)
    elseif data.method == "native" then
      for _, scr in ipairs(hs.screen.allScreens()) do
        if scr:getUUID() == data.uuid then
          scr:setBrightness(data.value / 100)
          break
        end
      end
    end
  end)

  M.webview = hs.webview.new(
    { x = x, y = y, w = WIDTH, h = panelHeight },
    { developerExtrasEnabled = false },
    uc
  )

  M.webview:windowStyle({ "titled", "closable", "utility" })
  M.webview:level(hs.canvas.windowLevels.floating)
  M.webview:allowTextEntry(true)
  M.webview:html(buildHTML(screens))
  M.webview:show()
  M.visible = true
end

return M
