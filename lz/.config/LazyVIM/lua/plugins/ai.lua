local codeium = {
  "Exafunction/windsurf.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "hrsh7th/nvim-cmp",
  },
  config = function()
    require("codeium").setup({})
  end,
}

local codecomp = {

  "olimorris/codecompanion.nvim",
  opts = {},
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  config = function()
    require("codecompanion").setup({

      adapters = {
        openai = function()
          return require("codecompanion.adapters").extend("openai", {
            schema = {
              model = {
                default = "gpt-4o",
              },
            },
          })
        end,
      },
      strategies = {
        chat = {
          adapter = "openai",
        },
        inline = {
          adapter = "openai",
        },
      },
    })
  end,
}

local cursor = {
  "xTacobaco/cursor-agent.nvim",
  config = function()
    require("cursor-agent").setup({})
    -- Moved off <leader>ca (which collides with LSP code-action) to the <leader>a* AI namespace.
    vim.keymap.set("n", "<leader>aa", ":CursorAgent<CR>", { desc = "Cursor Agent: Toggle terminal" })
    vim.keymap.set("v", "<leader>as", ":CursorAgentSelection<CR>", { desc = "Cursor Agent: Send selection" })
    vim.keymap.set("n", "<leader>ab", ":CursorAgentBuffer<CR>", { desc = "Cursor Agent: Send buffer" })
  end,
}

return {
  codecomp,
  codeium,
  cursor,
}
