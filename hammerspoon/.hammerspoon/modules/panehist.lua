-- panehist: one history out of the screens of a full-screen program.
-- Claude Code draws on the terminal's alternate screen: tmux keeps no scrollback for it, capture-pane returns only the
-- rows on screen now. The device scrolls such a window with the program's own PageUp / PageDown (deck.lua /key); every
-- screen that comes back is joined here with the ones before it — older rows go above, newer below, nothing shown is
-- dropped — so the device's terminal text simply grows, like a shell's with real scrollback (Mike 2026-11-17).
-- Pure Lua, no Hammerspoon: `lua modules/panehist_test.lua`.
local M = { MAX = 3000, acc = {} } -- MAX rows kept per window; past it the end opposite to the one growing is dropped

local function plain(s) return (s:gsub("\27%]8;[^\27]*\27\\", ""):gsub("\27%[[%d;]*m", ""):gsub("%s+$", "")) end
M.plain = plain

-- A capture's rows → those above the program's footer, their plain text (what rows are compared by), and the footer:
-- from the rule over its input box (the second ─── from the bottom, within 24 rows) to the end.
-- Claude draws «Jump to bottom · …» over the end of the last row when its view is scrolled up: cut from that row.
function M.split(rows, isRule)
  local n, rules, foot = #rows, 0, #rows + 1
  for i = n, math.max(1, n - 24), -1 do
    if isRule(plain(rows[i])) then
      rules = rules + 1
      if rules == 2 then foot = i; break end
    end
  end
  while foot > 1 and plain(rows[foot - 1]) == "" do foot = foot - 1 end -- the empty rows over the footer are its own
  local body, keys, cut, footer = {}, {}, {}, {}
  for i = 1, foot - 1 do
    local p = plain(rows[i])
    local q = p:gsub("%s*Jump to bottom ·.*$", "")
    if q ~= p then body[i], keys[i], cut[i] = q, q, true else body[i], keys[i] = rows[i], p end
  end
  for i = foot, n do footer[#footer + 1] = rows[i] end
  return body, keys, cut, footer
end

-- body row i ↔ acc row i + d: the best d by rows in common (≥ 3 and ≥ 60 % of the overlap), or nil
local function align(a, keys)
  local anchors = {}
  for i = 1, #keys do if #keys[i] >= 12 then anchors[#anchors + 1] = i end end
  local pick, tried, best, bestHits = {}, {}, nil, 0
  for _, k in ipairs({ 1, 2, #anchors - 1, #anchors, #anchors // 2 }) do if anchors[k] then pick[anchors[k]] = true end end
  for ai in pairs(pick) do
    for j = 1, #a.keys do
      local d = j - ai
      if a.keys[j] == keys[ai] and not tried[d] then
        tried[d] = true
        local lo, hi, hits = math.max(1, 1 - d), math.min(#keys, #a.keys - d), 0
        for i = lo, hi do if keys[i] == a.keys[i + d] then hits = hits + 1 end end
        if hi - lo + 1 >= 3 and hits >= 3 and hits >= 0.6 * (hi - lo + 1) and hits > bestHits then best, bestHits = d, hits end
      end
    end
  end
  return best
end

-- one capture of window id (its text), isRule from paneclean, key = the PageUp / PageDown the device sent it within
-- the last seconds (or nil), now = seconds → the text to render: the joined history + this screen's footer
function M.feed(id, out, isRule, key, now)
  for k, a in pairs(M.acc) do if now - a.seen > 600 then M.acc[k] = nil end end -- nobody looked for 10 min
  local rows = {}
  for line in (out .. "\n"):gmatch("(.-)\n") do rows[#rows + 1] = line end
  local body, keys, cut, footer = M.split(rows, isRule)
  local a = M.acc[id]
  if not a then a = { rows = {}, keys = {}, lost = 0 }; M.acc[id] = a end
  a.seen = now
  local d = #a.rows > 0 and align(a, keys) or nil
  local grewUp = false
  if #a.rows == 0 then
    a.rows, a.keys = body, keys
  elseif d then
    a.lost = 0
    local R, Kk = {}, {}
    for i = 1, -d do R[#R + 1], Kk[#Kk + 1] = body[i], keys[i] end -- older than everything kept: above it
    grewUp = #R > 0
    local atEnd = #body + d >= #a.rows -- this screen reaches the end of what is kept: the program's live end
    for j = 1, #a.rows do
      local i = j - d
      local same = i >= 1 and i <= #body and not cut[i] and keys[i] ~= a.keys[j]
      -- a row seen again and drawn differently: at the live end the new drawing wins (a spinner, a line still being
      -- written); elsewhere only a row that was kept cut short by the hint is completed
      if same and (atEnd or keys[i]:sub(1, #a.keys[j]) == a.keys[j]) then R[#R + 1], Kk[#Kk + 1] = body[i], keys[i]
      else R[#R + 1], Kk[#Kk + 1] = a.rows[j], a.keys[j] end
    end
    for i = #a.rows - d + 1, #body do if i >= 1 then R[#R + 1], Kk[#Kk + 1] = body[i], keys[i] end end -- newer: below
    a.rows, a.keys = R, Kk
  elseif key == "PageUp" or key == "PageDown" then
    -- a whole page with no row in common: it is the one next to what is kept, on the side the key went
    a.lost = 0
    local R, Kk = {}, {}
    local first, second = body, a.rows
    local fk, sk = keys, a.keys
    if key == "PageDown" then first, second, fk, sk = a.rows, body, a.keys, keys end
    for i = 1, #first do R[i], Kk[i] = first[i], fk[i] end
    for i = 1, #second do R[#R + 1], Kk[#Kk + 1] = second[i], sk[i] end
    a.rows, a.keys, grewUp = R, Kk, key == "PageUp"
  else
    -- a screen that is nowhere in what is kept (a dialog, /help; or the program cleared): shown as it is. The third
    -- such screen in a row starts the history again from it
    a.lost = a.lost + 1
    if a.lost >= 3 then a.rows, a.keys, a.lost = body, keys, 0 else return out end
  end
  while #a.rows > M.MAX do -- past the limit the far end goes: the newest when history grows upwards, else the oldest
    local at = grewUp and #a.rows or 1
    table.remove(a.rows, at); table.remove(a.keys, at)
  end
  local t = table.move(a.rows, 1, #a.rows, 1, {})
  for i = 1, #footer do t[#t + 1] = footer[i] end
  return table.concat(t, "\n")
end

return M
