local rng = {
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
}

-- Perfect
local barbar = {
    'romgrk/barbar.nvim',
    dependencies = {
      'lewis6991/gitsigns.nvim', -- OPTIONAL: for git status
      'nvim-tree/nvim-web-devicons', -- OPTIONAL: for file icons
    },
    init = function() vim.g.barbar_auto_setup = false end,
    opts = {
      -- lazy.nvim will automatically call setup for you. put your options here, anything missing will use the default:
      -- animation = true,
      -- insert_at_start = true,
      -- …etc.
    },
    version = '^1.0.0', -- optional: only update when a new 1.x version is released
}




local rngr = {
  "kevinhwang91/rnvimr",
  event = { "BufReadPost", "BufNewFile" },
  keys = { { "<leader>R", "<cmd>RnvimrToggle<cr>", desc = "Ranger file manager" } },
  init = function()
    vim.g.rnvimr_enable_picker = 1
    vim.g.rnvimr_border_attr = { fg = 3, bg = -1 }
    vim.g.rnvimr_shadow_winblend = 90
  end,
}


local other = {


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




}


local alpha = { "goolord/alpha-nvim", enabled = true }



return {
  rng,
  rngr,
  alpha,
  barbar,
  other,
}
