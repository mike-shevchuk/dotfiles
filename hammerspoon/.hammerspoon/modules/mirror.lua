-- Screen Mirroring (Sidecar / AirPlay) driven through Control Center.
--
-- macOS ships no public API for "connect that iPad as a display", so the only
-- supported surface is the Control Center → Screen Mirroring pane. This module
-- drives that pane through the accessibility API:
--
--   AXExtrasMenuBar → com.apple.menuextra.controlcenter   AXPress opens the panel
--     → controlcenter-screen-mirroring                    only action is a private
--                                                         "show details"; AXPress is a
--                                                         no-op, so we click it instead
--       → screen-mirroring-device-list                    flat list of sibling rows:
--           "Mirror or Extend to:"                        AXHeading
--           iPad                                          the device row
--           Mirror T27QD-40 / Use As Extended Display     its options, but ONLY while
--           Show Sidebar / Show Touch Bar                 the device is connected
--
-- Every row of one device carries the *same* AXIdentifier, so the first row of
-- an identifier is the device and the rest are its options. The device row is an
-- AXCheckBox while disconnected and an AXDisclosureTriangle once connected;
-- AXValue == 1 means connected in both shapes.
--
-- Connection state is read back from that pane rather than from hs.screen,
-- because a mirroring Sidecar session shows up as "Sidecar Display (AirPlay)"
-- and an extending one under yet another name — neither is the device's name.
--
-- Everything is callback-driven: wireless Sidecar takes several seconds to come
-- up and a busy-wait would freeze every other Hammerspoon hotkey meanwhile.

local M = {}

local ax = hs.axuielement

local CC_BUNDLE     = "com.apple.controlcenter"
local CC_MENU_ITEM  = "com.apple.menuextra.controlcenter"
local MIRROR_BUTTON = "controlcenter-screen-mirroring"
local DEVICE_LIST   = "screen-mirroring-device-list"
local DEVICE_PREFIX = "screen-mirroring-device-"
local CACHE_DIR     = os.getenv("HOME") .. "/.cache/hs"

local EXTEND_OPTION = "Use As Extended Display"
local MIRROR_OPTION = "^Mirror "

M.config = {
  device          = "iPad", -- default target when none is given
  mode            = nil,    -- "mirror" | "extend" | nil (leave whatever macOS picks)
  connect_timeout = 25,     -- wireless Sidecar is slow to hand over
  ui_timeout      = 5,      -- how long the Control Center panes get to appear
  watchdog        = 75,     -- hard deadline for a CLI call to produce a result
  notify          = true,   -- hs.alert on completion (for hotkey use)
}

-- ─── AX plumbing ────────────────────────────────────────────────

local function windowsOf(app) return app:attributeValue("AXWindows") or {} end

