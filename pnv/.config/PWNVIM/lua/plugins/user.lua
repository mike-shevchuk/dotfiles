return {
  {
    "petertriho/nvim-scrollbar",
    config = function()
      require("scrollbar").setup()
    end,
  },


  -- FIXME: delete or rewright
  -- TODO: make better
  -- NOTE: don't forget
  -- INFO: don't care
  -- WARN: don't worry 
  {  
    "AmeerTaweel/todo.nvim",
    requires = "nvim-lua/plenary.nvim",
    config = function()
      require("todo").setup {
        -- your configuration comes here
        -- or leave it empty to use the default settings
        -- refer to the configuration section below
      }
    end
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

  {
    "kelly-lin/ranger.nvim",
    config = function()
      require("ranger-nvim").setup({ replace_netrw = true })
      vim.api.nvim_set_keymap("n", "<leader>fe", "", {
        noremap = true,
        callback = function()
          require("ranger-nvim").open(true)
        end,
      })
    end,
  },

  {
    "kevinhwang91/rnvimr",
    event = { "BufReadPost", "BufNewFile" },
    keys = { { "<leader>R", "<cmd>RnvimrToggle<cr>", desc = "Ranger file manager" } },
    init = function()
      vim.g.rnvimr_enable_picker = 1
      vim.g.rnvimr_border_attr = { fg = 3, bg = -1 }
      vim.g.rnvimr_shadow_winblend = 90
    end,
  },





  { "goolord/alpha-nvim", enabled = true },

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
  
  -- NOTE: perfect
  {
    "yorickpeterse/nvim-window",
    keys = {
      { "<leader>j", "<cmd>lua require('nvim-window').pick()<cr>", desc = "nvim-window: Jump to window" },
    },
    config = true,
  },

  -- NOTE: search and replace very good
  {"nvim-pack/nvim-spectre",},
  

  -- sugestion panel automaticly 
  -- NOTE: perfetct
  {
    'gelguy/wilder.nvim',
    config = function()
      require('wilder').setup({
        modes = { ':', '/', '?' },
      })
    end,
  },

  -- NOTE: perfetct
  { 
    "anuvyklack/windows.nvim",
    dependencies = {
      "anuvyklack/middleclass",
      "anuvyklack/animation.nvim"
    },
    config = function()
      vim.o.winwidth = 10
      vim.o.winminwidth = 10
      vim.o.equalalways = false
      require('windows').setup()
      vim.keymap.set('n', '<C-w>z', ':WindowsMaximize<cr>')
      vim.keymap.set('n', '<C-w>V', ':WindowsMaximizeVertically<cr>')
      vim.keymap.set('n', '<C-w>H', ':WindowsMaximizeHorizontally<cr>')
      vim.keymap.set('n', '<C-w>=', ':WindowsEqualize<cr>')
    end
  },

  -- NOTE: perfetct
  { 
    'gen740/SmoothCursor.nvim',
    config = function()
      require('smoothcursor').setup({
        type='matrix',
        cursor = require('smoothcursor.matrix_chars'),              -- Cursor shape (requires Nerd Font). Disabled in fancy mode.:HopChar1
        texthl = "SmoothCursorGreen",   -- Highlight group. Default is { bg = nil, fg = "#FFD400" }. Disabled in fancy mode.
        linehl = nil,              -- Highlights the line under the cursor, similar to 'cursorline'. "CursorLine" is recommended. Disabled in fancy mode.
        speed = 40,
        threshold = 1,              -- Animate only if cursor moves more than this many lines
      })
    end,
  },

  { 
    'willthbill/opener.nvim',
    config = function()
      require('telescope').load_extension("opener")
      require('telescope').setup({
        extensions = {
          opener = {
            use_telescope = true,
            hidden = false, -- do not show hidden directories
            root_dir = "$HOME", -- search from home directory by default
            -- respect_gitignore = true, -- respect .gitignore files
          }
        }
      })
      require('opener').setup({
        pre_open = function(new_dir)
          print("Yay, opening " .. new_dir .. " in a moment")
        end,
        post_open = { "NeoTree", function(new_dir)
          print(new_dir .. " was opened")
        end },
      })
    -- TODO: add hiden files like find files 
    vim.api.nvim_set_keymap('n', '<Leader>fd', ":Telescope opener<CR>", { noremap = true })
          
    end
  }, 


  {
    "folke/noice.nvim",
    event = "VeryLazy",
    opts = {
      -- add any options here
    },
    dependencies = {
      -- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
      "MunifTanjim/nui.nvim",
      -- OPTIONAL:
      --   `nvim-notify` is only needed, if you want to use the notification view.
      --   If not available, we use `mini` as the fallback
      "rcarriga/nvim-notify",
    }
  },

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


