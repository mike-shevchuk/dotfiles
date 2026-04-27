-- System Monitor Menubar Widget
-- Shows RAM, processes, pomodoro, and caffeine in one menubar item
-- Refreshes every 10 seconds (pomodoro updates every 1s via callback)

local M = {}

local pomodoro = require("modules.pomodoro")
local guard    = require("modules.guard")
local system   = require("modules.system")
local menubar
local timer
local REFRESH_INTERVAL = 10
local totalMemoryBytes = 0
local cachedRamPct = 0
local caffeineState = false
local PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
local FONT = { name = "Menlo", size = 12 }

local function shellExec(cmd)
    return hs.execute(string.format("export PATH='%s'; %s", PATH, cmd))
end

local function styled(text)
    return hs.styledtext.new(text, { font = FONT })
end

local function formatGB(bytes)
    if not bytes then return "?" end
    return string.format("%.1f GB", bytes / 1073741824)
end

local function formatMB(mb)
    if mb >= 1024 then
        return string.format("%.1f GB", mb / 1024)
    else
        return string.format("%.0f MB", mb)
    end
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

local function formatUptime(etimeStr)
    if not etimeStr then return "?" end
    local days, h, m = etimeStr:match("(%d+)-(%d+):(%d+)")
    if days then return string.format("%dd %dh", tonumber(days), tonumber(h)) end
    h, m = etimeStr:match("(%d+):(%d+):%d+")
    if h then return string.format("%dh %dm", tonumber(h), tonumber(m)) end
    m = etimeStr:match("(%d+):%d+")
    if m then return string.format("%dm", tonumber(m)) end
    return etimeStr
end

local function getTopProcesses()
    local output = shellExec("ps -eo pid,user,rss,%cpu,etime,comm -m | head -11 | tail -10")
    if not output then return {} end

    local procs = {}
    for line in output:gmatch("[^\n]+") do
        local pid, user, rss, cpu, etime, comm =
            line:match("(%d+)%s+(%S+)%s+(%d+)%s+([%d.]+)%s+(%S+)%s+(.*)")
        if pid then
            local name = (comm:match("([^/]+)$") or comm):gsub("^%s+", ""):gsub("%s+$", "")
            local rssMB = (tonumber(rss) or 0) / 1024

            table.insert(procs, {
                name = name,
                pid = tonumber(pid),
                user = user,
                cpu = tonumber(cpu) or 0,
                ramStr = formatMB(rssMB),
                uptime = formatUptime(etime),
            })
        end
    end
    return procs
end

local function killProcess(pid, name)
    local btn = hs.dialog.blockAlert(
        string.format("Kill process: %s (PID %d)?", name, pid),
        "Send SIGTERM to this process.",
        "Kill", "Cancel"
    )
    if btn ~= "Kill" then return end

    local ok = os.execute(string.format("kill -15 %d", pid))
    if ok then
        hs.alert.show(string.format("Killed %s (PID %d)", name, pid), 2)
    else
        -- SIGTERM failed, offer force kill
        local forceBtn = hs.dialog.blockAlert(
            string.format("Failed to kill %s (PID %d)", name, pid),
            "Try force kill (SIGKILL)?",
            "Force Kill", "Cancel"
        )
        if forceBtn == "Force Kill" then
            os.execute(string.format("kill -9 %d", pid))
            hs.alert.show(string.format("Force killed %s (PID %d)", name, pid), 2)
        end
    end

    hs.timer.doAfter(2, M.refresh)
end

-- Update only the menubar title (called by pomodoro every second)
-- Uses cached RAM percentage to avoid spawning vm_stat subprocess each time
local function updateTitle()
    if not menubar then return end

    local parts = { guard.enabled and "🔨" or "⛔" }
    table.insert(parts, string.format("RAM: %d%%", cachedRamPct))

    local pomoTitle = pomodoro.getTitle()
    if pomoTitle then
        table.insert(parts, pomoTitle)
    end

    table.insert(parts, caffeineState and "☕️" or "💤")

    menubar:setTitle(table.concat(parts, " | "))
end