local function findAll(el, pred, maxDepth, acc, depth)
  acc, depth = acc or {}, depth or 0
  if depth > (maxDepth or 8) then return acc end
  for _, c in ipairs(el:attributeValue("AXChildren") or {}) do
    if pred(c) then acc[#acc + 1] = c end
    findAll(c, pred, maxDepth, acc, depth + 1)
  end
  return acc
end

local function findInWindows(app, pred)
  for _, w in ipairs(windowsOf(app)) do
    local hit = findAll(w, pred)[1]
    if hit then return hit end
  end
end

local function byId(id)
  return function(e) return e:attributeValue("AXIdentifier") == id end
end

-- A one-shot hs.timer is only kept alive by the reference you hold, and this
-- whole module is a chain of them — an unheld one can be collected mid-flight
-- and the operation then dies without ever calling back. Hold them here, and
-- surface anything that throws instead of losing it inside the timer callback.
local liveTimers = {}
M._lastError = nil

local function later(delay, fn)
  local t
  t = hs.timer.doAfter(delay, function()
    liveTimers[t] = nil
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      M._lastError = err
      print("mirror.lua: " .. tostring(err))
    end
  end)
  liveTimers[t] = true
  return t
end

-- Poll `pred` without blocking Hammerspoon; `cb` gets its value, or nil on timeout.
local function waitUntil(pred, timeout, cb)
  local deadline = hs.timer.secondsSinceEpoch() + timeout
  local function tick()
    local ok, v = pcall(pred)
    if ok and v then return cb(v) end
    if hs.timer.secondsSinceEpoch() >= deadline then return cb(nil) end
    later(0.25, tick)
  end
  tick()
end

-- Synthesise the click a human would make, then put the pointer back.
local function click(el)
  local f = el:attributeValue("AXFrame")
  if not f then return false end
  local saved = hs.mouse.absolutePosition()
  hs.eventtap.leftClick({ x = f.x + f.w / 2, y = f.y + f.h / 2 }, 20000)
  hs.mouse.absolutePosition(saved)
  return true
end

-- ─── Control Center panes ───────────────────────────────────────

-- "Control Center has a window" is not the same as "the panel is open": the
-- process keeps a window around whose children are an AXApplication and an
-- AXMenuBar, which answers to nothing. Counting windows therefore reports the
-- panel open when it is not, and the button is then hunted for in an empty
-- shell forever. Judge by content instead — a real panel carries controls whose
-- identifiers start with controlcenter- or screen-mirroring-.
local function panelIsOpen(a)
  return findInWindows(a, function(e)
    local id = e:attributeValue("AXIdentifier")
    return id ~= nil and (id:find("^controlcenter%-") ~= nil or id:find("^screen%-mirroring") ~= nil)
  end) ~= nil
end

local function openPanel(cb)
  local app = hs.application.get(CC_BUNDLE)
  if not app then return cb(nil, "Control Center is not running") end
  local a = ax.applicationElement(app)
  if panelIsOpen(a) then return cb(a) end

  local extras = a:attributeValue("AXExtrasMenuBar")
  local item = extras and findAll(extras, byId(CC_MENU_ITEM), 1)[1]
  if not item then return cb(nil, "Control Center menu bar item not found") end
  item:performAction("AXPress")

  -- AXPress on that menu bar item stops working sometimes — it reports success
  -- and nothing opens. A synthesised click on the same spot always does, so it
  -- is the fallback, exactly as for the Screen Mirroring button below.
  waitUntil(function() return panelIsOpen(a) or nil end, 1.5, function(opened)
    if opened then return cb(a) end
    click(item)
    waitUntil(function() return panelIsOpen(a) or nil end, M.config.ui_timeout, function(ok)
      if ok then cb(a) else cb(nil, "Control Center panel did not open") end
    end)
  end)
end

-- Control Center sometimes leaves a window behind that answers to nothing: it
-- holds neither the pane nor the button, and Escape will not close it. Anything
-- that trusts "a window exists, so the panel is open" then fails forever. So an
-- unrecognisable window is torn down by toggling the menu bar item, and the
-- whole thing is tried once more from scratch.
local function openMirroring(cb, retried)
  openPanel(function(a, err)
    if not a then return cb(nil, err) end
    if findInWindows(a, byId(DEVICE_LIST)) then return cb(a) end

    local btn = findInWindows(a, byId(MIRROR_BUTTON))
    if not btn then
      if retried then
        return cb(nil, "Screen Mirroring button not found in Control Center")
      end
      local extras = a:attributeValue("AXExtrasMenuBar")
      local item = extras and findAll(extras, byId(CC_MENU_ITEM), 1)[1]
      if item then item:performAction("AXPress") end   -- close the stale panel
      return later(0.8, function() openMirroring(cb, true) end)
    end
    click(btn)

    waitUntil(function() return findInWindows(a, byId(DEVICE_LIST)) end, M.config.ui_timeout, function(ok)
      if ok then return cb(a) end
      -- The pane can be open and still carry no list: that is what an empty
      -- offer looks like, and it is a different problem from the pane refusing
      -- to open. Saying "pane did not open" there sends you debugging the Mac
      -- when the thing to wake is the iPad.
      if findInWindows(a, byId("screen-mirroring-header")) then
        return cb(nil, "Screen Mirroring is open but offering no devices — " ..
                       "wake the iPad, and check it is on this Wi-Fi and the same Apple Account")
      end
      cb(nil, "Screen Mirroring pane did not open")
    end)
  end)
end

local function closePanel()
  local app = hs.application.get(CC_BUNDLE)
  if not app then return end
  local a = ax.applicationElement(app)
  if #windowsOf(a) > 0 then hs.eventtap.keyStroke({}, "escape", 0) end
end

-- Re-read the pane every time: rows are rebuilt as devices connect and expand,
-- which leaves any element we cached behind pointing at nothing.
local function parseDevices(a)
  local list = findInWindows(a, byId(DEVICE_LIST))
  if not list then return {} end

  local devices, seen = {}, {}
  for _, row in ipairs(list:attributeValue("AXChildren") or {}) do
    local id = row:attributeValue("AXIdentifier")
    if id and id:sub(1, #DEVICE_PREFIX) == DEVICE_PREFIX then
      local key  = id:sub(#DEVICE_PREFIX + 1)
      local name = row:attributeValue("AXDescription") or "?"
      local on   = row:attributeValue("AXValue") == 1
      if seen[key] then
        local opts = seen[key].options
        opts[#opts + 1] = { name = name, checked = on, el = row }
      else
        local dev = {
          name      = name,
          id        = key,
          kind      = key:match("^Sidecar:") and "sidecar" or "airplay",
          connected = on,
          el        = row,
          options   = {},
        }
        seen[key], devices[#devices + 1] = dev, dev
      end
    end
  end
  return devices
end

local function pick(devs, name)
  local want = name:lower()
  for _, d in ipairs(devs) do
    if d.name:lower() == want then return d end
  end
  for _, d in ipairs(devs) do
    if d.name:lower():find(want, 1, true) then return d end
  end
end

local function deviceNames(devs)
  local n = {}
  for _, d in ipairs(devs) do n[#n + 1] = d.name end
  return n
end

-- AXPress is honoured by the rows but not by every control in this pane, so
-- fall back to a real click when the row's state has not moved.
local function activate(el, wasOn)
  el:performAction("AXPress")
  later(1.0, function()
    local ok, now = pcall(function() return el:attributeValue("AXValue") end)
    if ok and now ~= nil and (now == 1) == wasOn then click(el) end
  end)
end

local function screenNames()
  local n = {}
  for _, s in ipairs(hs.screen.allScreens()) do n[#n + 1] = s:name() or "?" end
  return n
end

-- Attaching or dropping a display rearranges the desktop, and Control Center
-- dismisses its panel when that happens — so the pane often disappears mid-flight
-- and cannot confirm anything. A changed display set is the second witness.
local function screenSignature()
  local parts = {}
  for _, s in ipairs(hs.screen.allScreens()) do
    local f = s:fullFrame()
    parts[#parts + 1] = ("%s@%dx%d"):format(s:name() or "?", f.w, f.h)
  end
  table.sort(parts)
  return table.concat(parts, "|")
end

-- ─── Mirror / extend ────────────────────────────────────────────

-- The mode options only exist while the device is connected, and there is one
-- "Mirror <display>" per display. `target` is the display the caller wants
-- mirrored, captured *before* connecting: once Sidecar attaches, the main screen
-- is renamed ("Sidecar Display (AirPlay)") and a "Virtual …" display of its own
-- shows up, so asking macOS which screen is main at this point picks the wrong one.
local function findModeOption(dev, mode, target)
  if mode == "extend" then
    for _, o in ipairs(dev.options) do
      if o.name == EXTEND_OPTION then return o end
    end
    return nil
  end
  local first, firstReal
  for _, o in ipairs(dev.options) do
    if o.name:match(MIRROR_OPTION) then
      if target and target ~= "" and o.name:find(target, 1, true) then return o end
      first = first or o
      -- Sidecar's own scratch display is a poor mirror target; keep it last.
      if not o.name:match("^Mirror Virtual ") then firstReal = firstReal or o end
    end
  end
  return firstReal or first
end

local function applyMode(a, name, mode, target, cb)
  if not mode then return cb(true, nil) end
  local dev = pick(parseDevices(a), name)
  if not dev then return cb(false, "device vanished from the pane") end
  local opt = findModeOption(dev, mode, target)
  if not opt then
    return cb(false, ("no %q option offered for %s"):format(mode, dev.name))
  end
  if opt.checked then return cb(true, opt.name .. " already active") end

  -- Switching mirror ↔ extend rearranges the desktop, which dismisses the pane
  -- before it can confirm the new state — so accept a changed display set too.
  local baseline = screenSignature()
  activate(opt.el, opt.checked)
  waitUntil(function()
    local d = pick(parseDevices(a), name)
    local o = d and findModeOption(d, mode, target)
    if o and o.checked then return "pane" end
    if screenSignature() ~= baseline then return "displays" end
    return nil
  end, M.config.ui_timeout + 5, function(ok)
    if ok then cb(true, opt.name) else cb(false, "could not switch to " .. opt.name) end
  end)
end

-- ─── Public API ─────────────────────────────────────────────────

function M.list(cb)
  openMirroring(function(a, err)
    if not a then return cb(false, nil, err) end
    local devs = parseDevices(a)
    closePanel()
    cb(true, devs, ("%d device(s) offered"):format(#devs))
  end)
end

-- opts: { mode = "mirror" | "extend" }
function M.connect(name, opts, cb)
  name, opts, cb = name or M.config.device, opts or {}, cb or function() end
  local mode = opts.mode or M.config.mode

  -- Captured before anything attaches: this is the display "mirror" means.
  local target = hs.screen.mainScreen() and hs.screen.mainScreen():name() or nil

  openMirroring(function(a, err)
    if not a then return cb(false, err) end
    local devs = parseDevices(a)
    local dev = pick(devs, name)
    if not dev then
      closePanel()
      local avail = deviceNames(devs)
      return cb(false, ("%q is not offered by Screen Mirroring (available: %s)")
        :format(name, #avail > 0 and table.concat(avail, ", ") or "none"))
    end

    -- macOS finishes rearranging displays a beat after the pane says it is done,
    -- so let it settle before reading the list back into the message.
    local function report(msg, detail)
      closePanel()
      later(1.5, function()
        cb(true, msg .. (detail and (" — " .. detail) or "") ..
          " | displays: " .. table.concat(screenNames(), ", "))
      end)
    end

    -- The pane may have been dismissed by the display change, so re-open it
    -- before touching the mode options.
    local function finish(msg)
      if not mode then return report(msg) end
      openMirroring(function(a2, err2)
        if not a2 then return report(msg, "could not reopen pane to set mode: " .. tostring(err2)) end
        applyMode(a2, dev.name, mode, target, function(_, detail) report(msg, detail) end)
      end)
    end

    if dev.connected then return finish(dev.name .. " already connected") end

    local baseline = screenSignature()
    activate(dev.el, false)
    waitUntil(function()
      local d = pick(parseDevices(a), name)
      if d and d.connected then return "pane" end
      if screenSignature() ~= baseline then return "displays" end
      return nil
    end, M.config.connect_timeout, function(ok)
      if ok then
        finish("connected " .. dev.name)
      else
        closePanel()
        cb(false, ("%s did not come up in %ds — check it is awake, unlocked, on the same Wi-Fi and signed into the same Apple Account")
          :format(dev.name, M.config.connect_timeout))
      end
    end)
  end)
end

function M.disconnect(name, cb)
  name, cb = name or M.config.device, cb or function() end

  openMirroring(function(a, err)
    if not a then return cb(false, err) end
    local dev = pick(parseDevices(a), name)
    if not dev then
      closePanel()
      return cb(false, ("%q is not in the Screen Mirroring list"):format(name))
    end
    if not dev.connected then
      closePanel()
      return cb(true, dev.name .. " is not connected")
    end

    local baseline = screenSignature()
    activate(dev.el, true)
    waitUntil(function()
      local d = pick(parseDevices(a), name)
      if d and not d.connected then return "pane" end
      if screenSignature() ~= baseline then return "displays" end
      return nil
    end, M.config.ui_timeout + 10, function(ok)
      closePanel()
      if not ok then return cb(false, dev.name .. " is still attached") end
      -- Same settle delay as connect: the display list lags the pane.
      later(1.5, function()
        cb(true, ("disconnected %s — displays: %s"):format(dev.name, table.concat(screenNames(), ", ")))
      end)
    end)
  end)
end

function M.status(name, cb)
  name = name or M.config.device
  openMirroring(function(a, err)
    if not a then return cb(false, err) end
    local dev = pick(parseDevices(a), name)
    closePanel()
    if not dev then
      return cb(false, ("%q is not offered right now — displays: %s"):format(name, table.concat(screenNames(), ", ")))
    end
    local active = {}
    for _, o in ipairs(dev.options) do
      if o.checked then active[#active + 1] = o.name end
    end
    cb(true, ("%s: %s%s — displays: %s"):format(
      dev.name,
      dev.connected and "connected" or "not connected",
      #active > 0 and (" (" .. table.concat(active, ", ") .. ")") or "",
      table.concat(screenNames(), ", ")))
  end)
end

function M.toggle(name, opts, cb)
  name, opts, cb = name or M.config.device, opts or {}, cb or function() end
  openMirroring(function(a, err)
    if not a then return cb(false, err) end
    local dev = pick(parseDevices(a), name)
    local connected = dev and dev.connected
    closePanel()
    -- Re-entering through the public calls costs one extra pane open, which is
    -- cheap next to a Sidecar handshake and keeps the state machine in one place.
    later(0.4, function()
      if connected then M.disconnect(name, cb) else M.connect(name, opts, cb) end
    end)
  end)
end

-- ─── Chooser + hotkey entry points ──────────────────────────────

M._chooser = nil

function M.showChooser()
  M.list(function(ok, devs, err)
    if not ok then return hs.alert.show("Mirror: " .. tostring(err), 3) end
    local items = {}
    for _, d in ipairs(devs) do
      items[#items + 1] = {
        text    = d.name,
        subText = ("%s — %s"):format(d.kind, d.connected and "connected (select to disconnect)" or "not connected"),
        device  = d.name,
      }
    end
    if #items == 0 then
      items[1] = { text = "No devices offered", subText = "wake the iPad, same Wi-Fi + Apple Account", unusable = true }
    end
    M._chooser = M._chooser or hs.chooser.new(function(choice)
      if not choice or choice.unusable then return end
      M.toggle(choice.device, {}, function(_, msg) hs.alert.show("Mirror: " .. msg, 4) end)
    end)
    M._chooser:placeholderText("Mirror or extend to…")
    M._chooser:choices(items)
    M._chooser:show()
  end)
end

function M.toggleDefault(mode)
  M.toggle(M.config.device, { mode = mode }, function(_, msg)
    if M.config.notify then hs.alert.show("Mirror: " .. msg, 4) end
  end)
end

-- ─── Menubar widget ─────────────────────────────────────────────
--
-- Asking the Screen Mirroring pane for the current state means opening Control
-- Center, which would flash the panel open on every refresh. The widget instead
-- reads the display list: an attached Sidecar session always shows up there as
-- "Sidecar Display (AirPlay)", and an AirPlay screen under the device's name.
-- The exact mode (mirror vs extend) is only known after an action, so it is
-- remembered rather than guessed.

local SIDECAR_SCREEN = "Sidecar"

M._menubar   = nil
M._lastMode  = nil
local screenWatcher, widgetTimer
local busy = false

local function attachedScreen()
  local want = M.config.device:lower()
  for _, s in ipairs(hs.screen.allScreens()) do
    local n = s:name() or ""
    if n:find(SIDECAR_SCREEN, 1, true) or n:lower():find(want, 1, true) then return n end
  end
end

local function refreshTitle()
  if not M._menubar then return end
  local on = attachedScreen()
  M._menubar:setTitle(busy and "⏳" or (on and "🪞" or "📱"))
  M._menubar:setTooltip(busy and ("Screen Mirroring: working on " .. M.config.device)
    or (on and (M.config.device .. " attached" .. (M._lastMode and (" (" .. M._lastMode .. ")") or ""))
        or (M.config.device .. " not connected")))
end

-- Run one of the public calls with the widget showing that it is in flight.
local function widgetAction(fn, mode)
  if busy then return hs.alert.show("Mirror: already working on it", 2) end
  busy = true
  refreshTitle()
  fn(function(ok, msg)
    busy = false
    if ok and mode then M._lastMode = mode elseif ok then M._lastMode = nil end
    refreshTitle()
    if M.config.notify then hs.alert.show("Mirror: " .. tostring(msg), 4) end
  end)
end

-- The menu section, also usable from another menubar (see pomodoro/sysmonitor).
function M.getMenuItems()
  local dev, on = M.config.device, attachedScreen()
  local items = {
    { title = ("%s — %s"):format(dev, on and ("attached as " .. on) or "not connected"), disabled = true },
    { title = "-" },
    { title = "🪞 Mirror this screen",
      fn = function() widgetAction(function(cb) M.connect(dev, { mode = "mirror" }, cb) end, "mirror") end },
    { title = "🖥  Use as extended display",
      fn = function() widgetAction(function(cb) M.connect(dev, { mode = "extend" }, cb) end, "extend") end },
  }
  if on then
    items[#items + 1] = { title = "✕  Disconnect",
      fn = function() widgetAction(function(cb) M.disconnect(dev, cb) end) end }
  end
  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = "Pick device…", fn = M.showChooser }
  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = "Displays: " .. table.concat(screenNames(), ", "), disabled = true }
  return items
end

function M.startWidget()
  if M._menubar then return M._menubar end
  M._menubar = hs.menubar.new()
  -- Passing a function rebuilds the menu on every click, so it is always current
  -- without polling anything.
  M._menubar:setMenu(M.getMenuItems)
  refreshTitle()

  -- Attaching or dropping a display fires this, which is exactly when the title
  -- changes; the slow timer only covers states nothing announced.
  screenWatcher = hs.screen.watcher.new(function() later(1.5, refreshTitle) end):start()
  widgetTimer = hs.timer.doEvery(30, refreshTitle)
  return M._menubar
end

function M.stopWidget()
  if screenWatcher then screenWatcher:stop() screenWatcher = nil end
  if widgetTimer then widgetTimer:stop() widgetTimer = nil end
  if M._menubar then M._menubar:delete() M._menubar = nil end
end

-- ─── CLI bridge (used by `just -g mirror*`) ─────────────────────
--
-- `hs -c` keeps streaming the Hammerspoon console back over the ipc socket, so
-- a slow call can leave the shell hanging on unrelated log chatter. Everything
-- therefore runs detached and drops its result in ~/.cache/hs/mirror.{txt,json};
-- the shell side polls for that file instead of waiting on the socket.

local function writeResult(cmd, ok, msg, devs)
  hs.fs.mkdir(CACHE_DIR)
  local lines = { (ok and "OK " or "FAIL ") .. (msg or "") }
  for _, d in ipairs(devs or {}) do
    lines[#lines + 1] = ("%s\t%s\t%s"):format(d.name, d.kind, d.connected and "on" or "off")
  end
  local f = io.open(CACHE_DIR .. "/mirror.txt", "w")
  if f then f:write(table.concat(lines, "\n") .. "\n") f:close() end

  local payload = { ok = ok, cmd = cmd, message = msg, devices = {} }
  for _, d in ipairs(devs or {}) do
    local opts = {}
    for _, o in ipairs(d.options or {}) do
      opts[#opts + 1] = { name = o.name, checked = o.checked }
    end
    payload.devices[#payload.devices + 1] =
      { name = d.name, id = d.id, kind = d.kind, connected = d.connected, options = opts }
  end
  local j = io.open(CACHE_DIR .. "/mirror.json", "w")
  if j then j:write(hs.json.encode(payload)) j:close() end
end

function M.cli(cmd, device, mode)
  device = (device ~= nil and device ~= "") and device or M.config.device
  mode   = (mode ~= nil and mode ~= "") and mode or nil

  local answered = false
  local function done(ok, msg, devs)
    if answered then return end
    answered = true
    writeResult(cmd, ok, msg, devs)
  end

  -- Sidecar lives in the graphical session: on the lock screen there is no
  -- Control Center to open, and every accessibility action quietly does
  -- nothing. Saying so beats letting the UI hunt fail with something vague —
  -- that mistake cost an evening once.
  local session = hs.caffeinate.sessionProperties() or {}
  if session.CGSSessionScreenIsLocked then
    writeResult(cmd, false,
      "the Mac is locked — Sidecar needs an unlocked desktop. Unlock it at the machine, " ..
      "or over Screen Sharing (vnc://" .. (hs.host.localizedName() or "this-mac") .. "), then retry")
    return "locked"
  end

  M._lastError = nil
  later(0, function()
    if cmd == "connect" then
      M.connect(device, { mode = mode }, done)
    elseif cmd == "disconnect" then
      M.disconnect(device, done)
    elseif cmd == "toggle" then
      M.toggle(device, { mode = mode }, done)
    elseif cmd == "list" then
      M.list(function(ok, devs, msg) done(ok, msg, devs) end)
    elseif cmd == "status" then
      M.status(device, done)
    else
      done(false, "unknown command: " .. tostring(cmd))
    end
  end)

  -- The shell blocks on the result file, so never leave it without one: if the
  -- flow above died somewhere, report that rather than hanging the caller.
  later(M.config.watchdog, function()
    done(false, M._lastError and ("errored: " .. tostring(M._lastError):gsub("\n.*", ""))
      or ("no result within %ds"):format(M.config.watchdog))
  end)

  return "queued"
end

return M
