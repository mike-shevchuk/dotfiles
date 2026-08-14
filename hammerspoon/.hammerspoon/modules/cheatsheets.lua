-- Every cheatsheet on the machine, opened without leaving the keyboard.
--
-- The sheets already exist and are already indexed by `just -g cheat`; what was
-- missing is reading one *now*, without a terminal, an fzf and a pager. So the
-- same three sources are gathered here and rendered into a window: the README's
-- own sections, the zettelkasten cheatsheet tree, and any claude_code note that
-- calls itself a cheatsheet.
--
-- One sheet is generated rather than read — the palette's own — because a
-- written copy of it would be out of date by the next commit.

local M = {}

local HOME = os.getenv("HOME")

M.sources = {
  readme   = HOME .. "/dotfiles/README.md",
  zettel   = HOME .. "/zettelkasten/IT/cheatsheet",
  claude   = HOME .. "/zettelkasten/claude_code",
}

-- ─── Gathering ──────────────────────────────────────────────────

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local body = f:read("a")
  f:close()
  return body
end

-- The README is one file holding a dozen sheets, so it is split on its own
-- headings rather than shown whole.
local function readmeSections(out)
  local body = readFile(M.sources.readme)
  if not body then return end
  local title, buf = nil, {}
  local function flush()
    if title and #buf > 0 then
      out[#out + 1] = { title = title, origin = "README", body = table.concat(buf, "\n") }
    end
  end
  for line in body:gmatch("([^\n]*)\n?") do
    local h = line:match("^##%s+(.+)$")
    if h then
      flush()
      title, buf = h, { "# " .. h }
    elseif title then
      buf[#buf + 1] = line
    end
  end
  flush()
end

local function walk(dir, match, origin, out, depth)
  depth = depth or 0
  if depth > 3 then return end
  local here = hs.fs.attributes(dir)
  if not here or here.mode ~= "directory" then return end

  -- hs.fs.dir hands back an iterator *and* the directory object it walks, so it
  -- has to be called in the loop header; keeping only the function loses the
  -- state and the first step errors out.
  pcall(function()
    for file in hs.fs.dir(dir) do
      if file ~= "." and file ~= ".." then
        local path = dir .. "/" .. file
        local attrs = hs.fs.attributes(path)
        if attrs and attrs.mode == "directory" then
          walk(path, match, origin, out, depth + 1)
        elseif file:match("%.md$") and (not match or file:lower():find(match, 1, true)) then
          out[#out + 1] = { title = file:gsub("%.md$", ""), origin = origin, path = path }
        end
      end
    end
  end)
end

function M.collect()
  local out = {}
  readmeSections(out)
  walk(M.sources.zettel, nil, "zettelkasten", out)
  walk(M.sources.claude, "cheatsheet", "claude_code", out)
  out[#out + 1] = { title = "Command palette — how it works", origin = "generated",
                    generate = "palette" }
  return out
end

-- ─── Rendering ──────────────────────────────────────────────────

local function escape(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- Just enough Markdown to read by: headings, fenced code, inline code, rules.
-- Anything else keeps its shape, which for a cheatsheet is usually the point.
local function toHTML(md)
  local lines, out, inCode = {}, {}, false
  for line in (md .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end

  for _, line in ipairs(lines) do
    if line:match("^```") then
      out[#out + 1] = inCode and "</pre>" or "<pre class='code'>"
      inCode = not inCode
    elseif inCode then
      out[#out + 1] = escape(line)
    else
      local h, text = line:match("^(#+)%s+(.+)$")
      if h then
        local level = math.min(#h + 1, 4)
        out[#out + 1] = ("<h%d>%s</h%d>"):format(level, escape(text), level)
      elseif line:match("^%s*$") then
        out[#out + 1] = "<div class='gap'></div>"
      elseif line:match("^%-%-%-+$") then
        out[#out + 1] = "<hr>"
      else
        local esc = escape(line):gsub("`([^`]+)`", "<code>%1</code>")
        out[#out + 1] = "<p>" .. esc .. "</p>"
      end
    end
  end
  if inCode then out[#out + 1] = "</pre>" end
  return table.concat(out, "\n")
end

local CSS = [[
  :root { color-scheme: dark; }
  body { background:#16161e; color:#c0caf5; margin:0; padding:28px 34px 60px;
         font:14px/1.55 -apple-system, BlinkMacSystemFont, sans-serif; }
  h1,h2,h3,h4 { color:#7aa2f7; margin:22px 0 8px; line-height:1.25; }
  h1 { font-size:24px; border-bottom:1px solid #2a2e42; padding-bottom:8px; }
  h2 { font-size:18px; } h3 { font-size:15px; } h4 { font-size:14px; }
  p { margin:2px 0; white-space:pre-wrap; }
  code { background:#1f2335; color:#f7c948; padding:1px 5px; border-radius:4px;
         font:12.5px/1.4 Menlo, monospace; }
  pre.code { background:#1a1b26; border:1px solid #2a2e42; border-radius:8px;
             padding:12px 14px; overflow-x:auto; margin:10px 0;
             font:12.5px/1.5 Menlo, monospace; color:#9ece6a; white-space:pre; }
  hr { border:0; border-top:1px solid #2a2e42; margin:18px 0; }
  .gap { height:8px; }
  .head { position:sticky; top:0; background:#16161ee6; backdrop-filter:blur(6px);
          margin:-28px -34px 16px; padding:14px 34px; border-bottom:1px solid #2a2e42;
          font:12px Menlo, monospace; color:#565f89; }
]]

M._view = nil

-- Closing has to be handled by the page, not by a hotkey. A modal bound to esc
-- swallows esc for every other app while the window is up — and one bound to a
-- bare letter steals that letter from whatever you are typing into. A keydown
-- listener inside the document only ever fires when this window has focus.
local CLOSE_JS = [[
  <script>
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' || e.key === 'q') {
        webkit.messageHandlers.cheatsheet.postMessage('close');
      }
    });
  </script>
]]

local userContent = hs.webview.usercontent.new("cheatsheet")
userContent:setCallback(function(msg)
  if msg and msg.body == "close" then M.close() end
end)

function M.render(title, origin, md)
  local html = ([[<html><head><meta charset="utf-8"><style>%s</style></head><body>
    <div class="head">%s &nbsp;·&nbsp; %s &nbsp;·&nbsp; esc or q to close</div>%s%s</body></html>]])
    :format(CSS, escape(title), escape(origin), toHTML(md), CLOSE_JS)

  local screen = hs.screen.mainScreen():frame()
  local w = math.min(980, screen.w - 120)
  local h = math.min(880, screen.h - 120)
  local rect = { x = screen.x + (screen.w - w) / 2, y = screen.y + (screen.h - h) / 2, w = w, h = h }

  if M._view then M._view:delete() end
  M._view = hs.webview.new(rect, {}, userContent)
    :windowStyle({ "titled", "closable", "resizable" })
    :windowTitle(title)
    :allowTextEntry(true)   -- the page needs keys to hear esc at all
    :deleteOnClose(true)
    :html(html)
    :bringToFront(true)
    :show()

  -- Focus the window itself, or the keys go to whatever was in front and the
  -- page never sees them.
  hs.timer.doAfter(0.2, function()
    local w = M._view and M._view:hswindow()
    if w then w:focus() end
  end)
end

function M.close()
  if M._view then M._view:delete() M._view = nil end
end

-- ─── The generated one ──────────────────────────────────────────

local PALETTE_SHEET = [[
# Command palette

Open it with `ctrl+alt+shift+Space`. Everything this machine can do is in there:
the Hammerspoon bindings, every module function that never got a chord, and all
the `just -g` recipes from dotfiles.

## Moving around

The first screen is categories. Enter goes into one, `esc` comes back out.
`⌘1`…`⌘9` pick a row straight away without arrowing to it.

The first rows are the ones worth reaching for before any category:

```
Cheatsheet — all commands and their keys
Menu of this app          every menu command of the front app
Click anything by keyboard   labels every button; type a label
Move the cursor with keys    hjkl to move, space to click
Show all windows             Exposé, ignores the tiler
```

## Filtering — one character, no Enter

```
*   only the starred ones
!   only shell recipes (just -g …)
?   only what has a hotkey — the real cheatsheet
#   the archive
/   only Hammerspoon (bindings + module functions)
```

The character disappears from the box as soon as it is understood; keep typing
to search inside what is left.

## Arranging — one character, then Enter on a command

```
+   star it, so it sits at the top       (again to unstar)
-   archive it, out of the way           (again to bring it back)
>   move it to another category
```

The placeholder tells you which mode you are in, so there is nothing to
remember. Stars, the archive and moves are saved and survive a reload.

## Order

Most-used first, counted per command. Ties keep the order the files give them,
so the list stays familiar instead of reshuffling every time. `Archive` always
sorts last.

## Where the entries come from

```
init.lua      the bindings, described by the comments above them
modules/*.lua every zero-argument M.* function
global.just   every recipe, with its doc comment and group
```

Nothing is registered by hand. Edit a comment, add a function, write a recipe —
it appears on the next reload.
]]

-- ─── Picker ─────────────────────────────────────────────────────

M._chooser = nil

function M.show()
  local sheets = M.collect()
  local rows = {}
  for _, s in ipairs(sheets) do
    rows[#rows + 1] = {
      text    = s.title,
      subText = hs.styledtext.new(s.origin, { color = { hex = "#7AA2F7" },
                                              font = { name = "Menlo", size = 12 } }),
      sheet   = s,
    }
  end

  M._chooser = M._chooser or hs.chooser.new(function(choice)
    if not choice then return end
    local s = choice.sheet
    if s.generate == "palette" then
      return M.render(s.title, "generated", PALETTE_SHEET)
    end
    local md = s.body or readFile(s.path)
    if not md then return hs.alert.show("Cannot read " .. tostring(s.path), 3) end
    M.render(s.title, s.origin, md)
  end)
  M._chooser:placeholderText(("cheatsheet — %d of them"):format(#rows))
  M._chooser:searchSubText(true)
  M._chooser:bgDark(true)
  M._chooser:width(40)
  M._chooser:rows(14)
  M._chooser:choices(rows)
  M._chooser:show()
end

-- Straight to the palette's own sheet, for when that is the one you want
function M.palette()
  M.render("Command palette — how it works", "generated", PALETTE_SHEET)
end

return M
