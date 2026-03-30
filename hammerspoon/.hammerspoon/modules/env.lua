-- Load .env file from ~/.hammerspoon/.env
local M = {}

local cache = nil

function M.load()
  if cache then return cache end
  cache = {}
  local path = os.getenv("HOME") .. "/.hammerspoon/.env"
  local f = io.open(path, "r")
  if not f then
    print("env: .env file not found at " .. path)
    return cache
  end
  for line in f:lines() do
    -- Skip comments and empty lines
    if not line:match("^%s*#") and not line:match("^%s*$") then
      local key, val = line:match("^([%w_]+)%s*=%s*(.+)%s*$")
      if key and val then
        -- Strip quotes if present
        val = val:gsub("^[\"']", ""):gsub("[\"']$", "")
        cache[key] = val
      end
    end
  end
  f:close()
  return cache
end

function M.get(key)
  local vars = M.load()
  return vars[key]
end

return M
