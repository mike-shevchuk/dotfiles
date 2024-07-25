-- Plugin Manager: lazy.nvim
commander =  {
  "FeiyouG/commander.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
  keys = {
    { "<leader>fk", "<CMD>Telescope commander<CR>", mode = "n", desc="Telescope command pallet" },
    -- {
    --       "<leader>fl",
    --       mode = {"n"},
    --       desc = "Search inside current buffer",
    --       cmd = "<CMD>Telescope current_buffer_fuzzy_find<CR>",
    -- },
  },

  config = function()
    local commander = require("commander")
    commander.setup({
      components = {
        "DESC",
        "KEYS",
        "CAT",
        "CMD",
      },
      sort_by = {
        "DESC",
        "KEYS",
        "CAT",
        "CMD"
      },
      integration = {
        telescope = {
          enable = true,
        },
        lazy = {
          enable = true,
          set_plugin_name_as_cat = true
        }
      },
  
  })

  end,
}


legendary = {
  "mrjones2014/legendary.nvim",

  config = function()
    local leg = require("legendary")
    require("legendary").setup { include_builtin = true, auto_register_which_key = true }
    leg.keymap(keymap)
    leg.setup({
      keymaps = {
        -- map keys to a command
        -- { '<leader>ff', ':Telescope find_files<cr>', description = 'Telescope Find files' },
        { '<leader>fc', ':Telescope commands<cr>', description = 'Telescope commands pallete'},
        { '<leader>fl', "<CMD>Telescope current_buffer_fuzzy_find<CR>", mode={"n"}, desc = "Search inside current buffer"},
        { '<leader>fr', "<cmd>Telescope oldfiles<CR>", mode={"n"}, desc = "Telescope Recent files"},
        { '<leader>fs', "<cmd>Telescope session-lens<CR>", mode={"n"}, desc = "Telescope search session"},

        -- map keys to a function
      },
      commands = {
        -- easily create user commands
        {
          ':SayHello',
          function()
            print('hello world!')
          end,
          description = 'Say hello as a command',
        },

        {
          ':SNV',
          ':source $MYVIMRC<cr>',
          description = 'Reload nvim config',
          mode = 'n',
        },

        {
          ':CWD', 
          function()
            vim.cmd('Neotree focus reveal toggle show_hidden true')
          end,
          description = 'Toggle show hidden files',
          mode = {'n'}, 
        },

        {
          ':Cls',
          ':qa',
          desc = 'close all safe',
          mode = {'n'},
        },

        {
          ':Kll',
          ':qa!',
          desc = 'close all without saves',
          mode = {'n'},
        },

        { ':glow', description = 'preview markdown', filters = { ft = 'markdown' } },
        -- { ':cls', ':qa!', description = 'close without saves'},
      },

      extensions = {
        -- automatically load keymaps from lazy.nvim's `keys` option
        lazy_nvim = true,
        -- load keymaps and commands from nvim-tree.lua
        nvim_tree = true,
        -- which_key = true,
        -- load commands from smart-splits.nvim
        -- and create keymaps, see :h legendary-extensions-smart-splits.nvim
        smart_splits = {
          directions = { 'h', 'j', 'k', 'l' },
          mods = {
            move = '<C>',
            resize = '<M>',
          },
        },
        -- load commands from op.nvim
        op_nvim = true,
        -- load keymaps from diffview.nvim
        diffview = true,
      },

      -- which_key = {
      --   -- Automatically add which-key tables to legendary
      --   -- see ./doc/WHICH_KEY.md for more details
      --   auto_register = true,
      --   -- you can put which-key.nvim tables here,
      --   -- or alternatively have them auto-register,
      --   -- see ./doc/WHICH_KEY.md
      --   mappings = {},
      --   opts = {},
      --   -- controls whether legendary.nvim actually binds they keymaps,
      --   -- or if you want to let which-key.nvim handle the bindings.
      --   -- if not passed, true by default
      --   do_binding = true,
      --   -- controls whether to use legendary.nvim item groups
      --   -- matching your which-key.nvim groups; if false, all keymaps
      --   -- are added at toplevel instead of in a group.
      --   use_groups = true,
      -- },
      

    })
     -- load extensions
    
  end,

}



return {
  commander, legendary
}


