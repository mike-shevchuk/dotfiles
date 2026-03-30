-- System Monitor Menubar Widget
-- Shows RAM usage, CPU temperature, and top 10 memory-consuming processes
-- Refreshes every 10 seconds

local M = {}

local menubar
local timer
local REFRESH_INTERVAL = 10
local totalMemoryBytes = 0
local PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

local function shellExec(cmd)
    return hs.execute(string.format("export PATH='%s'; %s", PATH, cmd))
end

local function getMemoryUsage()
    local output = shellExec("vm_stat")
    if not output then return 0, totalMemoryBytes, {} end

    local pageSize = tonumber(output:match("page size of (%d+) bytes")) or 16384
    local active = tonumber(output:match("Pages active:%s+(%d+)")) or 0
    local inactive = tonumber(output:match("Pages inactive:%s+(%d+)")) or 0
    local wired = tonumber(output:match("Pages wired down:%s+(%d+)")) or 0
    local compressed = tonumber(output:match("Pages occupied by compressor:%s+(%d+)")) or 0
    local free = tonumber(output:match("Pages free:%s+(%d+)")) or 0
    local purgeable = tonumber(output:match("Pages purgeable:%s+(%d+)")) or 0

    local usedBytes = (active + wired + compressed) * pageSize

    local details = {
        active = active * pageSize,
        wired = wired * pageSize,
        compressed = compressed * pageSize,
        inactive = inactive * pageSize,
        free = free * pageSize,
        purgeable = purgeable * pageSize,
    }

    return usedBytes, totalMemoryBytes, details
end

local function getSwap()
    local output = shellExec("sysctl vm.swapusage")
    if not output then return nil end
    local used = output:match("used = ([%d.]+)M")
    local total = output:match("total = ([%d.]+)M")
    if used and total then
        return tonumber(used), tonumber(total)
    end
    return nil
end

local function getTemperature()
    local output = shellExec("osx-cpu-temp 2>/dev/null")
    if output then
        local temp = output:match("([%d.]+)")
        if temp then return tonumber(temp) end
    end
    return nil
end

local function getTopProcesses()
    local output = shellExec("ps -eo pid,rss,%mem,%cpu,comm -m | head -11 | tail -10")
    if not output then return {} end

    local procs = {}
    for line in output:gmatch("[^\n]+") do
        local pid, rss, mem, cpu, comm = line:match("(%d+)%s+(%d+)%s+([%d.]+)%s+([%d.]+)%s+(.*)")
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
                cpu = tonumber(cpu) or 0,
                memStr = memStr,
            })
        end
    end
    return procs
end

local function formatGB(bytes)
    if not bytes then return "?" end
    local gb = bytes / 1073741824
    if gb >= 1 then
        return string.format("%.1f GB", gb)
    else
        return string.format("%.0f MB", bytes / 1048576)
    end
end

local function killProcess(pid, name)
    local script = string.format([[
        echo "══════════════════════════════════════"
        echo "  Process: %s (PID %d)"
        echo "══════════════════════════════════════"
        echo ""
        ps -p %d -o pid,rss,%%mem,%%cpu,state,start,time,command 2>/dev/null || echo "  Process already exited"
        echo ""
        printf "Kill this process? [y/N] "
        read ans
        if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
            kill %d 2>&1 && echo "✓ Killed %s (PID %d)" || echo "✗ Failed — try force kill? [y/N] " && read f && [ "$f" = "y" ] && kill -9 %d 2>&1 && echo "✓ Force killed"
        else
            echo "Cancelled"
        fi
        echo ""
        echo "Window closes in 3s..."
        sleep 3
    ]], name, pid, pid, pid, name, pid, pid)

    local tmpfile = os.tmpname()
    local f = io.open(tmpfile, "w")
    f:write(script)
    f:close()

    shellExec(string.format(
        'kitty --title "Kill: %s" -o remember_window_size=no -o initial_window_width=80c -o initial_window_height=20c -e bash %s &',
        name, tmpfile
    ))

    hs.timer.doAfter(5, M.refresh)
end

function M.refresh()
    if not menubar then return end

    local used, total, details = getMemoryUsage()
    local temp = getTemperature()
    local procs = getTopProcesses()
    local swapUsed, swapTotal = getSwap()

    local pct = total > 0 and math.floor(used / total * 100) or 0
    local title = string.format("RAM: %d%%", pct)
    if temp then title = title .. string.format(" | %.0f\u{00B0}C", temp) end
    menubar:setTitle(title)

    local menu = {}

    -- Memory overview
    table.insert(menu, {
        title = string.format("RAM: %s / %s (%d%%)", formatGB(used), formatGB(total), pct),
        disabled = true,
    })
    -- Memory breakdown
    table.insert(menu, {
        title = string.format("  Active: %s  |  Wired: %s  |  Compressed: %s",
            formatGB(details.active), formatGB(details.wired), formatGB(details.compressed)),
        disabled = true,
    })
    table.insert(menu, {
        title = string.format("  Free: %s  |  Inactive: %s  |  Purgeable: %s",
            formatGB(details.free), formatGB(details.inactive), formatGB(details.purgeable)),
        disabled = true,
    })

    -- Swap
    if swapUsed and swapTotal then
        local swapStr
        if swapTotal > 0 then
            swapStr = string.format("Swap: %.0f MB / %.0f MB (%.0f%%)", swapUsed, swapTotal, swapUsed / swapTotal * 100)
        else
            swapStr = "Swap: 0 MB"
        end
        table.insert(menu, { title = swapStr, disabled = true })
    end

    -- Temperature
    table.insert(menu, {
        title = temp and string.format("CPU Temp: %.1f\u{00B0}C", temp) or "CPU Temp: N/A",
        disabled = true,
    })

    table.insert(menu, { title = "-" })

    -- Process header
    table.insert(menu, {
        title = string.format("%-4s  %-25s  %7s  %6s", "#", "PROCESS (PID)", "RAM", "CPU%"),
        disabled = true,
    })
    table.insert(menu, { title = "-" })

    -- Process list with CPU%
    for i, p in ipairs(procs) do
        table.insert(menu, {
            title = string.format("%-2d.  %-25s  %7s  %5.1f%%",
                i,
                string.format("%s (%d)", p.name:sub(1, 18), p.pid),
                p.memStr,
                p.cpu),
            fn = function() killProcess(p.pid, p.name) end,
        })
    end

    table.insert(menu, { title = "-" })
    table.insert(menu, { title = "Refresh Now", fn = M.refresh })

    menubar:setMenu(menu)
end

function M.start()
    local memStr = shellExec("sysctl -n hw.memsize")
    totalMemoryBytes = tonumber(memStr) or 0
    menubar = hs.menubar.new()
    M.refresh()
    timer = hs.timer.doEvery(REFRESH_INTERVAL, M.refresh)
end

return M
