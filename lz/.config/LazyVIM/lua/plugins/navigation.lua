-- Seamless split/pane navigation: nvim splits <-> tmux panes (Claude Code) with
-- ONE keystroke, no prefix. C-hjkl moves within nvim; at the edge of the nvim
-- layout it crosses into the adjacent tmux pane (e.g. the one running `claude`).
-- Needs the tmux counterpart binds (is_vim check) in ~/.tmux.conf.local.
-- Replaces the old plain :wincmd C-hjkl maps (removed from config/keymaps.lua).
-- Maps live in `keys` (not config()): LazyVim's default keymaps load on VeryLazy
-- and skip only keys declared in a lazy `keys` spec — otherwise they'd overwrite
-- <C-hjkl> with plain <C-w>hjkl and <M-j>/<M-k> with "move line".
local function ss(fn)
  return function() require("smart-splits")[fn]() end
end

return {
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  opts = {}, -- default at_edge = "wrap": crosses into the tmux pane at the edge
  keys = {
    -- Move focus (nvim split OR tmux pane)
    { "<C-h>", ss("move_cursor_left"), desc = "Focus split/pane left" },
    { "<C-j>", ss("move_cursor_down"), desc = "Focus split/pane down" },
    { "<C-k>", ss("move_cursor_up"), desc = "Focus split/pane up" },
    { "<C-l>", ss("move_cursor_right"), desc = "Focus split/pane right" },
    -- Resize (Alt-hjkl). kitty distinguishes these; harmless elsewhere.
    { "<M-h>", ss("resize_left"), desc = "Resize split left" },
    { "<M-j>", ss("resize_down"), desc = "Resize split down" },
    { "<M-k>", ss("resize_up"), desc = "Resize split up" },
    { "<M-l>", ss("resize_right"), desc = "Resize split right" },
  },
}
