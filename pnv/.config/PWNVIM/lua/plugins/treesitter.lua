return {

  -- NOTE: perfetct, automatically highlighting other uses of the word under the cursor
  {
    "RRethy/vim-illuminate",
    config = function()
      require("illuminate").configure()
      vim.api.nvim_set_keymap(
        "n",
        "<leader>gn",
        ':lua require("illuminate").goto_next_reference()<CR>',
        { silent = true, noremap = true }
      )
      vim.api.nvim_set_keymap(
        "n",
        "<leader>gp",
        ':lua require("illuminate").goto_prev_reference()<CR>',
        { silent = true, noremap = true }
      )
    end,
  },



  {
    "OXY2DEV/markview.nvim",
    lazy = false,      -- Recommended
    -- ft = "markdown" -- If you decide to lazy-load anyway

    dependencies = {
      -- You will not need this if you installed the
      -- parsers manually
      -- Or if the parsers are in your $RUNTIMEPATH
      "nvim-treesitter/nvim-treesitter",

      "nvim-tree/nvim-web-devicons"
    }
  },


  {
      'fei6409/log-highlight.nvim',
      config = function()
          require('log-highlight').setup {}
      end,
  },



  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      local config = require("nvim-treesitter.configs")
      config.setup({
        auto_install = true,
        highlight = { enable = true },
        indent = { enable = true },

        context_commentstring = {
          enable = true,
          enable_autocmd = false,
        },
        ensure_installed = {
          'python',
          'lua',
          'markdown_inline',
          'markdown',
          'json',
          'yaml',
          'toml',
          'bash',
          'c',
          'cpp',
          'css',
          'html',
          'javascript',
          'jsdoc',
          'lua',
          'markdown',
          'markdown_inline',
          'python',
          'query',
          'regex',
          'rust',
          'scss',
          'sql',
          'tsx',
          'typescript',
          'vim',
          'vue',
          'yaml',
        },

        sync_install = false,
      })
    end
  }
}
