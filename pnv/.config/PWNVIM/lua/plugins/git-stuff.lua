return {
  {
    "tpope/vim-fugitive"
  },
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      local commander = require("commander")
      require("gitsigns").setup()

      commander.add({
        { keys = {"n", "<leader>gp"}, cmd="<cmd>Gitsigns preview_hunk<cr>",              desc = "git Preview_hunk", show=true },
        { keys = {"n", "<leader>gt"}, cmd="<cmd>Gitsigns toggle_current_line_blame<cr>", desc = "git toggle_current_line_blame", show=true },
      })
      vim.keymap.set("n", "<leader>gp", "", {})
      vim.keymap.set("n", "<leader>gt", ":Gitsigns toggle_current_line_blame<CR>", {})
    end
  }
}
