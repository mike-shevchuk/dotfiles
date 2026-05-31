-- Statusline helpers — cross-platform (Linux + macOS), fully async.
--
-- Every metric (CPU, memory, temps, keyboard layout) is sampled OFF the UI
-- thread with `vim.system()`. The lualine components only ever return a cached
-- string, so they never block a redraw and never error when a tool is missing.
-- This is the fix for the old Linux-only `top -bn1`/`free`/`xkb-switch` calls
-- that ran synchronously on every redraw.

local M = {}

local is_mac = vim.fn.has("mac") == 1
local is_linux = vim.fn.has("linux") == 1

-- ── shared cache ────────────────────────────────────────────────────────────
local update_interval = 5 -- seconds between samples
local last_update_time = 0
local last_sys_info = "🧠 …⧖ | 💾 … | 🌡️ …"
local cached = { cpu = "?", mem = "?", cpu_t = "?", gpu_t = "?" }
local sampling = false -- guard against overlapping samples

local layout_cache = is_mac and "" or "…" -- empty hides the segment on mac
local layout_inflight = false
local notified_missing = false

local function read_line(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local line = f:read("*l")
  f:close()
  return line
end

-- ── styling (unchanged visual language) ─────────────────────────────────────
local function style_cpu(cpu)
  local val = tonumber(cpu)
  if not val then
    return "?"
  end
  local hl, icon
  if val >= 45 then
    hl, icon = "ErrorMsg", "🔥"
  elseif val >= 20 then
    hl, icon = "WarningMsg", "🧠"
  else
    hl, icon = "MoreMsg", "🧊"
  end
  return string.format("%%#%s#%s %.2f%%*", hl, icon, val)
end

local function style_temp(temp)
  if type(temp) ~= "number" then
    return "?"
  end
  local symbol, hl = "🌡️", "Normal"
  if temp >= 60 then
    symbol, hl = "🔥", "ErrorMsg"
  elseif temp < 39 then
    symbol, hl = "🧊", "Comment"
  else
    hl = "WarningMsg"
  end
  return string.format("%%#%s#%d°C%%*%s", hl, temp, symbol)
end

-- ── Linux samplers ──────────────────────────────────────────────────────────
local function sample_linux()
  -- CPU idle from `top`, memory used from `free` — both async.
  vim.system({ "sh", "-c", "top -bn1 | grep 'Cpu(s)' | sed 's/,/./g'" }, { text = true }, function(o)
    local idle = (o.stdout or ""):match("(%d+%.%d+) id")
    cached.cpu = idle and string.format("%.2f", 100 - idle) or "?"
  end)
  vim.system({ "sh", "-c", "free | grep Mem" }, { text = true }, function(o)
    local total, _, _, _, _, avail = (o.stdout or ""):match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
    if total and avail then
      cached.mem = string.format("%.2f", (tonumber(total) - tonumber(avail)) / (1024 * 1024))
    end
  end)
  -- Temps: /sys/class/thermal (synchronous file reads are cheap, no process).
  for _, path in ipairs(vim.fn.glob("/sys/class/thermal/thermal_zone*/", true, true)) do
    local t = (read_line(path .. "type") or ""):lower()
    local raw = tonumber(read_line(path .. "temp"))
    if t ~= "" and raw then
      local c = math.floor(raw / 1000)
      if t:find("pkg") or t:find("cpu") or t:find("acpitz") then
        cached.cpu_t = c
      elseif t:find("gpu") or t:find("iwlwifi") or t:find("video") then
        cached.gpu_t = c
      end
    end
  end
end

-- ── macOS samplers ──────────────────────────────────────────────────────────
local function sample_mac()
  -- One `top -l 1 -n 0` call gives both CPU idle and PhysMem used.
  vim.system({ "top", "-l", "1", "-n", "0" }, { text = true }, function(o)
    local out = o.stdout or ""
    local idle = out:match("CPU usage:.-([%d%.]+)%% idle")
    if idle then
      cached.cpu = string.format("%.2f", 100 - tonumber(idle))
    end
    local used, unit = out:match("PhysMem:%s+([%d%.]+)(%a)%s+used")
    if used then
      local gb = tonumber(used)
      if unit == "M" then
        gb = gb / 1024
      end
      cached.mem = string.format("%.2f", gb)
    end
  end)
  -- macOS exposes no stable userland thermal source → leave temps hidden.
  cached.cpu_t = "?"
  cached.gpu_t = "?"
end

local function refresh_sys()
  if sampling then
    return
  end
  sampling = true
  if is_mac then
    sample_mac()
  elseif is_linux then
    sample_linux()
  end
  -- Re-arm the guard shortly after dispatch; samples are fire-and-forget.
  vim.defer_fn(function()
    sampling = false
  end, 1500)
end

function M.get_sys_status()
  local now = vim.uv.hrtime() / 1e9
  if now - last_update_time > update_interval then
    refresh_sys()
    last_update_time = now
    -- Render from whatever is currently cached (updated by prior async sample).
    if is_mac then
      last_sys_info = string.format("🧠 %s⧖ | 💾 %sGB", style_cpu(cached.cpu), cached.mem or "?")
    else
      last_sys_info = string.format(
        "🧠 %s⧖ | 💾 %sGB | %s/%s",
        style_cpu(cached.cpu),
        cached.mem or "?",
        style_temp(cached.cpu_t),
        style_temp(cached.gpu_t)
      )
    end
  end
  return last_sys_info
end

-- ── keyboard layout ─────────────────────────────────────────────────────────
-- Linux/X11: `xkb-switch`. macOS: no clean CLI → hidden. Sampled async.
local function refresh_layout()
  if not is_linux or layout_inflight then
    return
  end
  if vim.fn.executable("xkb-switch") == 0 then
    if not notified_missing then
      notified_missing = true
      vim.schedule(function()
        vim.notify("ℹ️ `xkb-switch` not found — keyboard-layout segment hidden.", vim.log.levels.INFO)
      end)
    end
    layout_cache = ""
    return
  end
  layout_inflight = true
  vim.system({ "xkb-switch" }, { text = true }, function(o)
    layout_inflight = false
    local layout = (o.stdout or ""):gsub("%s+", "")
    layout_cache = ({ us = "[EN]", ua = "[UA]" })[layout] or (layout ~= "" and "[" .. layout .. "]" or "")
  end)
end

function M.get_keyboard_layout()
  refresh_layout()
  return layout_cache
end

-- ── battery (battery.nvim is itself cross-platform) ─────────────────────────
function M.get_battery_status()
  local ok, battery = pcall(require, "battery")
  if ok and battery then
    return battery.get_status_line()
  end
  return "🔋 N/A"
end

-- ── reload helper (unchanged) ───────────────────────────────────────────────
local function find_lua_root(filepath)
  local segments = vim.split(filepath, "/")
  for i = #segments, 1, -1 do
    if segments[i] == "lua" then
      return table.concat(vim.list_slice(segments, 1, i), "/") .. "/"
    end
  end
end

function M.reload_current()
  local file = vim.fn.expand("%:p")
  local lua_root = find_lua_root(file)
  if not lua_root then
    vim.notify("❌ Could not find 'lua/' root", vim.log.levels.ERROR)
    return
  end
  local module_path = file:gsub(lua_root, ""):gsub("%.lua$", ""):gsub("/", ".")
  if module_path == "" then
    vim.notify("⚠️ Not a Lua module file", vim.log.levels.WARN)
    return
  end
  package.loaded[module_path] = nil
  local ok, result = pcall(require, module_path)
  if ok then
    vim.notify("✅ Reloaded: " .. module_path)
  else
    vim.notify("❌ Error reloading " .. module_path .. ":\n" .. result, vim.log.levels.ERROR)
  end
end

vim.keymap.set("n", "<leader>rr", M.reload_current, { desc = "Reload Current Lua File" })
vim.api.nvim_create_user_command("ReloadCurrent", M.reload_current, {})
vim.api.nvim_create_user_command("SYS", function()
  vim.notify(M.get_sys_status())
end, { desc = "Show system monitor" })
vim.api.nvim_create_user_command("BAT", function()
  vim.notify(M.get_battery_status())
end, { desc = "Show battery" })
vim.api.nvim_create_user_command("LANG", function()
  vim.notify(M.get_keyboard_layout())
end, { desc = "Show lang layout" })

return M
