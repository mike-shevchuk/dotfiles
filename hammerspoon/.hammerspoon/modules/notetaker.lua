-- Zettelkasten quick notetaker
-- 5 tabs: Daily, Weekly, Temp, B2B, Life
-- All files saved to ~/zettelkasten/comb-notes/
local M = {}

M.webview = nil
M.visible = false

local VAULT = os.getenv("HOME") .. "/zettelkasten"
local WIDTH = 560
local HEIGHT = 480

-- Tab definitions: id, label, directory, filename pattern, new file template
local TABS = {
  {
    id = "daily",
    label = "Daily",
    dir = VAULT .. "/comb-notes/daily_staff",
    filename = function() return os.date("%Y-%m-%d") .. ".md" end,
    template = function()
      return string.format("#daily #%s\n\n# %s\n\n",
        os.date("%Y-%m-%d"), os.date("%A, %B %d"))
    end,
  },
  {
    id = "weekly",
    label = "Weekly",
    dir = VAULT .. "/comb-notes/weekly_staff",
    filename = function() return os.date("%Y") .. "-W" .. os.date("%W") .. ".md" end,
    template = function()
      return string.format("#weekly #%s-W%s\n\n",
        os.date("%Y"), os.date("%W"))
    end,
  },
  {
    id = "temp",
    label = "Temp",
    dir = VAULT .. "/comb-notes/temp",
    filename = function() return os.date("%Y-%m-%d_%H") .. "h.md" end,
    template = function()
      return string.format("#temp #%s %s:00\n\n",
        os.date("%Y-%m-%d"), os.date("%H"))
    end,
  },
  {
    id = "b2b",
    label = "B2B",
    dir = VAULT .. "/comb-notes/daily_b2b",
    filename = function() return os.date("%Y-%m-%d") .. ".md" end,
    template = function()
      return string.format("#b2b #%s\n\n# B2B — %s\n\n",
        os.date("%Y-%m-%d"), os.date("%A, %B %d"))
    end,
  },
  {
    id = "life",
    label = "Life",
    dir = VAULT .. "/comb-notes/daily_life",
    filename = function() return os.date("%Y-%m-%d") .. ".md" end,
    template = function()
      return string.format("#life #%s\n\n# Life — %s\n\n",
        os.date("%Y-%m-%d"), os.date("%A, %B %d"))
    end,
  },
}

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return "" end
  local content = f:read("*a")
  f:close()
  return content
end

local function writeFile(path, content)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(content)
  f:close()
  return true
end

local function ensureDir(dir)
  hs.execute("mkdir -p '" .. dir .. "'")
end

local function escapeJS(s)
  return s:gsub("\\", "\\\\"):gsub("'", "\\'"):gsub("\n", "\\n"):gsub("\r", "")
end

