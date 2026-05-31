-- Canonical DiffView + Neogit spec (the git-review palette in command_pallet.lua
-- depends on these commands existing). Lazy-loaded on its commands and keys, so
-- it costs nothing at startup. Cross-platform — no OS-specific assumptions.
return {
  {
    "sindrets/diffview.nvim",
    cmd = {
      "DiffviewOpen",
      "DiffviewClose",
      "DiffviewToggleFiles",
      "DiffviewFocusFiles",
      "DiffviewRefresh",
      "DiffviewLog",
      "DiffviewFileHistory",
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "TimUntersberger/neogit",
        cmd = "Neogit",
        opts = { disable_commit_confirmation = true },
      },
    },
    keys = {
      { "<C-g>", "<CMD>DiffviewOpen<CR>", mode = { "n", "i", "v" }, desc = "Diffview: Open" },
      { "<leader>gd", "<CMD>DiffviewOpen<CR>", mode = "n", desc = "Diffview: Open" },
    },
    opts = {
      -- In-view keymaps must be plain command strings or functions.
      keymaps = {
        view = {
          ["<C-g>"] = "<CMD>DiffviewClose<CR>",
          ["c"] = "<CMD>DiffviewClose | Neogit commit<CR>",
        },
        file_panel = {
          ["<C-g>"] = "<CMD>DiffviewClose<CR>",
          ["c"] = "<CMD>DiffviewClose | Neogit commit<CR>",
        },
      },
    },
  },
}
