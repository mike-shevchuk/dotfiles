-- App launching and toggling
local M = {}

function M.toggle(appName)
  return function()
    local app = hs.application.get(appName)
    if app and app:isFrontmost() then
      app:hide()
    else
      hs.application.launchOrFocus(appName)
    end
  end
end

function M.pasteBypass()
  local contents = hs.pasteboard.getContents()
  if contents then
    hs.eventtap.keyStrokes(contents)
  end
end

return M
