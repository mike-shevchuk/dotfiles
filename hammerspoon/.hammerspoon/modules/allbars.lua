-- Every Hammerspoon menu-bar widget, for pal's "menubar" folder: a full bar on a notched MacBook hides the ones that
-- don't fit, this reaches them anyway. Must load before the modules that make widgets.
local M = {}
local bars = setmetatable({}, { __mode = "k" }) -- menubar → { menu = table|fn, click = fn }
local mt = hs.getObjectMetatable("hs.menubar")
for _, k in ipairs({ "setMenu", "setClickCallback" }) do
  local orig = mt[k]
  mt[k] = function(self, v, ...)
    local e = bars[self]
    if e then e[k == "setMenu" and "menu" or "click"] = v end
    return orig(self, v, ...)
  end
end
local new = hs.menubar.new
hs.menubar.new = function(...) -- pass args as given: new(nil) is an error, new() is not
  local m = new(...)
  if m and select(1, ...) ~= false then bars[m] = {} end
  return m
end

-- the widgets left to right, as on the bar: { {title, icon (hs.image|nil), open = fn}, … }. open() shows the
-- widget's own native menu (submenus and all) at the mouse, the same as clicking its icon.
local popup = new(false)
function M.widgets()
  local list = {}
  for m, e in pairs(bars) do
    if m:isInMenuBar() and (e.menu or e.click) then list[#list + 1] = { m = m, e = e, x = m:frame().x } end
  end
  table.sort(list, function(a, b) return a.x < b.x end)
  local out = {}
  for _, b in ipairs(list) do
    local e = b.e
    out[#out + 1] = { title = ((b.m:title() or ""):gsub("%s+", " ")), icon = b.m:icon(), open = function()
      if not e.menu then return e.click({}) end
      popup:setMenu(type(e.menu) == "function" and e.menu({}) or e.menu)
      popup:popupMenu(hs.mouse.absolutePosition(), true)
    end }
  end
  return out
end
return M
