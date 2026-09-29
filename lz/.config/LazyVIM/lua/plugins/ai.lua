local codeium = {
  "Exafunction/windsurf.nvim",
  -- VeryLazy: off the startup path, but the language server is warm before the first insert.
  event = "VeryLazy",
  cmd = "Codeium",
  dependencies = { "nvim-lua/plenary.nvim" },
  -- nvim-cmp is disabled (LazyVim uses blink.cmp), so the cmp source would make setup() throw;
  -- show suggestions as inline virtual text instead.
  opts = { enable_cmp_source = false, virtual_text = { enabled = true } },
  config = function(_, opts)
    require("codeium").setup(opts)
  end,
}

local codecomp = {
  "olimorris/codecompanion.nvim",
  cmd = {
    "CodeCompanion",
    "CodeCompanionChat",
    "CodeCompanionActions",
    "CodeCompanionCmd",
    "CodeCompanionCLI",
    "CodeCompanionCodeReview",
  },
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
    { "<leader>as", ":CursorAgentSelection<CR>", mode = "x", desc = "Cursor Agent: Send selection" },
    { "<leader>ab", "<cmd>CursorAgentBuffer<cr>", desc = "Cursor Agent: Send buffer" },
  },
  config = function()
    require("cursor-agent").setup({})
    -- The plugin's after/plugin file maps global <leader>ca on load; drop it (LSP code-action lives there).
    pcall(vim.keymap.del, "n", "<leader>ca")
  end,
}

return {
  codecomp,
  codeium,
  cursor,
}
