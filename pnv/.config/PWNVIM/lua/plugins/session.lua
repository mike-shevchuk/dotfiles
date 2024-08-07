local tmux_session = {
  "sanathks/workspace.nvim",
  dependencies = {"nvim-telescope/telescope.nvim"}, 
  config = function()
  local workspace = require("workspace")
  local commander = require("commander")
    workspace.setup({
      workspaces = {
        { name = "Dotfiles", path = "~/dotfiles", keymap = {"<leader>sd"} }, 
        { name = "Hobby",     path = "~/myword",  keymap = { "<leader>sh" } },
        { name = "Work",    path = "~/JOB/LAB325", keymap = { "<leader>sw" } },
      }
    })
    commander.add({
      { keys = {"n", "<leader>ss"}, cmd = workspace.tmux_sessions, desc = "Tmux session" },
    })
  end,
}







return {
  tmux_session,
} 
