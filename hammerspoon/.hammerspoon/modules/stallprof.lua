-- stallprof.lua — who blocks Hammerspoon's main thread. Required first in init.lua: wraps every callback handed to
-- hs.timer / watchers / hs.task / hotkeys / eventtaps / window filters, and the sync hs.execute / hs.osascript /
-- hs.http calls; anything >500 ms goes to ~/Library/Logs/deck-slow.log as "slow <what> <file:line> N ms".
-- M.current names the callback running right now, M.last the one that finished last (deck's stall line prints both).
local M = { current = nil, last = nil }
local LOG = os.getenv("HOME") .. "/Library/Logs/deck-slow.log"
local now = hs.timer.absoluteTime
local LIMIT = 500

function M.log(line)
  print("deck slow: " .. line)
  local f = io.open(LOG, "a")
  if f then f:write(os.date("%H:%M:%S "), line, "\n"); f:close() end
end

local function where(level)
  local i = debug.getinfo(level, "Sl")
  return i and (i.short_src:gsub("^.*/%.hammerspoon/", "") .. ":" .. (i.currentline or 0)) or "?"
end

local function timed(label, fn, ...)
  local prev, t0 = M.current, now()
  M.current = label
  local r = table.pack(fn(...))
  local ms = (now() - t0) / 1e6
  M.current, M.last = prev, { label = label, at = now(), ms = ms }
  if ms > LIMIT then M.log(string.format("slow %s %.0f ms", label, ms)) end
  return table.unpack(r, 1, r.n)
end

-- constructor(…, fn, …) → the same constructor with every function argument timed, labelled by its caller
local function wrapCtor(tbl, key, name)
  local orig = tbl and tbl[key]
  if type(orig) ~= "function" then return end
  tbl[key] = function(...)
    local label = name .. " " .. where(3)
    local a = table.pack(...)
    for i = 1, a.n do
      local fn = a[i]
      if type(fn) == "function" then a[i] = function(...) return timed(label, fn, ...) end end
    end
    return orig(table.unpack(a, 1, a.n))
  end
end

-- a sync call: time it where it is called
local function wrapSync(tbl, key, name)
  local orig = tbl and tbl[key]
  if type(orig) ~= "function" then return end
  tbl[key] = function(...)
    local label = name .. " " .. where(3)
    local a1 = ...
    if type(a1) == "string" then label = label .. " «" .. a1:sub(1, 60):gsub("%s+", " ") .. "»" end
    return timed(label, orig, ...)
  end
end

for _, k in ipairs({ "doEvery", "doAfter", "doAt", "new", "doUntil", "doWhile", "waitUntil", "waitWhile" }) do
  wrapCtor(hs.timer, k, "timer." .. k)
end
wrapCtor(hs.timer.delayed, "new", "timer.delayed")
wrapCtor(hs.task, "new", "task")
wrapCtor(hs.pathwatcher, "new", "pathwatcher")
wrapCtor(hs.application.watcher, "new", "app.watcher")
wrapCtor(hs.screen.watcher, "new", "screen.watcher")
wrapCtor(hs.screen.watcher, "newWithActiveScreen", "screen.watcher")
wrapCtor(hs.caffeinate.watcher, "new", "caffeinate.watcher")
wrapCtor(hs.spaces.watcher, "new", "spaces.watcher")
wrapCtor(hs.battery.watcher, "new", "battery.watcher")
wrapCtor(hs.audiodevice.watcher, "setCallback", "audio.watcher")
wrapCtor(hs.usb.watcher, "new", "usb.watcher")
wrapCtor(hs.wifi.watcher, "new", "wifi.watcher")
wrapCtor(hs.eventtap, "new", "eventtap")
wrapCtor(hs.hotkey, "new", "hotkey")
wrapCtor(hs.hotkey, "bind", "hotkey")
wrapCtor(hs.menubar, "new", "menubar") -- harmless: no function args
wrapCtor(hs.urlevent, "bind", "urlevent")
wrapSync(hs, "execute", "execute")
wrapSync(hs.osascript, "applescript", "applescript")
wrapSync(hs.osascript, "javascript", "javascript")
wrapSync(hs.osascript, "_osascript", "osascript")
wrapSync(hs.http, "get", "http.get")
wrapSync(hs.http, "post", "http.post")
wrapSync(hs.http, "doRequest", "http.doRequest")
-- a module whose load (its top level / M.start at require) takes >500 ms
local req = require
require = function(name)
  if package.loaded[name] then return req(name) end
  return timed("require " .. name, req, name)
end
-- window-filter subscribers (PaperWM & co): the methods live on the filter objects' metatable
pcall(function()
  local WF = getmetatable(hs.window.filter.new(false)).__index
  local sub = WF.subscribe
  WF.subscribe = function(self, ev, fn, ...)
    local label = "wfilter " .. where(2)
    local function w(f) return function(...) return timed(label, f, ...) end end
    if type(ev) == "table" then -- subscribe({event = fn, …}) form
      local t = {}
      for k, v in pairs(ev) do t[k] = type(v) == "function" and w(v) or v end
      return sub(self, t, fn, ...)
    end
    if type(fn) == "table" then
      local t = {}
      for i, v in ipairs(fn) do t[i] = type(v) == "function" and w(v) or v end
      fn = t
    elseif type(fn) == "function" then fn = w(fn) end
    return sub(self, ev, fn, ...)
  end
end)

-- a userdata finalizer (hs.task, axuielement, …) runs from inside any allocation, so a slow one shows up as a stall at
-- a random Lua line: time every registered metatable's __gc as "gc <type>" (re-scanned each minute: extensions load lazily)
local gcWrapped = {}
local function wrapGc()
  for name, mt in pairs(debug.getregistry()) do
    if type(name) == "string" and type(mt) == "table" and type(mt.__gc) == "function" and not gcWrapped[mt] then
      local orig = mt.__gc
      mt.__gc = function(...) return timed("gc " .. name, orig, ...) end
      gcWrapped[mt] = true
    end
  end
end
M.wrapGc = wrapGc
wrapGc()
M.gcTimer = hs.timer.new(60, wrapGc):start()

-- a stall inside code nobody wrapped (a C call: AX, AppleEvent, DNS…): a 0.25 s heartbeat, and a count hook that,
-- once Lua runs again with the heartbeat >1 s late, logs the stack that was blocked — once per stall
local beat, told = now(), false
M.beatTimer = hs.timer.new(0.25, function() beat, told = now(), false end):start()
debug.sethook(function()
  if told then return end
  local late = (now() - beat) / 1e6
  if late > 1000 then
    told = true
    local fr = {} -- the innermost frame, then only ours (modules/, Spoons/, init.lua): hs internals hide the caller
    for l in debug.traceback("", 2):gmatch("\n%s*([^\n]+)") do
      if #fr == 1 or not l:find("Resources/extensions/", 1, true) then fr[#fr + 1] = l:gsub("^.-%.hammerspoon/", "") end
    end
    table.remove(fr, 1) -- "stack traceback:"
    M.log(string.format("blocked %.0f ms in %s · %s", late, M.current or "?", table.concat(fr, " ← "):sub(1, 600)))
  end
end, "", 1000)

return M
