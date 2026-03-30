-- Linear desktop widget
-- Shows assigned tasks grouped by status, auto-refreshes
local M = {}

local env = require("modules.env")
local API_URL = "https://api.linear.app/graphql"

local function getAPIKey()
  local key = env.get("LINEAR_API_KEY")
  if not key then
    hs.alert.show("Linear: add LINEAR_API_KEY to ~/.hammerspoon/.env", 5)
  end
  return key
end
local REFRESH_MIN = 5

M.webview = nil
M.timer = nil
M.issues = {}

local QUERY = [[
{
  viewer {
    assignedIssues(
      filter: { state: { type: { nin: ["canceled", "completed"] } } }
      orderBy: updatedAt
      first: 30
    ) {
      nodes {
        id
        identifier
        title
        priority
        url
        state { name type }
        labels { nodes { name } }
        project { name }
      }
    }
  }
}
]]

local WIDTH = 340
local MAX_HEIGHT = 600
local MARGIN = 16

local function fetchIssues(callback)
  local apiKey = getAPIKey()
  if not apiKey then callback(nil); return end

  local headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = apiKey,
  }
  local body = hs.json.encode({ query = QUERY })

  hs.http.asyncPost(API_URL, body, headers, function(status, response)
    if status ~= 200 then
      print("Linear API error: " .. tostring(status))
      callback(nil)
      return
    end

    local ok, data = pcall(hs.json.decode, response)
    if not ok or not data then
      print("Linear JSON parse error")
      callback(nil)
      return
    end

    local nodes = data
      and data.data
      and data.data.viewer
      and data.data.viewer.assignedIssues
      and data.data.viewer.assignedIssues.nodes

    if nodes then
      callback(nodes)
    else
      print("Linear: no issues found in response")
      callback({})
    end
  end)
end

local function priorityIcon(p)
  if p == 1 then return "🔴"
  elseif p == 2 then return "🟠"
  elseif p == 3 then return "🟡"
  elseif p == 4 then return "🔵"
  else return "⚪" end
end

local function buildHTML(issues, lastUpdated)
  -- Group by state
  local groups = {}
  local order = { "In Progress", "In Review", "Todo", "Backlog", "Triage" }
  local orderMap = {}
  for i, s in ipairs(order) do orderMap[s] = i end

  for _, issue in ipairs(issues) do
    local state = issue.state and issue.state.name or "Unknown"
    if not groups[state] then groups[state] = {} end
    groups[state][#groups[state] + 1] = issue
  end

  -- Sort groups by order
  local sortedStates = {}
  for state in pairs(groups) do sortedStates[#sortedStates + 1] = state end
  table.sort(sortedStates, function(a, b)
    return (orderMap[a] or 99) < (orderMap[b] or 99)
  end)

  local sections = {}
  local totalActive = 0
  for _, state in ipairs(sortedStates) do
    local items = groups[state]
    totalActive = totalActive + #items
    local rows = {}
    for _, issue in ipairs(items) do
      local pIcon = priorityIcon(issue.priority)
      local labels = ""
      if issue.labels and issue.labels.nodes then
        local ls = {}
        for _, l in ipairs(issue.labels.nodes) do ls[#ls + 1] = l.name end
        if #ls > 0 then labels = table.concat(ls, ", ") end
      end
      local title = issue.title or ""
      if #title > 45 then title = title:sub(1, 42) .. "..." end
      local escapedTitle = title:gsub('"', '&quot;'):gsub("'", "&#39;"):gsub("<", "&lt;")
      local escapedUrl = (issue.url or ""):gsub('"', '&quot;')

      rows[#rows + 1] = string.format([[
        <div class="issue" onclick="window.webkit.messageHandlers.linear.postMessage('%s')" title="%s">
          <span class="prio">%s</span>
          <span class="id">%s</span>
          <span class="title">%s</span>
        </div>
      ]], escapedUrl, escapedTitle, pIcon, issue.identifier, escapedTitle)
    end

    sections[#sections + 1] = string.format([[
      <div class="group">
        <div class="state">%s <span class="count">%d</span></div>
        %s
      </div>
    ]], state, #items, table.concat(rows, "\n"))
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
  .issue {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 5px 6px;
    border-radius: 4px;
    cursor: pointer;
    transition: background 0.15s;
  }
  .issue:hover { background: rgba(69, 71, 90, 0.6); }
  .prio { font-size: 10px; flex-shrink: 0; }
  .id {
    color: #89b4fa;
    font-size: 10px;
    font-family: SF Mono, Menlo, monospace;
    flex-shrink: 0;
    min-width: 65px;
  }
  .title {
    color: #cdd6f4;
    font-size: 11px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
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
</style>
</head>
<body>
  <div class="header">
    <h2>Linear</h2>
    <span class="badge">%d active</span>
  </div>
  %s
  <div class="footer">
    <button class="refresh-btn" onclick="window.webkit.messageHandlers.linear.postMessage('refresh')">↻</button>
    %s
  </div>
</body>
</html>
  ]], totalActive, table.concat(sections, "\n"), lastUpdated or "")
end

local function updateWidget()
  fetchIssues(function(issues)
    if not issues then return end
    M.issues = issues
    local ts = os.date("%%H:%%M")
    if M.webview then
      M.webview:html(buildHTML(issues, ts))
    end
  end)
end

function M.start()
  -- Create widget in bottom-right corner
  local screen = hs.screen.mainScreen():frame()
  local x = screen.x + screen.w - WIDTH - MARGIN
  local y = screen.y + MARGIN

  local uc = hs.webview.usercontent.new("linear"):setCallback(function(msg)
    if msg.body == "refresh" then
      updateWidget()
    elseif msg.body and msg.body:match("^https://") then
      hs.urlevent.openURL(msg.body)
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

  -- Fetch immediately
  updateWidget()

  -- Auto-refresh
  M.timer = hs.timer.doEvery(REFRESH_MIN * 60, updateWidget)
end

function M.stop()
  if M.webview then M.webview:delete(); M.webview = nil end
  if M.timer then M.timer:stop(); M.timer = nil end
end

function M.toggle()
  if M.webview then
    M.stop()
  else
    M.start()
  end
end

return M
