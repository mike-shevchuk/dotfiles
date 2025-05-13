return {
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons",
    "MunifTanjim/nui.nvim",
  },
  config = function()
    local commander = require("commander")
    commander.add({
      { keys = { "n", "<leader>e" }, cmd = "<cmd>Neotree toggle filesystem reveal left<cr>", desc = "Neotree" },
      -- { keys={'n', '<leader>3'}, cmd='<cmd>cd %:h <CR>', desc='Change dir'},

      {
        keys = { "n", "<leader>3" },
        cmd = function()
          vim.cmd("cd %:h")
          print("change dir to ", vim.fn.getcwd())
        end,
        desc = "Change dir",
      },
    })
  end,
}
