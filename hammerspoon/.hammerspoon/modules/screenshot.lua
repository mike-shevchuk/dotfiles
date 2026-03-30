-- Screenshot + annotate
-- Takes area screenshot, opens annotation overlay
local M = {}

M.canvas = nil

function M.capture()
  -- Use macOS screenshot to capture area to clipboard
  local tmpfile = os.tmpname() .. ".png"
  local task = hs.task.new("/usr/sbin/screencapture", function(exitCode)
    if exitCode ~= 0 then return end

    -- Read the screenshot
    local img = hs.image.imageFromPath(tmpfile)
    if not img then
      os.remove(tmpfile)
      return
    end

    -- Copy to clipboard
    hs.pasteboard.writeObjects(img)

    -- Show annotation window
    M.annotate(img, tmpfile)
  end, { "-i", "-s", tmpfile })
  task:start()
end

function M.annotate(img, tmpfile)
  local imgSize = img:size()
  local screen = hs.screen.mainScreen():frame()

  -- Scale to fit screen if needed
  local scale = 1
  local maxW = screen.w * 0.8
  local maxH = screen.h * 0.8
  if imgSize.w > maxW then scale = maxW / imgSize.w end
  if imgSize.h * scale > maxH then scale = maxH / imgSize.h end

  local w = math.floor(imgSize.w * scale)
  local h = math.floor(imgSize.h * scale)
  local x = screen.x + (screen.w - w) / 2
  local y = screen.y + (screen.h - h - 60) / 2

  -- Encode image to base64 for HTML
  local imgData = img:encodeAsURLString()

  local html = string.format([[
<!DOCTYPE html>
<html>
<head>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { background: #1e1e2e; overflow: hidden; }
  .toolbar {
    display: flex;
    gap: 8px;
    padding: 8px 12px;
    background: #181825;
    border-bottom: 1px solid #45475a;
    align-items: center;
  }
  .btn {
    background: #313244;
    color: #cdd6f4;
    border: none;
    padding: 6px 12px;
    border-radius: 4px;
    cursor: pointer;
    font-size: 12px;
    font-family: -apple-system, sans-serif;
  }
  .btn:hover { background: #45475a; }
  .btn.active { background: #fab387; color: #1e1e2e; }
  .btn.primary { background: #a6e3a1; color: #1e1e2e; }
  .spacer { flex: 1; }
  canvas {
    display: block;
    cursor: crosshair;
  }
  .color-btn {
    width: 20px; height: 20px;
    border-radius: 50%%;
    border: 2px solid transparent;
    cursor: pointer;
  }
  .color-btn.active { border-color: white; }
</style>
</head>
<body>
  <div class="toolbar">
    <button class="btn active" id="btn-arrow" onclick="setTool('arrow')">Arrow</button>
    <button class="btn" id="btn-rect" onclick="setTool('rect')">Rect</button>
    <button class="btn" id="btn-pen" onclick="setTool('pen')">Pen</button>
    <button class="btn" id="btn-text" onclick="setTool('text')">Text</button>
    <span style="color:#45475a">|</span>
    <button class="color-btn active" id="c-red" style="background:#f38ba8" onclick="setColor('#f38ba8')"></button>
    <button class="color-btn" id="c-yellow" style="background:#f9e2af" onclick="setColor('#f9e2af')"></button>
    <button class="color-btn" id="c-green" style="background:#a6e3a1" onclick="setColor('#a6e3a1')"></button>
    <button class="color-btn" id="c-blue" style="background:#89b4fa" onclick="setColor('#89b4fa')"></button>
    <div class="spacer"></div>
    <button class="btn" onclick="undo()">Undo</button>
    <button class="btn primary" onclick="copyResult()">Copy</button>
    <button class="btn" onclick="saveResult()">Save</button>
  </div>
  <canvas id="canvas"></canvas>

  <script>
    const canvas = document.getElementById('canvas');
    const ctx = canvas.getContext('2d');
    const img = new Image();
    let tool = 'arrow';
    let color = '#f38ba8';
    let drawing = false;
    let startX, startY;
    let actions = [];
    let currentPath = [];

    img.onload = function() {
      canvas.width = img.width;
      canvas.height = img.height;
      canvas.style.width = '%dpx';
      canvas.style.height = '%dpx';
      redraw();
    };
    img.src = '%s';

    function setTool(t) {
      tool = t;
      document.querySelectorAll('.toolbar .btn').forEach(b => b.classList.remove('active'));
      document.getElementById('btn-' + t).classList.add('active');
    }

    function setColor(c) {
      color = c;
      document.querySelectorAll('.color-btn').forEach(b => b.classList.remove('active'));
      event.target.classList.add('active');
    }

    function redraw() {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.drawImage(img, 0, 0);
      actions.forEach(a => drawAction(a));
    }

    function drawAction(a) {
      ctx.strokeStyle = a.color;
      ctx.fillStyle = a.color;
      ctx.lineWidth = 3;

      if (a.type === 'arrow') {
        ctx.beginPath();
        ctx.moveTo(a.x1, a.y1);
        ctx.lineTo(a.x2, a.y2);
        ctx.stroke();
        // arrowhead
        let angle = Math.atan2(a.y2 - a.y1, a.x2 - a.x1);
        ctx.beginPath();
        ctx.moveTo(a.x2, a.y2);
        ctx.lineTo(a.x2 - 15*Math.cos(angle-0.4), a.y2 - 15*Math.sin(angle-0.4));
        ctx.lineTo(a.x2 - 15*Math.cos(angle+0.4), a.y2 - 15*Math.sin(angle+0.4));
        ctx.closePath();
        ctx.fill();
      } else if (a.type === 'rect') {
        ctx.strokeRect(a.x1, a.y1, a.x2-a.x1, a.y2-a.y1);
      } else if (a.type === 'pen') {
        if (a.points.length < 2) return;
        ctx.beginPath();
        ctx.moveTo(a.points[0].x, a.points[0].y);
        a.points.forEach(p => ctx.lineTo(p.x, p.y));
        ctx.stroke();
      } else if (a.type === 'text') {
        ctx.font = 'bold 18px -apple-system, sans-serif';
        ctx.fillText(a.text, a.x1, a.y1);
      }
    }

    function getPos(e) {
      let rect = canvas.getBoundingClientRect();
      let scaleX = canvas.width / rect.width;
      let scaleY = canvas.height / rect.height;
      return { x: (e.clientX - rect.left) * scaleX, y: (e.clientY - rect.top) * scaleY };
    }

    canvas.addEventListener('mousedown', function(e) {
      let p = getPos(e);
      startX = p.x; startY = p.y;
      drawing = true;
      if (tool === 'pen') currentPath = [{ x: p.x, y: p.y }];
      if (tool === 'text') {
        let text = prompt('Text:');
        if (text) {
          actions.push({ type: 'text', x1: p.x, y1: p.y, text: text, color: color });
          redraw();
        }
        drawing = false;
      }
    });

    canvas.addEventListener('mousemove', function(e) {
      if (!drawing) return;
      let p = getPos(e);
      if (tool === 'pen') {
        currentPath.push({ x: p.x, y: p.y });
        redraw();
        ctx.strokeStyle = color;
        ctx.lineWidth = 3;
        ctx.beginPath();
        ctx.moveTo(currentPath[0].x, currentPath[0].y);
        currentPath.forEach(pt => ctx.lineTo(pt.x, pt.y));
        ctx.stroke();
      } else if (tool === 'arrow' || tool === 'rect') {
        redraw();
        drawAction({ type: tool, x1: startX, y1: startY, x2: p.x, y2: p.y, color: color });
      }
    });

    canvas.addEventListener('mouseup', function(e) {
      if (!drawing) return;
      drawing = false;
      let p = getPos(e);
      if (tool === 'pen') {
        actions.push({ type: 'pen', points: currentPath, color: color });
      } else if (tool === 'arrow' || tool === 'rect') {
        actions.push({ type: tool, x1: startX, y1: startY, x2: p.x, y2: p.y, color: color });
      }
      redraw();
    });

    function undo() {
      actions.pop();
      redraw();
    }

    function copyResult() {
      canvas.toBlob(function(blob) {
        // Send base64 to Hammerspoon
        let reader = new FileReader();
        reader.onload = function() {
          window.webkit.messageHandlers.screenshot.postMessage(
            JSON.stringify({ action: 'copy', data: reader.result })
          );
        };
        reader.readAsDataURL(blob);
      });
    }

    function saveResult() {
      canvas.toBlob(function(blob) {
        let reader = new FileReader();
        reader.onload = function() {
          window.webkit.messageHandlers.screenshot.postMessage(
            JSON.stringify({ action: 'save', data: reader.result })
          );
        };
        reader.readAsDataURL(blob);
      });
    }

    document.addEventListener('keydown', function(e) {
      if ((e.metaKey || e.ctrlKey) && e.key === 'z') { e.preventDefault(); undo(); }
      if ((e.metaKey || e.ctrlKey) && e.key === 'c') { e.preventDefault(); copyResult(); }
      if (e.key === 'Escape') {
        window.webkit.messageHandlers.screenshot.postMessage(JSON.stringify({ action: 'close' }));
      }
    });
  </script>
</body>
</html>
  ]], w, h, imgData)

  if M.webview then M.webview:delete() end

  M.webview = hs.webview.new(
    { x = x, y = y, w = w, h = h + 44 },
    { developerExtrasEnabled = false },
    hs.webview.usercontent.new("screenshot"):setCallback(function(msg)
      local ok, data = pcall(hs.json.decode, msg.body)
      if not ok or not data then return end

      if data.action == "close" then
        if M.webview then M.webview:delete(); M.webview = nil end
        os.remove(tmpfile)
      elseif data.action == "copy" or data.action == "save" then
        -- Extract base64 data
        local b64 = data.data:match(",(.+)$")
        if b64 then
          local decoded = hs.base64.decode(b64)
          local resultImg = hs.image.imageFromASCII(decoded)

          -- Write to temp file and load as image
          local outfile = os.tmpname() .. ".png"
          local f = io.open(outfile, "wb")
          if f then
            f:write(decoded)
            f:close()
            local finalImg = hs.image.imageFromPath(outfile)
            if finalImg then
              hs.pasteboard.writeObjects(finalImg)
              hs.alert.show("Copied to clipboard", 1.5)
            end

            if data.action == "save" then
              local savePath = os.getenv("HOME") .. "/Desktop/screenshot_" .. os.date("%Y%m%d_%H%M%S") .. ".png"
              hs.execute("cp '" .. outfile .. "' '" .. savePath .. "'")
              hs.alert.show("Saved to Desktop", 1.5)
            end
            os.remove(outfile)
          end
        end

        if M.webview then M.webview:delete(); M.webview = nil end
        os.remove(tmpfile)
      end
    end)
  )

  M.webview:windowStyle({ "titled", "closable", "resizable", "utility" })
  M.webview:level(hs.canvas.windowLevels.floating)
  M.webview:allowTextEntry(true)
  M.webview:html(html)
  M.webview:show()
end

return M
