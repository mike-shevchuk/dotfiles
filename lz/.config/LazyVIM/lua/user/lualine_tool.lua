local M = {}

local last_sys_info = ""
local last_update_time = 0
local update_interval = 5 -- seconds between real updates
local last_sys_info = "🧠 ? ⧖ | 💾 ? | 🌡️ ?"
local cached_temps = { cpu_t = "?", gpu_t = "?", mem = "?", cpu = "?" }
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

-- Extract CPU and memory usage from system tools
local function update_usage()
  local cpu_line = vim.fn.system("top -bn1 | grep 'Cpu(s)' | sed 's/,/./g'")
  local mem_line = vim.fn.system("free | grep Mem")

  -- local used_cpu = idle and (100 - idle) or "?"
  -- 💾 RAM usage in GB
  local idle = cpu_line:match("(%d+%.%d+) id")
  cached_temps.cpu = idle and string.format("%.2f", 100 - idle) or "?"

  -- 🧠 CPU usage
  local total_kb, _, _, _, _, avail_kb = mem_line:match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
  local used_gb = (total_kb and avail_kb) and (tonumber(total_kb) - tonumber(avail_kb)) / (1024 * 1024) or nil

  cached_temps.mem = used_gb and string.format("%.2f", used_gb) or "?"
end

-- Scan thermal zones and update cpu_t / gpu_t
local function update_temperatures()
  for _, path in ipairs(vim.fn.glob("/sys/class/thermal/thermal_zone*/", true, true)) do
    local sensor_type = read_line(path .. "type")
    local temp_raw = tonumber(read_line(path .. "temp"))

    if sensor_type and temp_raw then
      local temp_c = math.floor(temp_raw / 1000)
      sensor_type = sensor_type:lower()

      if sensor_type:find("pkg") or sensor_type:find("cpu") or sensor_type:find("acpitz") then
        cached_temps.cpu_t = temp_c
      elseif sensor_type:find("gpu") or sensor_type:find("iwlwifi") or sensor_type:find("video") then
        cached_temps.gpu_t = temp_c
      end
    end
  end
end

function M.get_sys_status()
  local now = vim.loop.hrtime() / 1e9 -- convert nanoseconds to seconds

  if now - last_update_time > update_interval then
    -- 🧩 Final formatting
    -- last_sys_info = string.format("cpu: %.2f%% | mem: %.2fGB", used_cpu, used_gb)
    -- last_sys_info = "🧠" .. cpu_str .. "⧖ | 💾" .. mem_str .. "GB"

    update_usage()
    update_temperatures()

    last_sys_info = string.format(
      "🧠 %s⧖ | 💾 %sGB | 🌡️ %s/%s",
      cached_temps.cpu or "?",
      cached_temps.mem or "?",
      cached_temps.cpu_t or "?",
      cached_temps.gpu_t or "?"
    )

    last_update_time = now
  end

  return last_sys_info
end

function M.get_keyboard_layout()
  local result = vim.fn.system("xkb-switch")
  local error_code = vim.v.shell_error

  if error_code ~= 0 then
    if not notified_missing then
      notified_missing = true
      vim.schedule(function()
        vim.notify("❗ Missing `xkb-switch`. Run: yay -S xkb-switch", vim.log.levels.WARN)
      end)
    end
    return "n/a"
  end

  local layout = result:gsub("\n", "")
  return ({
    us = "[EN]",
    ua = "[UA]",
  })[layout] or "[" .. layout .. "]"
end

function M.get_battery_status()
  local battery_ok, battery = pcall(require, "battery")

  local btr = "🔋 N/A"

  if battery_ok and battery then
    -- btr = battery.get_status() .. "🔋"
    btr = battery.get_status_line()
  end

  -- vim.notify(btr)
  return btr
end

local function find_lua_root(filepath)
  -- look for the nearest parent folder named "lua"
  local segments = vim.split(filepath, "/")
  for i = #segments, 1, -1 do
    if segments[i] == "lua" then
      return table.concat(vim.list_slice(segments, 1, i), "/") .. "/"
    end
  end
end

function M.reload_current()
  local file = vim.fn.expand("%:p") -- full file path
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
end, {})

vim.api.nvim_create_user_command("BAT", function()
  vim.notify(M.get_battery_status())
end, {})

vim.api.nvim_create_user_command("LANG", function()
  vim.notify(M.get_keyboard_layout())
end, {})

return M
