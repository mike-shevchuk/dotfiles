-- Todoist desktop widget with menubar toggle
-- Shows today's tasks from Back2Back project, auto-refreshes
-- Menubar dropdown controls both Linear and Todoist widgets
local M = {}

local env = require("modules.env")
local API_URL = "https://api.todoist.com/api/v1/tasks"
local PROJECT_ID = "6cf7g4H5532pQmW3" -- Back2Back
local DOOING_SECTION = "6cf7g6cWMX2c3qpV"
local REFRESH_MIN = 3

local function getToken()
  local token = env.get("TODOIST_TOKEN")
  if not token then
    hs.alert.show("Todoist: add TODOIST_TOKEN to ~/.hammerspoon/.env", 5)
  end
  return token
end

M.webview = nil
M.timer = nil
M.menubar = nil
M.tasks = {}
M.linearModule = nil -- set via start()

local WIDTH = 340
local MAX_HEIGHT = 500
local MARGIN = 16

local function fetchTasks(callback)
  local token = getToken()
  if not token then callback(nil); return end

  local headers = {
    ["Authorization"] = "Bearer " .. token,
  }
  local url = API_URL .. "?project_id=" .. PROJECT_ID

  hs.http.asyncGet(url, headers, function(status, response)
    if status ~= 200 then
      print("Todoist API error: " .. tostring(status))
      callback(nil)
      return
    end

    local ok, data = pcall(hs.json.decode, response)
    if not ok or not data then
      print("Todoist JSON parse error")
      callback(nil)
      return
    end

    local results = data and data.results
    if results then
      -- Filter: today label OR Dooing section, only PUN tasks or tasks with sprint label
      local filtered = {}
      for _, task in ipairs(results) do
        local labels = task.labels or {}
        local hasToday = false
        local hasSprint = false
        for _, l in ipairs(labels) do
          if l == "today" then hasToday = true end
          if l == "sprint" then hasSprint = true end
        end
        local isDooing = task.section_id == DOOING_SECTION
        if hasToday or isDooing or hasSprint then
          filtered[#filtered + 1] = task
        end
      end
      callback(filtered)
    else
      print("Todoist: no results in response")
      callback({})
    end
  end)
end

local function priorityIcon(p)
  -- Todoist: 4=urgent, 3=high, 2=medium, 1=normal
  if p == 4 then return "🔴"
  elseif p == 3 then return "🟠"
  elseif p == 2 then return "🟡"
  else return "⚪" end
end

local function labelBadges(labels)
  local badges = {}
  for _, l in ipairs(labels or {}) do
    if l == "today" then badges[#badges + 1] = '<span class="label today">today</span>'
    elseif l == "tomorrow" then badges[#badges + 1] = '<span class="label tomorrow">tomorrow</span>'
    elseif l == "bug" then badges[#badges + 1] = '<span class="label bug">bug</span>'
    elseif l == "feature" then badges[#badges + 1] = '<span class="label feature">feature</span>'
    end
  end
  return table.concat(badges, " ")
end

local function buildHTML(tasks, lastUpdated)
  -- Group: Dooing first, then sprint/today
  local dooing = {}
  local todo = {}

  for _, task in ipairs(tasks) do
    if task.section_id == DOOING_SECTION then
      dooing[#dooing + 1] = task
    else
      todo[#todo + 1] = task
    end
  end

  local function renderTasks(items)
    local rows = {}
    for _, task in ipairs(items) do
      local pIcon = priorityIcon(task.priority or 1)
      local content = task.content or ""
      -- Extract PUN-XXXX if present
      local pun = content:match("PUN%-(%d+)")
      local punTag = pun and string.format('<span class="pun">PUN-%s</span>', pun) or ""
      -- Clean title: remove PUN-XXXX: prefix
      local title = content:gsub("^PUN%-%d+:%s*", "")
      if #title > 50 then title = title:sub(1, 47) .. "..." end
      local escapedTitle = title:gsub('"', '&quot;'):gsub("'", "&#39;"):gsub("<", "&lt;")

      local badges = labelBadges(task.labels)

      -- Extract estimate from description
      local estimate = ""
      local desc = task.description or ""
      local est = desc:match("~(%d+h)")
      if est then estimate = string.format('<span class="estimate">~%s</span>', est) end

      rows[#rows + 1] = string.format([[
        <div class="task" title="%s">
          <span class="prio">%s</span>
          %s
          <span class="title">%s</span>
          %s
          %s
        </div>
      ]], escapedTitle, pIcon, punTag, escapedTitle, estimate, badges)
    end
    return table.concat(rows, "\n")
  end

  local sections = {}
  if #dooing > 0 then
    sections[#sections + 1] = string.format([[
      <div class="group">
        <div class="state">Dooing <span class="count">%d</span></div>
        %s
      </div>
    ]], #dooing, renderTasks(dooing))
  end
  if #todo > 0 then
    sections[#sections + 1] = string.format([[
      <div class="group">
        <div class="state">Sprint <span class="count">%d</span></div>
        %s
      </div>
    ]], #todo, renderTasks(todo))
  end

  return string.format([[
<!DOCTYPE html>
<html>
<head>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: -apple-system, sans-serif;
    font-size: 12px;
    background: rgba(30, 30, 46, 0.92);
    color: #cdd6f4;
    padding: 12px;
    -webkit-backdrop-filter: blur(20px);
    user-select: none;
    cursor: default;
  }
  .header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 10px;
    padding-bottom: 8px;
    border-bottom: 1px solid #45475a;
  }
  .header h2 {
    font-size: 13px;
    font-weight: 600;
    color: #cdd6f4;
  }
  .badge {
    background: #5b6078;
    color: #cdd6f4;
    padding: 2px 8px;
    border-radius: 10px;
    font-size: 11px;
  }
  .group { margin-bottom: 10px; }
  .state {
    font-size: 10px;
    font-weight: 600;
    color: #a6adc8;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    margin-bottom: 4px;
    padding: 2px 0;
  }
  .count {
    color: #6c7086;
    font-weight: normal;
  }
  .task {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 5px 6px;
    border-radius: 4px;
    cursor: default;
    transition: background 0.15s;
    flex-wrap: wrap;
  }
  .task:hover { background: rgba(69, 71, 90, 0.6); }
  .prio { font-size: 10px; flex-shrink: 0; }
  .pun {
    color: #89b4fa;
    font-size: 10px;
    font-family: SF Mono, Menlo, monospace;
    flex-shrink: 0;
  }
  .title {
    color: #cdd6f4;
    font-size: 11px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    flex: 1;
  }
  .estimate {
    color: #a6e3a1;
    font-size: 9px;
    font-family: SF Mono, Menlo, monospace;
    flex-shrink: 0;
  }
  .label {
    font-size: 8px;
    padding: 1px 5px;
    border-radius: 6px;
    font-weight: 500;
    flex-shrink: 0;
  }
  .label.today { background: #a6e3a1; color: #1e1e2e; }
  .label.tomorrow { background: #89b4fa; color: #1e1e2e; }
  .label.bug { background: #f38ba8; color: #1e1e2e; }
  .label.feature { background: #cba6f7; color: #1e1e2e; }
  .footer {
    margin-top: 8px;
    padding-top: 6px;
    border-top: 1px solid #313244;
    font-size: 9px;
    color: #585b70;
    text-align: right;
  }
  .refresh-btn {
    background: none;
    border: none;
    color: #585b70;
    cursor: pointer;
    font-size: 9px;
    padding: 0;
    font-family: inherit;
  }
  .refresh-btn:hover { color: #cdd6f4; }
  .empty {
    color: #585b70;
    font-style: italic;
    padding: 20px 0;
    text-align: center;
  }
</style>
</head>
<body>
  <div class="header">
    <h2>Todoist</h2>
    <span class="badge">%d tasks</span>
  </div>
  %s
  <div class="footer">
    <button class="refresh-btn" onclick="window.webkit.messageHandlers.todoist.postMessage('refresh')">↻</button>
    %s
  </div>
</body>
</html>
  ]], #tasks,
    #tasks > 0 and table.concat(sections, "\n") or '<div class="empty">No tasks for today</div>',
    lastUpdated or "")
end

local function updateMenubar()
  if not M.menubar then return end

  local linearOn = M.linearModule and M.linearModule.webview ~= nil
  local todoistOn = M.webview ~= nil

  -- Menubar title: show counts
  local dooingCount = 0
  for _, t in ipairs(M.tasks) do
    if t.section_id == DOOING_SECTION then dooingCount = dooingCount + 1 end
  end

  local linearCount = M.linearModule and #(M.linearModule.issues or {}) or 0
  local parts = {}
  if linearOn then parts[#parts + 1] = string.format("L:%d", linearCount) end
  if todoistOn then parts[#parts + 1] = string.format("T:%d", dooingCount) end
  local title = #parts > 0 and table.concat(parts, " ") or "Tasks"
  M.menubar:setTitle(title)

  -- Dropdown menu
  local menu = {
    {
      title = linearOn and "✓ Linear" or "  Linear",
      fn = function()
        if M.linearModule then M.linearModule.toggle() end
        hs.timer.doAfter(0.3, updateMenubar)
      end,
    },
    {
      title = todoistOn and "✓ Todoist" or "  Todoist",
      fn = function()
        M.toggle()
        hs.timer.doAfter(0.3, updateMenubar)
      end,
    },
    { title = "-" },
    {
      title = "Show Both",
      fn = function()
        if M.linearModule and not M.linearModule.webview then M.linearModule.toggle() end
        if not M.webview then showWidget() end
        hs.timer.doAfter(0.3, updateMenubar)
      end,
    },
    {
      title = "Hide All",
      fn = function()
        if M.linearModule and M.linearModule.webview then M.linearModule.toggle() end
        if M.webview then hideWidget() end
        hs.timer.doAfter(0.3, updateMenubar)
      end,
    },
    { title = "-" },
    {
      title = "Refresh",
      fn = function()
        updateWidget()
        if M.linearModule and M.linearModule.webview then
          -- Linear doesn't expose updateWidget, toggle off/on to refresh
          M.linearModule.stop(); M.linearModule.start()
        end
      end,
    },
  }
  M.menubar:setMenu(menu)
end

local function updateWidget()
  fetchTasks(function(tasks)
    if not tasks then return end
    M.tasks = tasks
    local ts = os.date("%%H:%%M")
    if M.webview then
      M.webview:html(buildHTML(tasks, ts))
    end
    updateMenubar()
  end)
end

local function showWidget()
  if M.webview then return end

  local screen = hs.screen.mainScreen():frame()
  -- Position: right side, below Linear widget
  local x = screen.x + screen.w - WIDTH - MARGIN
  local y = screen.y + MARGIN + 620 -- below Linear

  local uc = hs.webview.usercontent.new("todoist"):setCallback(function(msg)
    if msg.body == "refresh" then
      updateWidget()
    end
  end)

  M.webview = hs.webview.new(
    { x = x, y = y, w = WIDTH, h = MAX_HEIGHT },
    { developerExtrasEnabled = false },
    uc
  )

  M.webview:windowStyle({ "utility", "titled", "closable" })
  M.webview:level(hs.canvas.windowLevels.desktopIcon + 1)
  M.webview:allowTextEntry(false)
  M.webview:html(buildHTML({}, "loading..."))
  M.webview:show()

  updateWidget()

  M.timer = hs.timer.doEvery(REFRESH_MIN * 60, updateWidget)
end

local function hideWidget()
  if M.webview then M.webview:delete(); M.webview = nil end
  if M.timer then M.timer:stop(); M.timer = nil end
end

function M.toggle()
  if M.webview then
    hideWidget()
  else
    showWidget()
  end
end

function M.start(linearModule)
  M.linearModule = linearModule

  -- Combined Tasks menubar (Linear + Todoist)
  M.menubar = hs.menubar.new()
  M.menubar:setTitle("Tasks")
  M.menubar:setTooltip("Linear + Todoist widgets")
  updateMenubar()

  -- Auto-show widget on start
  showWidget()
end

function M.stop()
  hideWidget()
  if M.menubar then M.menubar:delete(); M.menubar = nil end
end

return M
