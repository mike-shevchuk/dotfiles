return {
  {
    "petertriho/nvim-scrollbar",
    config = function()
      require("scrollbar").setup()
    end,
  },


  --  Not use for now
  -- {
  --   "kndndrj/nvim-dbee",
  --   dependencies = {
  --     "MunifTanjim/nui.nvim",
  --   },
  --   build = function()
  --     -- Install tries to automatically detect the install method.
  --     -- if it fails, try calling it with one of these parameters:
  --     --    "curl", "wget", "bitsadmin", "go"
  --     require("dbee").install()
  --   end,
  --   config = function()
  --     require("dbee").setup(--[[optional config]])
  --   end,
  -- },

  -- {
  --   "vhyrro/luarocks.nvim",
  --   priority = 1000, -- Very high priority is required, luarocks.nvim should run as the first plugin in your config.
  --   opts = {
  --     rocks = { "fzy", "pathlib.nvim ~> 1.0" }, -- specifies a list of rocks to install
  --     -- luarocks_build_args = { "--with-lua=/my/path" }, -- extra options to pass to luarocks's configuration script
  --   }
  -- },



  -- NOTE:Check it
  { "folke/neodev.nvim", opts = {} },

  {
    'sindrets/winshift.nvim',
    config = true,
    keys = { -- load the plugin only when using it's keybinding:
      { "<leader>Tw", "<cmd>lua require('winshift').start_winshift()<cr>" },
    },

  },

  {
    "jiaoshijie/undotree",
    dependencies = "nvim-lua/plenary.nvim",
    config = true,
    keys = { -- load the plugin only when using it's keybinding:
      { "<leader>Tu", "<cmd>lua require('undotree').toggle()<cr>" },
    },
  },


  -- NOTE: Work fine  Rainbow Highlighting
  {"HiPhish/nvim-ts-rainbow2",},


  {"sindrets/diffview.nvim"},

  -- Plugin to diff different versions of a file
  {'will133/vim-dirdiff'},



  {
    'xiyaowong/transparent.nvim',
    config = function()
      require('transparent').setup({
        -- enable = false,
        -- NOTE:Case 1
        -- enable = true, -- boolean: enable transparent
        -- extra_groups = { -- table/string: additional groups that should be cleared
        --   -- In particular, list your own choice of groups
        --   -- 'BufferLineTabClose',
        --   -- 'BufferlineBufferSelected',
        --   -- 'BufferLineFill',
        --   -- 'BufferLineBackground',
        --   -- 'BufferLineSeparator',
        --   -- 'BufferLineIndicatorSelected',
        -- },
        -- exclude = {}, -- table: groups you don't want to clear

        groups = { -- table: default groups
          'Normal', 'NormalNC', 'Comment', 'Constant', 'Special', 'Identifier',
          'statement', 'PreProc', 'Type', 'Underlined', 'Todo', 'string', 'Function',
          'Conditional', 'Repeat', 'Operator', 'structure', 'LineNr', 'NonText',
          'SignColumn', 'CursorLine', 'CursorLineNr', 'statusLine', 'statusLineNC',
          'EndOfBuffer',
        },
        extra_groups = {}, -- table: additional groups that should be cleared
        exclude_groups = {}, -- table: groups you don't want to clear
      })
      vim.cmd('TransparentDisable')
    end
  },



  {
    "SmiteshP/nvim-navic",
    dependencies = "neovim/nvim-lspconfig",
  },

  -- NOTE: not need because has OVERseer 
  -- { "CRAG666/code_runner.nvim", config = true },



  -- NOTE: dont work normaly
  -- {
  --   "Praczet/encrypt-text.nvim",
  --   config = function()
  --     require("encrypt-text").setup({
  --       dir_path = '~/zettelkasten'
  --     })
  --   end
  -- },



  { "https://github.com/itchyny/calendar.vim.git"},

  {
    'cameron-wags/rainbow_csv.nvim',
    config = true,
    ft = {
      'csv',
      'tsv',
      'csv_semicolon',
      'csv_whitespace',
      'csv_pipe',
      'rfc_csv',
      'rfc_semicolon'
    },
    cmd = {
      'RainbowDelim',
      'RainbowDelimSimple',
      'RainbowDelimQuoted',
      'RainbowMultiDelim'
    }
  },
}
