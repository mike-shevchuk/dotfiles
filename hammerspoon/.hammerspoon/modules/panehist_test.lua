-- lua modules/panehist_test.lua (from ~/.hammerspoon or the dotfiles hammerspoon dir): the screens of a full-screen
-- program, paged through, become one history — nothing lost, nothing twice, in order
local dir = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = dir .. "/?.lua;" .. package.path
local ph = require("panehist")
local fails = 0
local function check(name, ok) print((ok and "  ok   " or "  FAIL ") .. name); if not ok then fails = fails + 1 end end
local function isRule(p) return p ~= "" and p:gsub("─", "") == "" end -- (deck.lua passes paneclean.isRule)

-- a transcript of N rows; the program shows VIEW of them above an 8-row footer, as Claude Code does
local N, VIEW = 400, 66
local function row(i) return ("\27[38;5;250m  row %03d of the conversation, some words\27[0m"):format(i) end
local function screen(top, opts) -- rows top .. top+VIEW-1; opts.hint: scrolled up, the hint over the last row; opts.tick: the status line changed
  local t = {}
  for i = top, top + VIEW - 1 do t[#t + 1] = row(i) .. ((opts and opts.pad) and "      " or "") end
  if opts and opts.hint then t[#t] = ("  row %03d of the conv"):format(top + VIEW - 1) .. "      Jump to bottom · fn+↓ to scroll" end
  for _, f in ipairs({ "", ("─"):rep(60), "❯ ", ("─"):rep(60), "  esp-deck  design/branch", "  model | tokens " .. ((opts and opts.tick) or "442k"), "  auto mode on", "" }) do t[#t + 1] = f end
  return table.concat(t, "\n")
end
local function body(text) -- the conversation rows in a fed result, as numbers
  local nums = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do local n = line:match("row (%d+) of the conv"); if n then nums[#nums + 1] = tonumber(n) end end
  return nums
end
local function runs(nums, from, to) -- exactly from..to, each once, in order
  if #nums ~= to - from + 1 then return false end
  for i, n in ipairs(nums) do if n ~= from + i - 1 then return false end end
  return true
end

local live = N - VIEW + 1 -- the top row of the live screen
local out = ph.feed("@1", screen(live), isRule, nil, 0)
check("the live screen alone is itself", runs(body(out), live, N) and out:find("❯ ", 1, true) ~= nil)
out = ph.feed("@1", screen(live, { tick = "443k" }), isRule, nil, 1)
check("a status line that ticks adds nothing", runs(body(out), live, N) and out:find("443k", 1, true) ~= nil)
-- PageUp by part of a page (Claude scrolls by different amounts): rows in common
out = ph.feed("@1", screen(live - 40, { hint = true, pad = true }), isRule, "PageUp", 2)
check("an older page that overlaps goes above, once", runs(body(out), live - 40, N))
check("the hint drawn over a row is not in the history", out:find("Jump to bottom", 1, true) == nil)
-- PageUp by exactly a page: no row in common, known only by the key
out = ph.feed("@1", screen(live - 40 - VIEW, { hint = true }), isRule, "PageUp", 3)
check("an older page with no row in common goes above too", runs(body(out), live - 40 - VIEW, N))
out = ph.feed("@1", screen(live - 40 - VIEW, { hint = true, tick = "444k" }), isRule, nil, 4)
check("the same page again changes nothing", runs(body(out), live - 40 - VIEW, N))
-- back down to the live end, where three new rows were written meanwhile
N = N + 3
out = ph.feed("@1", screen(live + 3), isRule, "PageDown", 5)
check("back at the live end the new rows are below, the history above stays", runs(body(out), live - 40 - VIEW, N))
-- a dialog over the screen: shown as it is, the history is not lost
local dialog = "Do you want to proceed?\n 1. Yes\n 2. No\n\nEsc to cancel"
check("a screen from nowhere is shown as it is", ph.feed("@1", dialog, isRule, nil, 6) == dialog)
out = ph.feed("@1", screen(live + 3), isRule, nil, 7)
check("and the history is still there after it", runs(body(out), live - 40 - VIEW, N))
-- the limit: the far end goes
ph.MAX = 150
out = ph.feed("@1", screen(live - 40 - VIEW - 30, { hint = true }), isRule, "PageUp", 8)
local b = body(out)
check("past MAX rows the newest end is dropped when history grows upwards", #b <= 150 and b[1] == live - 40 - VIEW - 30)
ph.MAX = 3000
-- another window has its own; one nobody asked for in 10 min is forgotten
check("windows do not mix", runs(body(ph.feed("@2", screen(10), isRule, nil, 9)), 10, 10 + VIEW - 1))
ph.feed("@2", screen(10), isRule, nil, 700)
check("a window not looked at for 10 min is forgotten", ph.acc["@1"] == nil and ph.acc["@2"] ~= nil)
os.exit(fails == 0 and 0 or 1)
