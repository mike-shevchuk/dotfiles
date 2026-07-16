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

-- Clipboard: OSC 52 + pbcopy, UNCONDITIONALLY.
-- Why not gate on $SSH_TTY: tmux does not propagate SSH_TTY into panes (it's
-- not in update-environment), and the tmux server usually starts locally — so
-- nvim inside tmux can never tell an SSH attach from a local one. The old
-- guard silently fell back to pbcopy and yanks landed in the REMOTE Mac's
-- pasteboard, invisible on the SSH client.
-- Copy  → OSC 52 (tmux `set-clipboard on` forwards it to WHOEVER is attached:
--         local kitty or the SSH client's terminal) + pbcopy so the Mac's own
--         pasteboard stays in sync for local apps.
-- Paste → pbpaste (perfect locally; over SSH paste arrives via the terminal's
--         bracketed paste anyway — OSC 52 paste QUERIES hang on most terminals).
do
  local osc52 = require("vim.ui.clipboard.osc52")
  local has_pb = vim.fn.executable("pbcopy") == 1
  local function copy_everywhere(reg)
    local osc_copy = osc52.copy(reg)
    return function(lines, regtype)
      osc_copy(lines, regtype)
      if has_pb then
        vim.fn.system({ "pbcopy" }, table.concat(lines, "\n"))
      end
    end
  end
  local function reg_paste() -- Linux fallback: paste from the unnamed register
    return { vim.split(vim.fn.getreg('"'), "\n"), vim.fn.getregtype('"') }
  end
  vim.g.clipboard = {
    name = "OSC 52 + pbcopy",
    copy = { ["+"] = copy_everywhere("+"), ["*"] = copy_everywhere("*") },
    paste = has_pb and { ["+"] = { "pbpaste" }, ["*"] = { "pbpaste" } }
      or { ["+"] = reg_paste, ["*"] = reg_paste },
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
