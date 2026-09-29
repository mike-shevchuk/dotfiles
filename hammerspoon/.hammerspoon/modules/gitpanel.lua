-- Git status shot
-- Compact panel: commits ahead/behind per repo, diff viewer, action buttons
local M = {}

M.webview = nil
M.visible = false

-- ── Default repos (always present) ───────────────────────────────
local DEFAULT_REPOS = {
  { label = "dotfiles",    path = os.getenv("HOME") .. "/dotfiles"          },
  { label = "rescue",      path = os.getenv("HOME") .. "/rescue-serverless"  },
  { label = "zettelkasten",path = os.getenv("HOME") .. "/zettelkasten"       },
}
-- ─────────────────────────────────────────────────────────────────

local EXTRA_REPOS_FILE = os.getenv("HOME") .. "/.hammerspoon/.git_repos.json"
local WIDTH  = 560
local HEIGHT = 700
local PATH   = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

local function loadExtraRepos()
  local f = io.open(EXTRA_REPOS_FILE, "r")
  if not f then return {} end
  local raw = f:read("*a"); f:close()
  local ok, data = pcall(hs.json.decode, raw)
  return (ok and type(data) == "table") and data or {}
end

local function saveExtraRepos(extras)
  local f = io.open(EXTRA_REPOS_FILE, "w")
  if not f then return end
  f:write(hs.json.encode(extras)); f:close()
end

