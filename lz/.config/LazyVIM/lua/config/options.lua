-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

local cmd = vim.cmd

cmd("set expandtab")
cmd("set tabstop=2")
cmd("set softtabstop=2")
cmd("set shiftwidth=2")
cmd("set clipboard=unnamedplus")
cmd("set so=6") -- scrolloff alias
vim.g.mapleader = " "
-- (removed: vim.g.background — no-op, the real option is vim.o.background)
-- vim.g.markdown_folding = 1,
-- vim.opt.swapfile = false

-- Clipboard over SSH: the remote Mac always has pbcopy, so nvim's OSC 52
-- auto-detection never activates and yanks land in the REMOTE Mac's
-- pasteboard — invisible on the local machine. Force OSC 52 when SSHed in;
-- tmux passes it through (set-clipboard on in .tmux.conf.local).
if vim.env.SSH_TTY then
  local osc52 = require("vim.ui.clipboard.osc52")
  local function paste_fallback()
    return { vim.split(vim.fn.getreg('"'), "\n"), vim.fn.getregtype('"') }
  end
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    -- OSC 52 paste QUERIES hang on terminals that don't answer them (most).
    -- Paste from the unnamed register instead — remote-side yanks still work,
    -- and local-clipboard paste arrives via terminal paste (Cmd/Ctrl-V) anyway.
    paste = { ["+"] = paste_fallback, ["*"] = paste_fallback },
  }
end

-- (removed: foldexpr = "nvim_treesitter#foldexpr()" — that vimscript function
-- no longer exists on nvim-treesitter `main`; foldmethod=indent never used it)
vim.opt.foldenable = false --
vim.opt.foldmethod = "indent"
vim.opt.foldlevel = 99
-- Resolve zsh per-machine (Linux: /usr/bin/zsh, macOS: /bin/zsh). Falls back to
-- the inherited $SHELL if zsh isn't on PATH.
local zsh = vim.fn.exepath("zsh")
if zsh ~= "" then
  vim.o.shell = zsh
end
-- vim.wo.number = true

-- Silence unused remote-plugin providers (cleans :checkhealth, no behaviour change).
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
