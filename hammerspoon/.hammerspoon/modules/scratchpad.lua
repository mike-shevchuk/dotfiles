-- Floating scratchpad that persists across reloads
local M = {}

local SETTINGS_KEY = "scratchpad_text"
local WIDTH = 400
local HEIGHT = 300

M.visible = false
M.webview = nil

local function getHTML(text)
  text = text or ""
  -- Escape for JS
  local escaped = text:gsub("\\", "\\\\"):gsub("'", "\\'"):gsub("\n", "\\n"):gsub("\r", "")
  return string.format([[
<!DOCTYPE html>
<html>
<head>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: -apple-system, SF Mono, Menlo, monospace;
    font-size: 13px;
    background: #1e1e2e;
    color: #cdd6f4;
    height: 100vh;
  }
  #title {
    background: #313244;
    padding: 6px 12px;
    font-size: 11px;
    color: #a6adc8;
    user-select: none;
    cursor: grab;
    border-bottom: 1px solid #45475a;
  }
  #editor {
    width: 100%%;
    height: calc(100vh - 30px);
    background: transparent;
    color: #cdd6f4;
    border: none;
    outline: none;
    padding: 10px 12px;
    font-family: SF Mono, Menlo, monospace;
    font-size: 13px;
    resize: none;
    line-height: 1.5;
  }
  #editor::placeholder { color: #585b70; }
</style>
</head>
<body>
  <div id="title">Scratchpad — alt+shift+J to toggle</div>
  <textarea id="editor" placeholder="Type anything... saves automatically" autofocus></textarea>
  <script>
    const editor = document.getElementById('editor');
    editor.value = '%s';
    editor.addEventListener('input', function() {
      window.webkit.messageHandlers.save.postMessage(editor.value);
    });
  </script>
</body>
</html>
  ]], escaped)
end

function M.toggle()
  if M.visible and M.webview then
    M.webview:delete()
    M.webview = nil
    M.visible = false
    return
  end

  local text = hs.settings.get(SETTINGS_KEY) or ""
  local screen = hs.screen.mainScreen():frame()
  local x = screen.x + screen.w - WIDTH - 20
  local y = screen.y + 60

  M.webview = hs.webview.new(
    { x = x, y = y, w = WIDTH, h = HEIGHT },
    { developerExtrasEnabled = false },
    hs.webview.usercontent.new("save"):setCallback(function(msg)
      hs.settings.set(SETTINGS_KEY, msg.body)
    end)
  )

  M.webview:windowStyle({ "titled", "closable", "resizable", "utility" })
  M.webview:level(hs.canvas.windowLevels.floating)
  M.webview:allowTextEntry(true)
  M.webview:html(getHTML(text))
  M.webview:show()
  M.visible = true
end

return M
