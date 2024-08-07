return {
  {
    'kristijanhusak/vim-hybrid-material',
  },

  -- {
  --   'fei6409/log-highlight.nvim',
  --   enable=false,
  --   config = function()
  --     require('log-highlight').setup {
  --       filename = {
  --         'messages',
  --         'name',
  --       },
  --     }
  --   end,
  -- },

  -- Not work propperly
  -- {
  --   "icedman/nvim-textmate",
  --   config = function()
  --     require("nvim-textmate").setup({
  --       quick_load = true,
  --       theme_name = 'Dracula',
  --       -- override_colorscheme = false
  --     })
  --   end,
  -- },


  {
    "scottmckendry/cyberdream.nvim",
    lazy = false,
    -- priority = 1000,
  },

  {
    "catppuccin/nvim",
    lazy = false,
    name = "catppuccin",
    -- priority = 1000,
    config = function()
      vim.cmd.colorscheme "catppuccin-mocha"
    end
  },


  {
    "tjdevries/colorbuddy.nvim",
  },


  { "lukas-reineke/indent-blankline.nvim", main = "ibl", opts = {} },
  {
    "neanias/everforest-nvim",
  },
  { "EdenEast/nightfox.nvim", name= "nightfox", priority=1000 },
  { "catppuccin/nvim", name = "catppuccin", priority = 800 },
  {  "rebelot/kanagawa.nvim"},
  { "folke/lsp-colors.nvim"},
  {
    'nvim-zh/colorful-winsep.nvim',
    config = function()
        local winsep = require("colorful-winsep")
        -- local bg = require("vscode.colors").get_colors().vscBack
        winsep.setup({
           --  highlight = {
           --      fg = active_bg,
           --      bg = "#16161E",
           --      -- bg = bg
           --  },
           --  no_exec_files = {"NvimTree", "packer", "TelescopePrompt", "Alpha", "NvimTree"},
           --  -- Rounded corners gud
           --  symbols = { "─", "│", "╭", "╮", "╰", "╯" },
           --   -- Smooth moving switch
           --  smooth = true,
           --  anchor = {
           --    left = { height = 1, x = -1, y = -1 },
           --    right = { height = 1, x = -1, y = 0 },
           --    up = { width = 0, x = -1, y = 0 },
           --    bottom = { width = 0, x = 1, y = 0 },
           -- },
        })
      end
    },


    --  don't use (((
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
          'Statement', 'PreProc', 'Type', 'Underlined', 'Todo', 'String', 'Function',
          'Conditional', 'Repeat', 'Operator', 'Structure', 'LineNr', 'NonText',
          'SignColumn', 'CursorLine', 'CursorLineNr', 'StatusLine', 'StatusLineNC',
          'EndOfBuffer',
        },
        extra_groups = {}, -- table: additional groups that should be cleared
        exclude_groups = {}, -- table: groups you don't want to clear
      })
      vim.cmd('TransparentDisable')
    end
  },



  {
    "navarasu/onedark.nvim",
    config = function()
      require('onedark').setup  {
        -- Main options --
        style = 'cool', -- Default theme style. Choose between 'dark', 'darker', 'cool', 'deep', 'warm', 'warmer' and 'light'
        transparent = false,  -- Show/hide background
        term_colors = true, -- Change terminal color as per the selected theme style
        ending_tildes = false, -- Show the end-of-buffer tildes. By default they are hidden
        cmp_itemkind_reverse = false, -- reverse item kind highlights in cmp menu

        -- toggle theme style ---
        toggle_style_key = nil, -- keybind to toggle theme style. Leave it nil to disable it, or set it to a string, for example "<leader>ts"
        toggle_style_list = {'dark', 'darker', 'cool', 'deep', 'warm', 'warmer', 'light'}, -- List of styles to toggle between

        -- Change code style ---
        -- Options are italic, bold, underline, none
        -- You can configure multiple style with comma separated, For e.g., keywords = 'italic,bold'
        code_style = {
          comments = 'italic',
          keywords = 'none',
          functions = 'none',
          strings = 'none',
          variables = 'none'
        },

        -- Lualine options --
        lualine = {
          transparent = false, -- lualine center bar transparency
        },

        -- Custom Highlights --
        colors = {}, -- Override default colors
        highlights = {}, -- Override highlight groups

        -- Plugins Config --
        diagnostics = {
          darker = true, -- darker colors for diagnostic
          undercurl = true,   -- use undercurl instead of underline for diagnostics
          background = true,    -- use background color for virtual text
        },
      }
      -- require("onedark").load()
    end,
  },


  {


    'nvim-lualine/lualine.nvim',
    config = function()
      require('lualine').setup({

        options = {
          icons_enabled = true,
          theme = 'powerline_dark',
          component_separators = { left = '', right = ''},
          section_separators = { left = '', right = ''},
          disabled_filetypes = {
            statusline = {},
            winbar = {},
          },
          ignore_focus = {},
          always_divide_middle = true,
          globalstatus = false,
          refresh = {
            statusline = 1000,
            tabline = 1000,
            winbar = 1000,
          }
        },
        sections = {
          lualine_a = {'mode'},
          lualine_b = {'branch', 'diff', 'diagnostics'},
          lualine_c = {'filename'},
          lualine_x = {'fileformat', 'filetype'},
          -- show lang name in lualine short way
          lualine_y = {'progress'},
          lualine_z = {'location', 'os.date("%H:%M:%S %d-%m")'}
        },
        inactive_sections = {
          lualine_a = {},
          lualine_b = {},
          lualine_c = {'filename'},
          lualine_x = {'location'},
          lualine_y = {},
          lualine_z = {}
        },
        tabline = {},
        winbar = {},
        inactive_winbar = {},
        extensions = {}
      })
    end
  },
}
