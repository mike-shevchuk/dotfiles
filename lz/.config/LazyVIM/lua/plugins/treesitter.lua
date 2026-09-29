return {

  -- NOTE: perfetct, automatically highlighting other uses of the word under the cursor
  {
    "RRethy/vim-illuminate",
    event = { "BufReadPost", "BufNewFile" },
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
    ft = { "markdown", "md" }, -- lazy-load on markdown buffers only
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
  },


  {
    "fei6409/log-highlight.nvim",
    ft = "log",
    config = function()
      require("log-highlight").setup({})
    end,
  },



  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    opts = {
      auto_install = true,
      highlight = { enable = true },
      indent = { enable = true },
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
        'query',
        'regex',
        'rust',
        'scss',
        'sql',
        'tsx',
        'typescript',
        'vim',
        'vue',
      },
      sync_install = false,
    },
  }
}
