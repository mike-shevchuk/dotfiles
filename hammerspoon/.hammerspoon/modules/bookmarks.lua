-- Quick URL bookmarks panel
-- Searchable list of frequent URLs, stored in a JSON file
local M = {}

M.chooser = nil

local BOOKMARKS_FILE = os.getenv("HOME") .. "/.hammerspoon/bookmarks.json"

local function loadBookmarks()
  local f = io.open(BOOKMARKS_FILE, "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(hs.json.decode, content)
  if ok and data then return data end
  return {}
end

local function saveBookmarks(bookmarks)
  local f = io.open(BOOKMARKS_FILE, "w")
  if not f then return end
  f:write(hs.json.encode(bookmarks, true))
  f:close()
end

-- Fuzzy match
local function fuzzyScore(query, target)
  if query == "" then return 1 end
  local q = query:lower()
  local t = target:lower()
  local qi = 1
  local score = 0
  local prevMatch = false
  for ti = 1, #t do
    if qi <= #q and t:sub(ti, ti) == q:sub(qi, qi) then
      if prevMatch then score = score + 5 end
      if ti == 1 or t:sub(ti - 1, ti - 1):match("[%s%-%_/%.:]") then
        score = score + 10
      end
      score = score + 1
      qi = qi + 1
      prevMatch = true
    else
      prevMatch = false
    end
  end
  if qi <= #q then return nil end
  return score
end

-- Add a bookmark from clipboard or prompt
function M.addFromClipboard()
  local url = hs.pasteboard.getContents()
  if not url or not url:match("^https?://") then
    hs.alert.show("Clipboard doesn't contain a URL", 1.5)
    return
  end

  -- Ask for a name
  local _, name = hs.dialog.textPrompt("Add Bookmark", "Name for:\n" .. url, "", "Save", "Cancel")
  if not name or name == "" then return end

  local bookmarks = loadBookmarks()
  -- Remove duplicate URL
  for i, b in ipairs(bookmarks) do
    if b.url == url then table.remove(bookmarks, i); break end
  end
  table.insert(bookmarks, 1, { name = name, url = url, category = "Custom" })
  saveBookmarks(bookmarks)
  hs.alert.show("Bookmark saved: " .. name, 1.5)
end

function M.show()
  if not M.chooser then
    M.chooser = hs.chooser.new(function(choice)
      if not choice then return end
      if choice.action == "add" then
        M.addFromClipboard()
        return
      end
      if choice.url then
        hs.urlevent.openURL(choice.url)
      end
    end)
    M.chooser:placeholderText("Search bookmarks...")
    M.chooser:width(45)

    M.chooser:queryChangedCallback(function(query)
      if not query or query == "" then
        M.chooser:choices(M.buildChoices())
        return
      end
      local all = M.buildChoices()
      local scored = {}
      for _, item in ipairs(all) do
        local s1 = fuzzyScore(query, item.text or "") or 0
        local s2 = fuzzyScore(query, item.subText or "") or 0
        local total = s1 + s2 * 0.5
        if total > 0 then
          scored[#scored + 1] = { item = item, score = total }
        end
      end
      table.sort(scored, function(a, b) return a.score > b.score end)
      local results = {}
      for i, s in ipairs(scored) do
        if i > 20 then break end
        results[#results + 1] = s.item
      end
      M.chooser:choices(results)
    end)
  end

  M.chooser:choices(M.buildChoices())
  M.chooser:show()
end

function M.buildChoices()
  local bookmarks = loadBookmarks()
  local items = {}

  -- Add bookmark option
  items[#items + 1] = {
    text = "+ Add bookmark from clipboard",
    subText = "Paste a URL and save it",
    action = "add",
  }

  for _, b in ipairs(bookmarks) do
    local domain = (b.url or ""):match("https?://([^/]+)") or ""
    items[#items + 1] = {
      text = b.name,
      subText = (b.category or "") .. " — " .. domain,
      url = b.url,
    }
  end

  return items
end

return M
