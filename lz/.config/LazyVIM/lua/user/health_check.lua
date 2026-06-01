-- Fast startup health check — cross-platform (Linux + macOS).
--
-- Runs ASYNC on VimEnter (deferred, never blocks startup). Always shows a short
-- OS/nvim line; only raises a WARN popup when something is actually wrong
-- (missing CLI tool, uninstalled LSP server, or a startup error in :messages).
--
-- Manual: `:Health` re-runs and always shows the full report.

local M = {}

-- ── what we expect to be present ────────────────────────────────────────────

-- CLI tools the config leans on. {name, executable}.
local CLI_TOOLS = {
  { "git", "git" },
  { "ripgrep", "rg" },
  { "fd", "fd" },
  { "gh", "gh" },
  { "lazygit", "lazygit" },
  { "node", "node" },
  { "fzf", "fzf" },
}

-- LSP servers we want — derived from the shared single source of truth so this
-- list can't drift from plugins/lsp.lua's ensure_installed.
local LSP_SERVERS = require("user.lsp_servers")

-- ── helpers ─────────────────────────────────────────────────────────────────

local function os_label()
  local sysname
  if vim.fn.has("mac") == 1 then
    sysname = "macOS"
  elseif vim.fn.has("linux") == 1 then
    sysname = "Linux"
  elseif vim.fn.has("win32") == 1 then
    sysname = "Windows"
  else
    sysname = "Unix"
  end
  local arch = (vim.uv.os_uname() or {}).machine or "?"
  local v = vim.version()
  return string.format("%s %s · nvim %d.%d.%d", sysname, arch, v.major, v.minor, v.patch)
end

local function missing_cli()
  local out = {}
  for _, t in ipairs(CLI_TOOLS) do
    if vim.fn.executable(t[2]) == 0 then
      out[#out + 1] = t[1]
    end
  end
  return out
end

local function missing_lsp()
  local bin = vim.fn.stdpath("data") .. "/mason/bin/"
  local out = {}
  for _, s in ipairs(LSP_SERVERS) do
    -- mason bin entries can be symlinks/wrappers; existence of the path is enough.
    if vim.fn.filereadable(bin .. s.mason_bin) == 0 and vim.fn.executable(s.mason_bin) == 0 then
      out[#out + 1] = s.display
    end
  end
  return out
end

-- Scan :messages for error markers (E-codes / "Error executing").
local function startup_errors()
  local ok, msgs = pcall(function()
    return vim.api.nvim_exec2("messages", { output = true }).output
  end)
  if not ok or not msgs then
    return {}
  end
  local out = {}
  for line in msgs:gmatch("[^\n]+") do
    if line:match("E%d%d+:") or line:match("Error executing") or line:match("attempt to %a+ ") then
      out[#out + 1] = line:sub(1, 80) -- truncate long lines
    end
  end
  return out
end

-- ── report ──────────────────────────────────────────────────────────────────

-- force=true (`:Health`) → always show the FULL report, including ✓ lines for
-- the things that passed. force=false (startup) → stay quiet when healthy and
-- only raise a WARN/ERROR popup when something is actually wrong.
function M.run(force)
  local cli = missing_cli()
  local lsp = missing_lsp()
  local errs = startup_errors()
  local healthy = (#cli == 0 and #lsp == 0 and #errs == 0)

  -- Startup path: a healthy system is silent except for one short OK line.
  if healthy and not force then
    vim.notify(" " .. os_label() .. "  ✓ healthy", vim.log.levels.INFO, { title = "nvim health" })
    return
  end

  local lines = { " " .. os_label() }

  -- Startup errors.
  if #errs > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "✗ startup errors (" .. #errs .. "):"
    for _, e in ipairs(errs) do
      lines[#lines + 1] = "  • " .. e
    end
  elseif force then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "✓ no startup errors"
  end

  -- CLI tools.
  if #cli > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "⚠ missing CLI tools: " .. table.concat(cli, ", ")
  elseif force then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "✓ all CLI tools present (" .. #CLI_TOOLS .. ")"
  end

  -- LSP servers.
  if #lsp > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "⚠ LSP not installed: " .. table.concat(lsp, ", ")
    lines[#lines + 1] = "  → run :Mason  (or just open a file of that type; auto-installs)"
  elseif force then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "✓ all LSP servers installed (" .. #LSP_SERVERS .. ")"
  end

  -- Severity: errors → ERROR, missing tools → WARN, full healthy report → INFO.
  local level = vim.log.levels.INFO
  if #errs > 0 then
    level = vim.log.levels.ERROR
  elseif #cli > 0 or #lsp > 0 then
    level = vim.log.levels.WARN
  end
  local title = healthy and "nvim health — all good" or "nvim health — problems found"
  vim.notify(table.concat(lines, "\n"), level, { title = title, timeout = 8000 })
end

-- ── wiring ──────────────────────────────────────────────────────────────────

vim.api.nvim_create_user_command("Health", function()
  M.run(true)
end, { desc = "Re-run the startup health check" })

-- Run once, async, after the UI settles — never blocks startup.
vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("user_health_check", { clear = true }),
  once = true,
  callback = function()
    vim.defer_fn(function()
      M.run(false)
    end, 300)
  end,
})

return M
