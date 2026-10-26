-- lua modules/paneclean_test.lua (from ~/.hammerspoon or the dotfiles hammerspoon dir): paneclean on saved capture-panes
local dir = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = dir .. "/?.lua;" .. package.path
local pc = require("paneclean")
local fails = 0
local function check(name, ok) print((ok and "  ok   " or "  FAIL ") .. name); if not ok then fails = fails + 1 end end

local function load(name)
  local f = assert(io.open(dir .. "/fixtures/pane-" .. name .. ".txt"))
  local t = f:read("a")
  f:close()
  local lines = {}
  for l in (t .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = (l:gsub("%s+$", "")) end
  local out, text, marks, blanks2 = pc.clean(lines), {}, { u = 0, a = 0 }, false
  for i, x in ipairs(out) do
    text[i] = x.s:gsub("\27%[[%d;]*m", "")
    if x.m then marks[x.m] = marks[x.m] + 1 end
    if i > 1 and x.s == "" and out[i - 1].s == "" then blanks2 = true end
  end
  return table.concat(text, "\n"), marks, blanks2, out
end
local function has(t, s) return t:find(s, 1, true) ~= nil end

print("→ idle (agent resting at its prompt)")
local t, m, b2, out = load("idle")
check("statusline gone", not has(t, "🤖") and not has(t, "⏱") and not has(t, "auto mode on"))
check("input box gone", not t:match("\n❯%s*$") and not pc.isRule(out[#out].s:gsub("\27%[[%d;]*m", "")))
check("spinner / done lines gone", not has(t, "✻ ") and not has(t, "Update installed"))
check("Mike's lines marked u", m.u >= 2)
check("Claude's lines marked a", m.a >= 3)
check("tool output folded", t:match("… %d+ рядків") ~= nil)
check("no blank runs", not b2)

print("→ working (spinner on screen)")
t, m, b2 = load("working")
check("statusline gone", not has(t, "🤖") and not has(t, "⏱"))
check("no spinner", not t:match("\n%s*[✻✽✶✳✢·*] [^\n]*…"))
check("marks", m.a >= 1)
check("no blank runs", not b2)

print("→ permission dialog open")
t, m = load("permission")
check("dialog kept", has(t, "Do you want to proceed?") and has(t, "1. Yes"))
check("Tip gone", not has(t, "Tip:"))
check("dialog's ❯ is not Mike", m.u == 1)
check("Claude marked", m.a == 1)

print(fails == 0 and "PASS" or ("FAIL (" .. fails .. ")"))
os.exit(fails == 0 and 0 or 1)
