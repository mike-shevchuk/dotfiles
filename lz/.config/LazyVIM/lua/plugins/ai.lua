local codeium = {
  "Exafunction/windsurf.nvim",
  event = "InsertEnter", -- completion is only useful in insert mode
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
  cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions" },
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
  cmd = { "CursorAgent", "CursorAgentSelection", "CursorAgentBuffer" },
  -- <leader>a* AI namespace (off <leader>ca, which collides with LSP code-action).
  -- As lazy `keys` so the maps exist before the plugin loads.
  keys = {
    { "<leader>aa", "<cmd>CursorAgent<cr>", desc = "Cursor Agent: Toggle terminal" },
    { "<leader>as", ":CursorAgentSelection<CR>", mode = "v", desc = "Cursor Agent: Send selection" },
    { "<leader>ab", "<cmd>CursorAgentBuffer<cr>", desc = "Cursor Agent: Send buffer" },
  },
  opts = {},
}

return {
  codecomp,
  codeium,
  cursor,
}
