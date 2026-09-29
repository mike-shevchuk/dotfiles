-- Seamless split/pane navigation: nvim splits <-> tmux panes (Claude Code) with
-- ONE keystroke, no prefix. C-hjkl moves within nvim; at the edge of the nvim
-- layout it crosses into the adjacent tmux pane (e.g. the one running `claude`).
-- Needs the tmux counterpart binds (is_vim check) in ~/.tmux.conf.local.
-- Replaces the old plain :wincmd C-hjkl maps (removed from config/keymaps.lua).
return {
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  config = function()
    local ss = require("smart-splits")
    ss.setup({}) -- default at_edge = "wrap": crosses into the tmux pane at the edge

    -- Move focus (nvim split OR tmux pane)
    vim.keymap.set("n", "<C-h>", ss.move_cursor_left, { desc = "Focus split/pane left" })
    vim.keymap.set("n", "<C-j>", ss.move_cursor_down, { desc = "Focus split/pane down" })
    vim.keymap.set("n", "<C-k>", ss.move_cursor_up, { desc = "Focus split/pane up" })
    vim.keymap.set("n", "<C-l>", ss.move_cursor_right, { desc = "Focus split/pane right" })

    -- Resize (Alt-hjkl). kitty distinguishes these; harmless elsewhere.
    vim.keymap.set("n", "<M-h>", ss.resize_left, { desc = "Resize split left" })
    vim.keymap.set("n", "<M-j>", ss.resize_down, { desc = "Resize split down" })
    vim.keymap.set("n", "<M-k>", ss.resize_up, { desc = "Resize split up" })
    vim.keymap.set("n", "<M-l>", ss.resize_right, { desc = "Resize split right" })
  end,
}
