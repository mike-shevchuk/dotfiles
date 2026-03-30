-- Caffeine: prevent display sleep
local M = {}

function M.start()
  M.menubar = hs.menubar.new()
  if not M.menubar then return end

  local function update(state)
    M.menubar:setTitle(state and "☕️" or "💤")
  end

  M.menubar:setClickCallback(function()
    local state = hs.caffeinate.toggle("displayIdle")
    update(state)
    hs.alert.show(state and "Caffeine ON" or "Caffeine OFF", 1)
  end)

  update(hs.caffeinate.get("displayIdle"))
end

return M
