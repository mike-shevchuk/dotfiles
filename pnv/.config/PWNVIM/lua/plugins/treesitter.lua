return {
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
        auto_install = true,
      })
    end
  }
}
