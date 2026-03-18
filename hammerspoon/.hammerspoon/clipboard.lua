-- Clipboard Manager with Global References for GC prevention
-- Includes visual feedback on every new item capture

local history_size = 50
local clipboard_history = hs.settings.get("clipboard_history") or {}
local last_change = hs.pasteboard.changeCount()

-- Prevent GC by storing in a module-level table that we return
local clipboard_manager = {}

-- Chooser UI
clipboard_manager.chooser = hs.chooser.new(function(choice)
    if not choice or choice.unusable then return end
    
    hs.pasteboard.setContents(choice.fullText)
    
    -- Small delay to let pasteboard update
    hs.timer.doAfter(0.1, function()
        hs.eventtap.keyStroke({"cmd"}, "v")
        hs.notify.new({
            title="Clipboard Manager", 
            informativeText="Pasted from history",
            withdrawAfter=1
        }):send()
    end)
end)

-- Formatting for display
local function formatItem(text)
    if not text then return "" end
    local display = text:gsub("[\r\n]+", " "):gsub("%s+", " ")
    if #display > 100 then
        display = display:sub(1, 97) .. "..."
    end
    return display
end

-- Refresh Chooser items
local function updateChooser()
    local menu_items = {}
    for i, item in ipairs(clipboard_history) do
        table.insert(menu_items, {
            text = formatItem(item),
            fullText = item,
            subText = "Item " .. i .. " (#" .. #item .. ")"
        })
    end
    
    if #menu_items == 0 then
        table.insert(menu_items, {text = "Clipboard history is empty", unusable = true})
    end
    
    clipboard_manager.chooser:choices(menu_items)
end

-- Manage History
local function addItem(text)
    if not text or text:gsub("%s+", "") == "" then return end
    
    -- Check for duplicate
    for i, existing in ipairs(clipboard_history) do
        if existing == text then
            table.remove(clipboard_history, i)
            break
        end
    end
    
    table.insert(clipboard_history, 1, text)
    
    if #clipboard_history > history_size then
        table.remove(clipboard_history)
    end
    
    -- Persist to disk
    hs.settings.set("clipboard_history", clipboard_history)
    
    -- Visual feedback for user
    hs.notify.new({
        title="Clipboard", 
        informativeText="Captured: " .. formatItem(text):sub(1, 30),
        withdrawAfter=1
    }):send()
    
    updateChooser()
end

-- Polling Timer
clipboard_manager.timer = hs.timer.doEvery(0.5, function()
    local current_change = hs.pasteboard.changeCount()
    if current_change ~= last_change then
        last_change = current_change
        local text = hs.pasteboard.getContents()
        if text and text ~= "" then
            print("Clipboard: Change detected (" .. current_change .. ")")
            addItem(text)
        end
    end
end)

-- Initialize
updateChooser()

-- Seed initial on load only if history is empty
if #clipboard_history == 0 then
    local initial = hs.pasteboard.getContents()
    if initial then addItem(initial) end
end

-- Hotkey: Alt + Shift + V
hs.hotkey.bind({"alt", "shift"}, "V", function()
    if clipboard_manager.chooser:isVisible() then
        clipboard_manager.chooser:hide()
    else
        updateChooser()
        clipboard_manager.chooser:show()
    end
end)

print("Clipboard Manager: Loaded (History: " .. #clipboard_history .. ")")
return clipboard_manager
