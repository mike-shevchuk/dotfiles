return {
  {
    "nvim-telescope/telescope-ui-select.nvim",
  },


  {
    "otavioschwanck/arrow.nvim",
    config = function()
      require("arrow").setup({
        show_icons = true,
        leader_key = ';', -- Recommended to be a single key
        buffer_leader_key = 'm', -- Per Buffer Mappings
      })
    end
  },


  {
  "nvim-telescope/telescope-z.nvim",
  config = function()
    require("telescope").load_extension "z"
  end,
  },

  {
    'gelguy/wilder.nvim',
    config = function()
      -- config goes here
    end,
  },

  {
    "kdheepak/lazygit.nvim",
    cmd = {
      "LazyGit",
      "LazyGitConfig",
      "LazyGitCurrentFile",
      "LazyGitFilter",
      "LazyGitFilterCurrentFile",
    },
    -- optional for floating window border decoration
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    -- setting the keybinding for LazyGit with 'keys' is recommended in
    -- order to load the plugin when the command is run for the first time
    keys = {
      { "<leader>lg", "<cmd>LazyGit<cr>", desc = "LazyGit Test" }
    }
  },

  {
    "nvim-telescope/telescope.nvim",
    tag = "0.1.5",
    dependencies = { 
      "nvim-lua/plenary.nvim",
      'andrew-george/telescope-themes',
      'folke/noice.nvim',
      -- "nvim-telescope/telescope-frecency.nvim",
    }, 
    keys = {
      {
      "<leader>fg",
      -- require('telescope.buitin').live_grep,
      '<cmd>Telescope live_grep<cr>',
      desc = 'live grep',
      mode = "n"
      },
      {
        "<leader><leader>",
        '<cmd>Telescope oldfiles<cr>',
        desc = 'recent files',
        mode = "n"
      },
    },

    config = function()
      require("telescope").setup({
        defaults = {
          vimgrep_arguments = {
            'rg',
            '--color=never',
            '--no-heading',
            '--with-filename',
            '--line-number',
            '--column',
            '--smart-case',
            '--no-ignore', -- **This is the added flag**
            '--hidden' -- **Also this flag. The combination of the two is the same as `-uu`** 
          },
        },
        extensions = {
          ["ui-select"] = {
            require("telescope.themes").get_dropdown({}),
          },
          picker = {
            enable_preview = true,
            find_files = {
              hidden = true
            }
          },
        },
      })
      -- local builtin = require("telescope.builtin")
      -- vim.keymap.set("n", "<C-p>", builtin.find_files, {})
      -- vim.keymap.set("n", "<leader>fg", builtin.live_grep, {})
      -- vim.keymap.set("n", "<leader><leader>", builtin.oldfiles, {})

  

      require("telescope").load_extension("ui-select")
      require("telescope").load_extension('themes')
      require("telescope").load_extension("noice")
      -- require("telescope").load_extension("z")

      --  Has some bugs
      -- require("telescope").load_extension("frecency")
    end,
  },
}
