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





  -- NOTE:Check it
  { "folke/neodev.nvim", opts = {} },

  {
    "jiaoshijie/undotree",
    dependencies = "nvim-lua/plenary.nvim",
    config = true,
    keys = { -- load the plugin only when using it's keybinding:
    { "<leader>Tu", "<cmd>lua require('undotree').toggle()<cr>" },
  },
},

  -- NOTE: so good
  {
    'chentoast/marks.nvim',
    config = function()
      require('marks').setup({
        mappings = {
          set_next = "m,",
          next = "m]",
          prev = "m[",
          delete_line = "m-",
          delete = "md",
          toggle = "m`",
          preview = "m:",
          set_bookmark0 = "m0",
          prev = false -- pass false to disable only this default mapping
        },
        -- whether to map keybinds or not. default true
        default_mappings = true,
        -- which builtin marks to show. default {}
        builtin_marks = { ".", "<", ">", "^" },
        -- whether movements cycle back and forth between rows
        cyclic = true,
        -- whether the shada file is updated after modifying uppercase marks
        force_write_shada = false,
        -- how often (in ms) to redraw signs/recompute mark positions
        -- can be an interval
        refresh_interval = 250,
      })
    end

  },

  -- NOTE: Work fine  Rainbow Highlighting
  {"HiPhish/nvim-ts-rainbow2",},


  {"sindrets/diffview.nvim"},

  -- Plugin to diff different versions of a file
  {'will133/vim-dirdiff'},

  { 
    'anuvyklack/pretty-fold.nvim',
    config = function()
      require('pretty-fold').setup()
    end
  },

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

  { "CRAG666/code_runner.nvim", config = true },
  
   -- NOTE: perfetct, automatically highlighting other uses of the word under the cursor
  {
    "RRethy/vim-illuminate",
    config = function()
      require("illuminate").configure()
      vim.api.nvim_set_keymap(
      "n",
      "<leader>tN",
      ':lua require("illuminate").goto_next_reference()<CR>',
      { silent = true, noremap = true }
      )
      vim.api.nvim_set_keymap(
      "n",
      "<leader>P",
      ':lua require("illuminate").goto_prev_reference()<CR>',
      { silent = true, noremap = true }
      )
    end,
  },

 

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


