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

    })
     -- load extensions
    
  end,

}



return {
  commander, legendary
}


