-- Shift+digit throws the focused window to a macOS Space. PaperWM does it by
-- opening Mission Control and dragging the window's thumbnail, finding the
-- thumbnail by TITLE — and when the full title is not found it chops words off
-- the end and takes the LAST window that still matches. A short fragment such
-- as "Palette Studio" then matches an unrelated window (a Claude chat about
-- it), and that one gets thrown instead. This replaces only the lookup: exact
-- title first, then shorter prefixes, accepted only when exactly one thumbnail
-- matches; otherwise it refuses and says so, instead of moving the wrong window.
local M = {}

local function mcGroups(id)
  local dock = hs.application.applicationsForBundleID("com.apple.dock")[1]
  local out = {}
  for _, mc in ipairs(hs.axuielement.applicationElement(dock)) do
    if mc.AXIdentifier == "mc" then
      for _, disp in ipairs(mc) do
        if disp.AXIdentifier == "mc.display" then
          for _, el in ipairs(disp) do
            if el.AXIdentifier == id then out[#out + 1] = el end
          end
        end
      end
    end
  end
  return out
end

local function drag(from, to)
  local ev, T = hs.eventtap.event, hs.eventtap.event.types
  ev.newMouseEvent(T.mouseMoved, from):post()
  ev.newMouseEvent(T.leftMouseDown, from):post()
  ev.newMouseEvent(T.leftMouseDragged, to):post()
  ev.newMouseEvent(T.leftMouseUp, to):post()
end

-- Candidate titles from most to least specific: the whole title, then with
-- trailing " - segment"s dropped (browsers append "- App - Profile").
local function candidates(title)
  local out, seen = {}, {}
  local t = title
  while t and #t >= 4 do
    if not seen[t] then seen[t] = true; out[#out + 1] = t end
    t = t:match("^(.*) %- [^%-]*$")
  end
  return out
end

function M.install(pwm)
  local MC = pwm.space.MissionControl
  function MC:moveWindowToSpace(win, space_id)
    if not win then return false, "no focused window" end
    local title = win:title()
    if not title or #title == 0 then title = win:application():title() end
    if not title or #title == 0 then return false, "no title for window" end
    local idx = self:getSpaceIndex(space_id)
    if not idx then return false, "can't find space_id in spaces" end

    hs.spaces.openMissionControl()
    hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, { x = 10, y = 10 }):post()
    local t0 = hs.timer.secondsSinceEpoch()
    while hs.timer.secondsSinceEpoch() - t0 < hs.spaces.MCwaitTime do end

    local thumbs = {}
    for _, g in ipairs(mcGroups("mc.windows")) do
      for _, w in ipairs(g) do thumbs[#thumbs + 1] = w end
    end

    local start, ambiguous
    for _, cand in ipairs(candidates(title)) do
      local hits = {}
      for _, w in ipairs(thumbs) do
        local at = w:attributeValue("AXTitle")
        if at and (at == cand or at:find(cand, 1, true)) then hits[#hits + 1] = w end
      end
      -- an exact title wins outright; otherwise the match must be unambiguous
      for _, w in ipairs(hits) do
        if w:attributeValue("AXTitle") == cand then hits = { w } break end
      end
      if #hits == 1 then start = hs.geometry(hits[1].AXFrame).center break end
      if #hits > 1 then ambiguous = true break end
    end

    if not start then
      hs.spaces.closeMissionControl()
      return false, ambiguous and "several windows match that title; not guessing"
          or "couldn't find mission control window"
    end

    local spaces = {}
    for _, g in ipairs(mcGroups("mc.spaces")) do
      for _, el in ipairs(g) do
        if el.AXIdentifier == "mc.spaces.list" then
          for _, sp in ipairs(el) do spaces[#spaces + 1] = sp end
        end
      end
    end
    local target = spaces[idx]
    if not target then
      hs.spaces.closeMissionControl()
      return false, "no space for space index: " .. idx
    end

    drag(start, hs.geometry(target.AXFrame).center)
    return true
  end
end

return M
