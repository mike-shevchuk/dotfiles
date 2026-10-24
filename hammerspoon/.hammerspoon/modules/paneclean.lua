-- paneclean.lua — Claude Code's tmux screen without its chrome, for the deck's /pane?m=clean (pure Lua, no hs.*).
-- In: capture-pane lines (SGR escapes may stay). Out: { {s = line, m = "u" | "a" | nil}, … } where
--   the prompt box and everything under it (statusline, mode line) is cut, spinner / "✻ … for 9s" / "Tip:" lines go,
--   a tool's ⎿ output folds to 2 lines + "… N рядків", runs of blank lines become one;
--   m = "u" on Mike's "❯ " / "> " line, "a" on Claude's "⏺ " line: the board draws a separator / colour there.
-- Test: lua modules/paneclean_test.lua
local M = {}

-- a TUI ─── or ╌╌╌ rule (box-drawing + spaces only)
function M.isRule(line)
  if not utf8.len(line) then return false end
  for _, cp in utf8.codes(line) do
    if cp ~= 32 and (cp < 0x2500 or cp > 0x257F) then return false end
  end
  return line ~= ""
end

local function plain(l) return (l:gsub("\27%[[%d;]*m", "")) end
local SPIN = { "✻", "✽", "✶", "✳", "✢", "·", "*", "✺", "✦" } -- Claude's spinner frames
local function chrome(p)
  local t = p:gsub("^%s+", "")
  if t:find("Tip:", 1, true) or t:find("^✔ Update installed") then return true end
  for _, g in ipairs(SPIN) do
    if t:sub(1, #g + 1) == g .. " " and (t:find("…", 1, true) or t:find(" for %d")) then return true end
  end
  return false
end

function M.clean(lines)
  local p = {}
  for i, l in ipairs(lines) do p[i] = plain(l) end
  -- the input box: a rule, "❯ …" (maybe wrapped), a rule — cut from its top rule to the end
  local stop = #p + 1
  for i = #p, math.max(1, #p - 40), -1 do
    if M.isRule(p[i]) then
      for j = i - 1, math.max(1, i - 8), -1 do
        if M.isRule(p[j]) then
          if (p[j + 1] or ""):match("^[❯>]") then stop = j end
          break
        end
      end
      if stop <= #p then break end
    end
  end
  local out, blank, i = {}, true, 1
  while i < stop do
    local t = p[i]
    if t:match("^%s*$") then
      if not blank then out[#out + 1] = { s = "" } end
      blank = true
      i = i + 1
    elseif chrome(t) then
      i = i + 1
    elseif t:match("^%s+⎿") then -- tool output: this line and the indented ones under it
      local j = i + 1
      while j < stop and p[j]:match("^%s%s") and not p[j]:match("^%s*$") do j = j + 1 end
      out[#out + 1] = { s = lines[i] }
      if j - i > 1 then out[#out + 1] = { s = lines[i + 1] } end
      if j - i > 2 then out[#out + 1] = { s = "     … " .. (j - i - 2) .. " рядків" } end
      blank, i = false, j
    else
      local m = (t:match("^❯ ") or t:match("^> ")) and "u" or t:match("^⏺") and "a" or nil
      out[#out + 1] = { s = lines[i], m = m }
      blank, i = false, i + 1
    end
  end
  while out[#out] and out[#out].s == "" do out[#out] = nil end
  return out
end

return M