function M.refresh()
    if not menubar then return end

    local used, total, details = getMemoryUsage()
    local procs = getTopProcesses()
    local swapUsed, swapTotal = getSwap()

    local pct = total > 0 and math.floor(used / total * 100) or 0
    cachedRamPct = pct

    -- Update title
    updateTitle()

    local menu = {}

    -- Memory overview
    table.insert(menu, {
        title = styled(string.format("RAM:  %s / %s (%d%%)", formatGB(used), formatGB(total), pct)),
        disabled = true,
    })
    table.insert(menu, {
        title = styled(string.format("  Active: %-8s  Wired: %-8s  Compressed: %s",
            formatGB(details.active), formatGB(details.wired), formatGB(details.compressed))),
        disabled = true,
    })
    table.insert(menu, {
        title = styled(string.format("  Free:   %-8s  Inactive: %-5s  Purgeable: %s",
            formatGB(details.free), formatGB(details.inactive), formatGB(details.purgeable))),
        disabled = true,
    })

    -- Swap
    if swapUsed and swapTotal then
        local swapStr
        if swapTotal > 0 then
            swapStr = string.format("Swap: %s / %s (%.0f%%)",
                formatMB(swapUsed), formatMB(swapTotal), swapUsed / swapTotal * 100)
        else
            swapStr = "Swap: 0 MB"
        end
        table.insert(menu, { title = styled(swapStr), disabled = true })
    end

    table.insert(menu, { title = "-" })

    -- Process header
    table.insert(menu, {
        title = styled(string.format(
            "%-3s %-16s %7s  %5s  %-7s  %s",
            "#", "PROCESS", "RAM", "CPU", "UPTIME", "USER")),
        disabled = true,
    })
    table.insert(menu, { title = "-" })

    -- Process list
    for i, p in ipairs(procs) do
        local procName = p.name:sub(1, 14)
        table.insert(menu, {
            title = styled(string.format(
                "%-3s %-16s %7s  %4.1f%%  %-7s  %s",
                i .. ".", procName, p.ramStr, p.cpu, p.uptime, p.user)),
            fn = function() killProcess(p.pid, p.name) end,
        })
    end

    -- Pomodoro section
    table.insert(menu, { title = "-" })
    table.insert(menu, { title = "Pomodoro", disabled = true })
    local pomoItems = pomodoro.getMenuItems()
    for _, item in ipairs(pomoItems) do
        table.insert(menu, item)
    end

    -- Trackpad section
    table.insert(menu, { title = "-" })
    table.insert(menu, { title = "Trackpad", disabled = true })
    table.insert(menu, {
        title = system.isPinchZoomBlocked()
            and "🤏 Pinch Zoom: BLOCKED  (click to allow)"
            or  "🤏 Pinch Zoom: allowed  (click to block)",
        fn = function()
            system.togglePinchZoom()
            M.refresh()
        end,
    })
    local currentMult = system.getScrollMultiplier()
    table.insert(menu, {
        title = string.format("↕  Scroll Speed: %.1fx  →  (slider)", currentMult),
        fn    = function() system.showScrollPanel() end,
    })
    for _, mult in ipairs({ 0.5, 1.0, 1.5, 2.0, 3.0 }) do
        table.insert(menu, {
            title = string.format("↕  Scroll %.1fx%s", mult, currentMult == mult and " ✓" or ""),
            fn = function()
                system.setScrollMultiplier(mult)
                M.refresh()
            end,
        })
    end

    -- Toggles section
    table.insert(menu, { title = "-" })
    table.insert(menu, {
        title = guard.enabled and "🔨 Hotkeys: ON (click to disable)" or "⛔ Hotkeys: OFF (click to enable)",
        fn = function()
            guard.toggle()
            updateTitle()
        end,
    })
    table.insert(menu, {
        title = caffeineState and "☕️ Caffeine: ON (click to disable)" or "💤 Caffeine: OFF (click to enable)",
        fn = function()
            caffeineState = hs.caffeinate.toggle("displayIdle")
            hs.alert.show(caffeineState and "Caffeine ON" or "Caffeine OFF", 1)
            updateTitle()
        end,
    })

    table.insert(menu, { title = "-" })
    table.insert(menu, { title = "Refresh Now", fn = M.refresh })

    menubar:setMenu(menu)
end

function M.start()
    local memStr = shellExec("sysctl -n hw.memsize")
    totalMemoryBytes = tonumber(memStr) or 0
    caffeineState = hs.caffeinate.get("displayIdle") or false

    -- Start pomodoro and guard without their own menubars
    pomodoro.start(true)
    pomodoro.onUpdate = updateTitle
    guard.onUpdate = updateTitle

    menubar = hs.menubar.new()
    M.refresh()
    timer = hs.timer.doEvery(REFRESH_INTERVAL, M.refresh)
end

return M
