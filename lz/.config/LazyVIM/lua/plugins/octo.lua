return {
  {
    "pwntester/octo.nvim",
    cmd = "Octo",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    keys = {
      { "<leader>op", "<cmd>Octo pr list<cr>", desc = "Octo: PR list" },
      { "<leader>oe", ":Octo pr edit ", desc = "Octo: edit PR by number" },
      { "<leader>or", "<cmd>Octo review start<cr>", desc = "Octo: start review" },
      { "<leader>oR", "<cmd>Octo review submit<cr>", desc = "Octo: submit review" },
      { "<leader>oi", "<cmd>Octo issue list<cr>", desc = "Octo: issue list" },
    },
    opts = {
      enable_builtin = true,
      picker = "telescope",
    },
  },
}
