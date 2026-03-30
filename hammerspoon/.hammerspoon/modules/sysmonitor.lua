-- System Monitor Menubar Widget
-- Shows RAM usage, CPU temperature, and top 10 memory-consuming processes
-- Refreshes every 10 seconds

local M = {}

local menubar
local timer
local REFRESH_INTERVAL = 10
local totalMemoryBytes = 0

local function getMemoryUsage()
    local output = hs.execute("vm_stat")
    if not output then return 0, totalMemoryBytes end

    local pageSize = tonumber(output:match("page size of (%d+) bytes")) or 16384
    local active = tonumber(output:match("Pages active:%s+(%d+)")) or 0
    local wired = tonumber(output:match("Pages wired down:%s+(%d+)")) or 0
    local compressed = tonumber(output:match("Pages stored in compressor:%s+(%d+)")) or 0

    return (active + wired + compressed) * pageSize, totalMemoryBytes
end

local function getTemperature()
    local output = hs.execute("osx-cpu-temp 2>/dev/null")
    if output then
        local temp = output:match("([%d.]+)")
        if temp then return tonumber(temp) end
    end
    return nil
end

local function getTopProcesses()
    local output = hs.execute("ps -eo pid,rss,%mem,comm -m | head -11 | tail -10")
    if not output then return {} end

    local procs = {}
    for line in output:gmatch("[^\n]+") do
        local pid, rss, mem, comm = line:match("(%d+)%s+(%d+)%s+([%d.]+)%s+(.*)")
        if pid then
            local name = (comm:match("([^/]+)$") or comm):gsub("^%s+", ""):gsub("%s+$", "")
            local mb = (tonumber(rss) or 0) / 1024
            local memStr = mb >= 1024
                and string.format("%.1f GB", mb / 1024)
                or string.format("%.0f MB", mb)

            table.insert(procs, {
                name = name,
                pid = tonumber(pid),
                mem = tonumber(mem) or 0,
                memStr = memStr,
            })
        end
    end
    return procs
end

local function formatGB(bytes)
    return bytes and string.format("%.1f GB", bytes / 1073741824) or "?"
end

local function killProcess(pid, name)
    local btn = hs.dialog.blockAlert(
        "Kill Process",
        string.format("Kill '%s' (PID %d)?", name, pid),
        "Kill", "Cancel"
    )
    if btn == "Kill" then
        hs.execute(string.format("kill %d", pid))
        hs.notify.new({
            title = "Process Killed",
            informativeText = string.format("%s (PID %d)", name, pid),
        }):send()
        M.refresh()
    end
end

function M.refresh()
    if not menubar then return end

    local used, total = getMemoryUsage()
    local temp = getTemperature()
    local procs = getTopProcesses()

    local pct = total > 0 and math.floor(used / total * 100) or 0
    local title = string.format("RAM: %d%%", pct)
    if temp then title = title .. string.format(" | %.0f\u{00B0}C", temp) end
    menubar:setTitle(title)

    local menu = {
        { title = string.format("RAM: %s / %s (%d%%)", formatGB(used), formatGB(total), pct), disabled = true },
        { title = temp and string.format("CPU Temp: %.1f\u{00B0}C", temp) or "CPU Temp: N/A", disabled = true },
        { title = "-" },
        { title = "Top 10 processes by RAM:", disabled = true },
        { title = "-" },
    }

    for i, p in ipairs(procs) do
        table.insert(menu, {
            title = string.format("%d. %s (PID %d) \u{2014} %s", i, p.name, p.pid, p.memStr),
            fn = function() killProcess(p.pid, p.name) end,
        })
    end

    table.insert(menu, { title = "-" })
    table.insert(menu, { title = "Refresh Now", fn = M.refresh })

    menubar:setMenu(menu)
end

function M.start()
    local memStr = hs.execute("sysctl -n hw.memsize")
    totalMemoryBytes = tonumber(memStr) or 0
    menubar = hs.menubar.new()
    M.refresh()
    timer = hs.timer.doEvery(REFRESH_INTERVAL, M.refresh)
end

return M