local function buildHTML(tabData, todayDate, weekLabel)
  -- Build tab buttons
  local tabButtons = {}
  for i, t in ipairs(tabData) do
    local activeClass = i == 1 and " active" or ""
    tabButtons[#tabButtons + 1] = string.format(
      '<div class="tab%s" id="tab-%s" onclick="switchTab(\'%s\')">%s</div>',
      activeClass, t.id, t.id, t.label
    )
  end

  -- Build JS content object
  local contentParts = {}
  for _, t in ipairs(tabData) do
    contentParts[#contentParts + 1] = string.format("'%s': '%s'", t.id, escapeJS(t.content))
  end

  -- Build JS paths object
  local pathParts = {}
  for _, t in ipairs(tabData) do
    pathParts[#pathParts + 1] = string.format("'%s': '%s'", t.id, escapeJS(t.path))
  end

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
    display: flex;
    flex-direction: column;
  }
  .tabs {
    display: flex;
    background: #181825;
    border-bottom: 1px solid #45475a;
  }
  .tab {
    padding: 8px 14px;
    cursor: pointer;
    color: #6c7086;
    font-size: 12px;
    border-bottom: 2px solid transparent;
    user-select: none;
    transition: color 0.15s;
  }
  .tab.active {
    color: #fab387;
    border-bottom-color: #fab387;
  }
  .tab:hover { color: #cdd6f4; }
  .header {
    padding: 6px 12px;
    font-size: 11px;
    color: #6c7086;
    background: #181825;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .tag {
    background: #313244;
    color: #a6e3a1;
    padding: 2px 8px;
    border-radius: 3px;
    font-size: 10px;
  }
  .tags { display: flex; gap: 4px; }
  .filepath {
    font-size: 9px;
    color: #45475a;
    padding: 2px 12px;
    background: #181825;
    border-bottom: 1px solid #313244;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  #editor {
    flex: 1;
    width: 100%%;
    background: transparent;
    color: #cdd6f4;
    border: none;
    outline: none;
    padding: 10px 12px;
    font-family: SF Mono, Menlo, monospace;
    font-size: 13px;
    resize: none;
    line-height: 1.6;
  }
  #editor::placeholder { color: #585b70; }
  .statusbar {
    padding: 4px 12px;
    font-size: 10px;
    color: #585b70;
    background: #181825;
    border-top: 1px solid #45475a;
    display: flex;
    justify-content: space-between;
  }
  .btn {
    background: #313244;
    color: #cdd6f4;
    border: none;
    padding: 2px 10px;
    border-radius: 3px;
    cursor: pointer;
    font-size: 10px;
    font-family: inherit;
  }
  .btn:hover { background: #45475a; }
</style>
</head>
<body>
  <div class="tabs">
    %s
  </div>
  <div class="header">
    <span id="dateLabel">%s</span>
    <div class="tags">
      <span class="tag" id="tagDate">%s</span>
      <span class="tag" id="tagDay">%s</span>
    </div>
  </div>
  <div class="filepath" id="filepath"></div>
  <textarea id="editor" placeholder="Start writing..." autofocus></textarea>
  <div class="statusbar">
    <span id="status">Ready</span>
    <button class="btn" onclick="openInObsidian()">Open in Obsidian</button>
  </div>

  <script>
    let currentTab = '%s';
    let content = { %s };
    let paths = { %s };
    let dirty = false;

    const editor = document.getElementById('editor');
    const filepath = document.getElementById('filepath');
    editor.value = content[currentTab];
    filepath.textContent = paths[currentTab];

    function switchTab(tab) {
      content[currentTab] = editor.value;
      save(currentTab);
      currentTab = tab;
      editor.value = content[tab];
      filepath.textContent = paths[tab];

      document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
      document.getElementById('tab-' + tab).classList.add('active');

      let label = document.getElementById('dateLabel');
      if (tab === 'weekly') {
        label.textContent = '%s';
      } else {
        label.textContent = '%s';
      }
      editor.focus();
    }

    editor.addEventListener('input', function() {
      content[currentTab] = editor.value;
      dirty = true;
      document.getElementById('status').textContent = 'Editing...';
    });

    function save(tab) {
      tab = tab || currentTab;
      window.webkit.messageHandlers.note.postMessage(
        JSON.stringify({ tab: tab, content: content[tab], path: paths[tab] })
      );
      dirty = false;
      document.getElementById('status').textContent = 'Saved';
      setTimeout(() => {
        document.getElementById('status').textContent = 'Ready';
      }, 1500);
    }

    function openInObsidian() {
      save();
      window.webkit.messageHandlers.note.postMessage(
        JSON.stringify({ action: 'obsidian', path: paths[currentTab] })
      );
    }

    setInterval(function() { if (dirty) save(); }, 3000);

    document.addEventListener('keydown', function(e) {
      if ((e.metaKey || e.ctrlKey) && e.key === 's') {
        e.preventDefault();
        save();
      }
      // Cmd+1-5 to switch tabs
      if (e.metaKey && e.key >= '1' && e.key <= '5') {
        e.preventDefault();
        let tabs = %s;
        let idx = parseInt(e.key) - 1;
        if (idx < tabs.length) switchTab(tabs[idx]);
      }
    });
  </script>
</body>
</html>
  ]],
    table.concat(tabButtons, "\n    "),
    todayDate,
    os.date("%%Y-%%m-%%d"),
    os.date("%%A"),
    tabData[1].id,
    table.concat(contentParts, ", "),
    table.concat(pathParts, ", "),
    weekLabel,
    todayDate,
    "['" .. table.concat(
      (function()
        local ids = {}
        for _, t in ipairs(tabData) do ids[#ids+1] = t.id end
        return ids
      end)(), "','") .. "']"
  )
end

function M.toggle()
  if M.visible and M.webview then
    M.webview:delete()
    M.webview = nil
    M.visible = false
    return
  end

  -- Load content for each tab
  local tabData = {}
  for _, tab in ipairs(TABS) do
    ensureDir(tab.dir)
    local path = tab.dir .. "/" .. tab.filename()
    local content = readFile(path)
    if content == "" then
      content = tab.template()
    end
    tabData[#tabData + 1] = {
      id = tab.id,
      label = tab.label,
      content = content,
      path = path,
    }
  end

  local todayDate = os.date("%A, %B %d, %Y")
  local weekLabel = "Week " .. os.date("%W") .. ", " .. os.date("%Y")

  local screen = hs.screen.mainScreen():frame()
  local x = screen.x + (screen.w - WIDTH) / 2
  local y = screen.y + (screen.h - HEIGHT) / 2

  local uc = hs.webview.usercontent.new("note"):setCallback(function(msg)
    local ok, data = pcall(hs.json.decode, msg.body)
    if not ok or not data then return end

    if data.action == "obsidian" then
      -- Open file in Obsidian using vault URI
      local relPath = data.path:gsub(VAULT .. "/", "")
      local uri = string.format("obsidian://open?vault=zettelkasten&file=%s",
        hs.http.encodeForQuery(relPath))
      hs.urlevent.openURL(uri)
      return
    end

    if data.path and data.content then
      if writeFile(data.path, data.content) then
        print("Notetaker: saved " .. data.path)
      else
        print("Notetaker: FAILED to save " .. data.path)
      end
    end
  end)

  M.webview = hs.webview.new(
    { x = x, y = y, w = WIDTH, h = HEIGHT },
    { developerExtrasEnabled = false },
    uc
  )

  M.webview:windowStyle({ "titled", "closable", "resizable", "utility" })
  M.webview:level(hs.canvas.windowLevels.floating)
  M.webview:allowTextEntry(true)
  M.webview:html(buildHTML(tabData, todayDate, weekLabel))
  M.webview:show()
  M.visible = true
end

return M