local function buildRepoList()
  local list = {}
  for _, r in ipairs(DEFAULT_REPOS) do list[#list+1] = r end
  for _, r in ipairs(loadExtraRepos())  do list[#list+1] = r end
  return list
end

M.repos = buildRepoList()

local function gitAsync(dir, args, cb)
  hs.task.new("/bin/sh", function(code, out, err)
    cb(code == 0, (out or "") .. (err or ""))
  end, { "-c", string.format("export PATH='%s'; cd '%s' && git %s 2>&1", PATH, dir, args) }):start()
end

local function js(fn, ...)
  if not M.webview then return end
  local parts = {}
  for _, v in ipairs({ ... }) do
    local s = tostring(v)
      :gsub("\\", "\\\\")
      :gsub("'",  "\\'")
      :gsub("\n", "\\n")
      :gsub("\r", "")
    parts[#parts + 1] = "'" .. s .. "'"
  end
  M.webview:evaluateJavaScript(fn .. "(" .. table.concat(parts, ",") .. ")", function() end)
end

local function fetchRepoStats(idx, repo, done)
  local dir = repo.path
  gitAsync(dir, "rev-parse --abbrev-ref HEAD", function(ok, branch)
    if not ok then
      done(idx, "not found", "?", "?", "?")
      return
    end
    branch = branch:gsub("%s+$", "")
    gitAsync(dir, "rev-list --count @{u}..HEAD 2>/dev/null || echo 0", function(_, ahead)
      ahead = ahead:gsub("%s+$", "")
      gitAsync(dir, "rev-list --count HEAD..@{u} 2>/dev/null || echo 0", function(_, behind)
        behind = behind:gsub("%s+$", "")
        gitAsync(dir, "status --short 2>/dev/null | wc -l | tr -d ' '", function(_, changed)
          changed = changed:gsub("%s+$", "")
          done(idx, branch, ahead, behind, changed)
        end)
      end)
    end)
  end)
end

local function refreshAll()
  local total = #M.repos
  local done  = 0
  for i, repo in ipairs(M.repos) do
    fetchRepoStats(i, repo, function(idx, branch, ahead, behind, changed)
      js("updateRepo", tostring(idx - 1), branch, ahead, behind, changed)
      done = done + 1
      if done == total then js("setLoading", "false") end
    end)
  end
end

local function buildHTML(repos)
  local defaultPaths = {}
  for _, r in ipairs(DEFAULT_REPOS) do defaultPaths[r.path] = true end

  local rows = {}
  for i, r in ipairs(repos) do
    local isExtra = not defaultPaths[r.path]
    local rmBtn = isExtra
      and string.format(' <span class="rm" onclick="removeRepo(%d)">✕</span>', i-1)
      or ""
    rows[#rows + 1] = string.format([[
      <tr id="row%d">
        <td class="rname">%s%s</td>
        <td class="branch" id="br%d">…</td>
        <td class="stat up"   id="up%d">↑ –</td>
        <td class="stat down" id="dn%d">↓ –</td>
        <td class="stat chg"  id="ch%d" onclick="showLocalDiff(%d)" style="cursor:pointer" title="Click to see git diff">~ –</td>
      </tr>]], i-1, r.label, rmBtn, i-1, i-1, i-1, i-1, i-1)
  end

  local opts = {}
  for i, r in ipairs(repos) do
    opts[#opts+1] = string.format('<option value="%d">%s</option>', i-1, r.label)
  end

  return string.format([[
<!DOCTYPE html><html>
<head><style>
* { margin:0; padding:0; box-sizing:border-box; }
body {
  font-family: SF Mono, Menlo, monospace; font-size: 12px;
  background: #1e1e2e; color: #cdd6f4;
  display: flex; flex-direction: column; height: 100vh; overflow: hidden;
}
.top {
  display: flex; align-items: center; justify-content: space-between;
  padding: 7px 12px; background: #181825; border-bottom: 1px solid #313244;
  flex-shrink: 0;
}
.title { font-size: 11px; color: #6c7086; text-transform: uppercase; letter-spacing: .5px; }
.topbtns { display: flex; gap: 6px; }
.icon-btn { background: none; border: none; color: #585b70; cursor: pointer;
            font-size: 13px; font-family: inherit; padding: 0 3px; }
.icon-btn:hover { color: #cdd6f4; }
table { width: 100%%; border-collapse: collapse; flex-shrink: 0; }
tr { border-bottom: 1px solid #2a2a3d; }
td { padding: 7px 10px; }
.rname  { color: #89b4fa; font-weight: 600; font-size: 11px; }
.branch { color: #a6adc8; font-size: 10px; }
.stat   { font-size: 11px; text-align: right; }
.up   { color: #a6e3a1; }
.down { color: #f38ba8; }
.chg  { color: #fab387; }
.zero { color: #45475a; }
.rm { color: #45475a; cursor: pointer; font-size: 9px; margin-left: 4px; }
.rm:hover { color: #f38ba8; }
.diff-repo-label {
  padding: 5px 12px 0; font-size: 10px; color: #6c7086; font-style: italic;
}

/* diff section */
.diff-section {
  flex: 1; overflow-y: auto; border-bottom: 1px solid #313244;
  display: none; flex-direction: column;
}
.diff-section.open { display: flex; }
.diff-group { padding: 6px 12px; }
.diff-group-title {
  font-size: 10px; color: #6c7086; text-transform: uppercase;
  letter-spacing: .5px; margin-bottom: 4px; padding: 4px 0;
  border-bottom: 1px solid #2a2a3d;
}
.diff-group-title.up   { color: #a6e3a1; }
.diff-group-title.down { color: #f38ba8; }
.commit {
  display: flex; gap: 8px; align-items: baseline;
  padding: 4px 6px; border-radius: 3px; cursor: pointer;
}
.commit:hover { background: #313244; }
.chash { color: #89b4fa; font-size: 10px; flex-shrink: 0; min-width: 58px; }
.cmsg  { color: #cdd6f4; font-size: 11px; white-space: nowrap;
         overflow: hidden; text-overflow: ellipsis; }
.empty { color: #45475a; font-size: 11px; padding: 6px; font-style: italic; }

/* actions */
.actions {
  display: flex; gap: 6px; padding: 8px 12px;
  border-top: 1px solid #313244; flex-shrink: 0; flex-direction: column;
}
.msg-row { display: flex; gap: 6px; }
.btn-row { display: flex; gap: 5px; }
input[type=text] {
  flex: 1; background: #313244; border: 1px solid #45475a;
  color: #cdd6f4; padding: 5px 8px; border-radius: 4px;
  font-family: inherit; font-size: 11px; outline: none;
}
input[type=text]:focus { border-color: #89b4fa; }
select {
  background: #313244; border: 1px solid #45475a; color: #cdd6f4;
  padding: 5px 6px; border-radius: 4px; font-family: inherit;
  font-size: 11px; outline: none; cursor: pointer;
}
.btn {
  flex: 1; background: #313244; color: #cdd6f4; border: none;
  padding: 6px 3px; border-radius: 4px; cursor: pointer;
  font-size: 10px; font-family: inherit;
}
.btn:hover    { background: #45475a; }
.btn.primary  { background: #89b4fa; color: #1e1e2e; font-weight: 600; }
.btn.primary:hover { background: #74c7ec; }
.btn.active   { background: #45475a; }

/* output */
.out {
  flex: 1; overflow-y: auto;
  padding: 8px 12px; font-size: 11px; line-height: 1.6;
  white-space: pre-wrap; word-break: break-all; color: #a6adc8;
  border-top: 1px solid #313244; display: none;
  font-family: SF Mono, Menlo, monospace;
  background: #11111b;
}
.out.visible { display: block; }
.ok  { color: #a6e3a1; }
.err { color: #f38ba8; }
.info { color: #89b4fa; }
</style></head>
<body>
  <div class="top">
    <span class="title">Git Status</span>
    <div class="topbtns">
      <button class="icon-btn" onclick="toggleDiff()" id="diffbtn" title="Show diff">📋</button>
      <button class="icon-btn" onclick="addRepo()" title="Add repo folder">＋</button>
      <button class="icon-btn" onclick="refresh()" title="Refresh">↻</button>
    </div>
  </div>

  <table>%s</table>

  <div class="diff-section" id="diffSection">
    <div class="diff-repo-label" id="diffRepoLabel"></div>
    <div class="diff-group" id="pushGroup">
      <div class="diff-group-title up">↑ To Push</div>
      <div id="pushList"><span class="empty">loading…</span></div>
    </div>
    <div class="diff-group" id="pullGroup">
      <div class="diff-group-title down">↓ To Pull</div>
      <div id="pullList"><span class="empty">loading…</span></div>
    </div>
  </div>

  <div class="actions">
    <div class="msg-row">
      <select id="sel" onchange="onRepoChange()">%s</select>
      <input id="msg" type="text" placeholder="commit message…" />
    </div>
    <div class="btn-row">
      <button class="btn" onclick="run('pull')">⬇ Pull</button>
      <button class="btn" onclick="run('commit')">✓ Commit</button>
      <button class="btn" onclick="run('push')">⬆ Push</button>
      <button class="btn primary" onclick="run('commit-push')">✓⬆ C+Push</button>
    </div>
  </div>
  <div class="out" id="out"></div>

<script>
  let diffOpen = false;

  function toggleDiff() {
    diffOpen = !diffOpen;
    document.getElementById('diffSection').classList.toggle('open', diffOpen);
    document.getElementById('diffbtn').classList.toggle('active', diffOpen);
    if (diffOpen) loadDiff();
  }

  function loadDiff() {
    const sel = document.getElementById('sel');
    const repo = parseInt(sel.value);
    const label = sel.options[sel.selectedIndex] ? sel.options[sel.selectedIndex].text : '';
    document.getElementById('diffRepoLabel').textContent = label ? '📁 ' + label : '';
    document.getElementById('pushList').innerHTML = '<span class="empty">loading…</span>';
    document.getElementById('pullList').innerHTML = '<span class="empty">loading…</span>';
    window.webkit.messageHandlers.git.postMessage(JSON.stringify({action:'diff', repo}));
  }

  function onRepoChange() {
    if (diffOpen) loadDiff();
  }

  function refresh() {
    document.getElementById('out').classList.remove('visible');
    window.webkit.messageHandlers.git.postMessage(JSON.stringify({action:'refresh'}));
    if (diffOpen) loadDiff();
  }

  function run(action) {
    const repo = parseInt(document.getElementById('sel').value);
    const msg  = document.getElementById('msg').value.trim();
    window.webkit.messageHandlers.git.postMessage(JSON.stringify({action, repo, msg}));
  }

  function setLoading(on) {}

  function updateRepo(idx, branch, ahead, behind, changed) {
    const i = parseInt(idx);
    const set = (id, text, zero) => {
      const el = document.getElementById(id+i);
      if (el) { el.textContent = text; el.classList.toggle('zero', zero); }
    };
    const br = document.getElementById('br'+i);
    if (branch === 'not found') {
      if (br) { br.textContent = '⚠ not found'; br.style.color = '#585b70'; }
      set('up', '↑ ?', true); set('dn', '↓ ?', true); set('ch', '~ ?', true);
      return;
    }
    if (br) br.textContent = branch ? '⎇ '+branch : '';
    const a = parseInt(ahead)||0, b = parseInt(behind)||0, c = parseInt(changed)||0;
    set('up', '↑ '+a, a===0);
    set('dn', '↓ '+b, b===0);
    set('ch', '~ '+c, c===0);
  }

  function showDiff(aheadLog, behindLog) {
    function renderList(raw, listId) {
      const el = document.getElementById(listId);
      const lines = raw.split('\n').filter(l => l.trim());
      if (!lines.length) {
        el.innerHTML = '<span class="empty">nothing here</span>';
        return;
      }
      el.innerHTML = lines.map(l => {
        const hash = l.substring(0,7);
        const msg  = l.substring(8).replace(/</g,'&lt;');
        return `<div class="commit" onclick="showCommit('${hash}')">
          <span class="chash">${hash}</span>
          <span class="cmsg">${msg}</span>
        </div>`;
      }).join('');
    }
    renderList(aheadLog,  'pushList');
    renderList(behindLog, 'pullList');
  }

  function addRepo() {
    window.webkit.messageHandlers.git.postMessage(JSON.stringify({action:'addrepo'}));
  }

  function addRepoRow(idx, label, removable) {
    const i = parseInt(idx);
    const tbody = document.querySelector('table tbody') || document.querySelector('table');
    const tr = document.createElement('tr');
    tr.id = 'row'+i;
    tr.innerHTML = `
      <td class="rname">${label}${removable==='true'?` <span class="rm" onclick="removeRepo(${i})">✕</span>`:''}</td>
      <td class="branch" id="br${i}">…</td>
      <td class="stat up"   id="up${i}">↑ –</td>
      <td class="stat down" id="dn${i}">↓ –</td>
      <td class="stat chg"  id="ch${i}">~ –</td>`;
    tbody.appendChild(tr);
    const sel = document.getElementById('sel');
    const opt = document.createElement('option');
    opt.value = i; opt.textContent = label;
    sel.appendChild(opt);
  }

  function removeRepo(idx) {
    window.webkit.messageHandlers.git.postMessage(JSON.stringify({action:'removerepo', repo:idx}));
    const tr = document.getElementById('row'+idx);
    if (tr) tr.remove();
    const sel = document.getElementById('sel');
    for (let o of sel.options) { if (parseInt(o.value)===idx) { o.remove(); break; } }
  }

  function showCommit(hash) {
    window.webkit.messageHandlers.git.postMessage(JSON.stringify({action:'show', hash}));
  }

  function showLocalDiff(repoIdx) {
    window.webkit.messageHandlers.git.postMessage(JSON.stringify({action:'localdiff', repo: repoIdx}));
  }

  function showOutput(text, cls) {
    const el = document.getElementById('out');
    el.className = 'out visible ' + cls;
    el.textContent = text.length > 3000 ? text.substring(0, 3000) + '\n… (truncated)' : text;
  }
</script>
</body></html>
]], table.concat(rows, "\n"), table.concat(opts))
end

local function handleAction(data)
  if data.action == "refresh" then
    refreshAll(); return
  end

  local repoIdx = (data.repo or 0) + 1
  local repo    = M.repos[repoIdx]
  if not repo then return end
  local dir = repo.path

  if data.action == "addrepo" then
    -- Open native folder picker (runs outside webview callback)
    hs.timer.doAfter(0, function()
      local result = hs.dialog.chooseFileOrFolder(
        "Select a git repository folder",
        os.getenv("HOME"), false, true, false
      )
      if not result or not result["1"] then return end
      local path = result["1"]
      -- Validate it's a git repo
      gitAsync(path, "rev-parse --git-dir", function(ok, _)
        if not ok then
          hs.alert.show("Not a git repository: " .. path, 2)
          return
        end
        local label = path:match("([^/]+)$") or path
        -- Check not already in list
        for _, r in ipairs(M.repos) do
          if r.path == path then
            hs.alert.show("Already in list: " .. label, 1.5)
            return
          end
        end
        -- Add to repos list and persist
        M.repos[#M.repos + 1] = { label = label, path = path }
        local extras = loadExtraRepos()
        extras[#extras + 1] = { label = label, path = path }
        saveExtraRepos(extras)
        -- Update UI
        js("addRepoRow", tostring(#M.repos - 1), label, "true")
        fetchRepoStats(#M.repos, M.repos[#M.repos], function(idx, branch, ahead, behind, changed)
          js("updateRepo", tostring(idx - 1), branch, ahead, behind, changed)
        end)
      end)
    end)
    return

  elseif data.action == "removerepo" then
    local idx = (data.repo or 0) + 1
    local removed = M.repos[idx]
    if not removed then return end
    -- Only allow removing non-default repos
    local isDefault = false
    for _, r in ipairs(DEFAULT_REPOS) do
      if r.path == removed.path then isDefault = true; break end
    end
    if isDefault then
      js("showOutput", "Cannot remove default repos", "err"); return
    end
    table.remove(M.repos, idx)
    local extras = loadExtraRepos()
    for i, r in ipairs(extras) do
      if r.path == removed.path then table.remove(extras, i); break end
    end
    saveExtraRepos(extras)
    return

  elseif data.action == "diff" then
    gitAsync(dir, "log @{u}..HEAD --oneline 2>/dev/null", function(_, ahead)
      gitAsync(dir, "log HEAD..@{u} --oneline 2>/dev/null", function(_, behind)
        js("showDiff", ahead, behind)
      end)
    end)

  elseif data.action == "localdiff" then
    gitAsync(dir, "diff --stat HEAD", function(_, stat)
      gitAsync(dir, "diff HEAD", function(ok, diff)
        local out = stat .. "\n" .. diff
        js("showOutput", out ~= "\n" and out or "No local changes", ok and "info" or "err")
      end)
    end)

  elseif data.action == "show" then
    -- only allow valid commit hashes (hex chars)
    local hash = (data.hash or ""):match("^[0-9a-fA-F]+$") and data.hash or ""
    if hash == "" then return end
    gitAsync(dir, "show " .. hash .. " --stat --patch", function(ok, out)
      js("showOutput", out, ok and "info" or "err")
    end)

  elseif data.action == "pull" then
    gitAsync(dir, "pull", function(ok, out)
      js("showOutput", out, ok and "ok" or "err")
      refreshAll()
    end)

  elseif data.action == "push" then
    gitAsync(dir, "push", function(ok, out)
      js("showOutput", out, ok and "ok" or "err")
      refreshAll()
    end)

  elseif data.action == "commit" or data.action == "commit-push" then
    local msg = (data.msg or ""):gsub("'", "'\\''")
    if msg == "" then js("showOutput", "Error: empty commit message", "err"); return end
    local extra = data.action == "commit-push" and " && git push" or ""
    gitAsync(dir, "add -A && git commit -m '" .. msg .. "'" .. extra, function(ok, out)
      js("showOutput", out, ok and "ok" or "err")
      refreshAll()
    end)
  end
end

function M.toggle()
  if M.visible and M.webview then
    M.webview:delete(); M.webview = nil; M.visible = false
    return
  end

  local screen = hs.screen.mainScreen():frame()
  local x = screen.x + (screen.w - WIDTH)  / 2
  local y = screen.y + (screen.h - HEIGHT) / 2

  local uc = hs.webview.usercontent.new("git"):setCallback(function(msg)
    local ok, data = pcall(hs.json.decode, msg.body)
    if ok and data then handleAction(data) end
  end)

  M.webview = hs.webview.new(
    { x = x, y = y, w = WIDTH, h = HEIGHT },
    { developerExtrasEnabled = false }, uc
  )
  M.webview:windowStyle({ "titled", "closable", "resizable", "utility" })
  M.webview:level(hs.canvas.windowLevels.floating)
  M.webview:allowTextEntry(true)
  M.webview:html(buildHTML(M.repos))
  M.webview:show()
  M.visible = true
  refreshAll()
end

return M
