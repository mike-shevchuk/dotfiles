local tterm = {
  "akinsho/nvim-toggleterm.lua",
  lazy = false,
  branch = "main",
  config = function()
    require("toggleterm").setup({
      close_on_exit = false,
      shell = vim.o.shell,
    })
  end,
  keys = {
    { "<leader>ta", "<cmd>ToggleTerm direction=float<CR>", desc = "terminal float" },
    { "<leader>tv", "<cmd>ToggleTerm direction=vertical<CR>", desc = "terminal vertical" },
    { "<leader>th", "<cmd>ToggleTerm direction=horizontal<CR>", desc = "terminal horizontal" },
    { "<leader>tw", "<cmd>ToggleTerm direction=tab<CR>", desc = "terminal tab" },
  },
}

local tmanager = {
  "ryanmsnyder/toggleterm-manager.nvim",
  dependencies = {
    "akinsho/nvim-toggleterm.lua",
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim", -- only needed because it's a dependency of telescope
  },
  config = function()
    local ttmanag = require("toggleterm-manager")
    local actions = ttmanag.actions
    require("toggleterm-manager").setup({
      -- actions = toggleterm_manager.actions,
      titles = {
        preview = "Preview", -- title of the preview buffer in telescope
        prompt = " Terminals", -- title of the prompt buffer in telescope
        results = "Results", -- title of the results buffer in telescope
      },
      results = {
        fields = { -- fields that will appear in the results of the telescope window
          "state", -- the state of the terminal buffer: h = hidden, a = active
          "space", -- adds space between fields, if desired
          "term_icon", -- a terminal icon
          "term_name", -- toggleterm's display_name if it exists, else the terminal's id assigned by toggleterm
        },
        separator = " ", -- the character that will be used to separate each field provided in results.fields
        term_icon = "", -- the icon that will be used for term_icon in results.fields
      },
      search = {
        field = "term_name", -- the field that telescope fuzzy search will use when typing in the prompt
      },
      sort = {
        field = "term_name", -- the field that will be used for sorting in the telesocpe results
        ascending = true, -- whether or not the field provided above will be sorted in ascending or descending order
      },
      mappings = { -- key mappings bound inside the telescope window
        i = {
          -- ["<CR>"] = { action = actions.toggle_term, exit_on_action = false }, -- toggles terminal open/closed
          ["<C-i>"] = { action = actions.create_term, exit_on_action = false }, -- creates a new terminal buffer
          ["<C-d>"] = { action = actions.delete_term, exit_on_action = false }, -- deletes a terminal buffer
          ["<C-r>"] = { action = actions.rename_term, exit_on_action = false }, -- provides a prompt to rename a terminal
          -- ["<C-t>"] = { action = actions.toggle_term, exit_on_action = false }, -- toggle_term
        },
      },
    })
  end,
}

local project_cli_terminal = {
  "dimaportenko/project-cli-commands.nvim",

  dependencies = {
    "akinsho/toggleterm.nvim",
    "nvim-telescope/telescope.nvim",
  },

  -- optional keymap config
  config = function()
    local OpenActions = require("project_cli_commands.open_actions")
    local RunActions = require("project_cli_commands.actions")
    local commander = require("commander")

    local config = {
      -- Key mappings bound inside the telescope window
      running_telescope_mapping = {
        ["<C-c>"] = RunActions.exit_terminal,
        ["<C-m>"] = RunActions.open_float,
        ["<C-v>"] = RunActions.open_vertical,
        ["<C-h>"] = RunActions.open_horizontal,
      },

      commander.add({
        { keys = "<C-;>", cmd = ":Telescope project_cli_commands open<cr>", desc = "Projrct terminal open" },
        -- {keys="<C-;>", cmd=":Telescope project_cli_commands running<cr>", desc="Projrct terminal running"},
      }),
      open_telescope_mapping = {
        { mode = "i", key = "<CR>", action = OpenActions.execute_script_vertical },
        { mode = "n", key = "<CR>", action = OpenActions.execute_script_vertical },
        { mode = "i", key = "<C-h>", action = OpenActions.execute_script },
        { mode = "n", key = "<C-h>", action = OpenActions.execute_script },
        { mode = "i", key = "<C-i>", action = OpenActions.execute_script_with_input },
        { mode = "n", key = "<C-i>", action = OpenActions.execute_script_with_input },
        { mode = "i", key = "<C-c>", action = OpenActions.copy_command_clipboard },
        { mode = "n", key = "<C-c>", action = OpenActions.copy_command_clipboard },
        { mode = "i", key = "<C-f>", action = OpenActions.execute_script_float },
        { mode = "n", key = "<C-f>", action = OpenActions.execute_script_float },
        { mode = "i", key = "<C-v>", action = OpenActions.execute_script_vertical },
        { mode = "n", key = "<C-v>", action = OpenActions.execute_script_vertical },
      },
    }

    require("project_cli_commands").setup(config)
  end,
}

local zellij = {
  "swaits/zellij-nav.nvim",
  lazy = true,
  event = "VeryLazy",
  keys = {
    { "<c-h>", "<cmd>ZellijNavigateLeftTab<cr>", { silent = true, desc = "navigate left or tab" } },
    { "<c-j>", "<cmd>ZellijNavigateDown<cr>", { silent = true, desc = "navigate down" } },
    { "<c-k>", "<cmd>ZellijNavigateUp<cr>", { silent = true, desc = "navigate up" } },
    { "<c-l>", "<cmd>ZellijNavigateRightTab<cr>", { silent = true, desc = "navigate right or tab" } },
  },
  opts = {},
}

local multiplexer = {
  "stevalkr/multiplexer.nvim",
  lazy = false,
  opts = {
    on_init = function()
      local multiplexer = require("multiplexer")

      vim.keymap.set("n", "<C-h>", multiplexer.activate_pane_left, { desc = "Activate pane to the left" })
      vim.keymap.set("n", "<C-j>", multiplexer.activate_pane_down, { desc = "Activate pane below" })
      vim.keymap.set("n", "<C-k>", multiplexer.activate_pane_up, { desc = "Activate pane above" })
      vim.keymap.set("n", "<C-l>", multiplexer.activate_pane_right, { desc = "Activate pane to the right" })

      vim.keymap.set("n", "<C-S-h>", multiplexer.resize_pane_left, { desc = "Resize pane to the left" })
      vim.keymap.set("n", "<C-S-j>", multiplexer.resize_pane_down, { desc = "Resize pane below" })
      vim.keymap.set("n", "<C-S-k>", multiplexer.resize_pane_up, { desc = "Resize pane above" })
      vim.keymap.set("n", "<C-S-l>", multiplexer.resize_pane_right, { desc = "Resize pane to the right" })
    end,
  },
}

return {
  -- project_cli_terminal,
  tterm,
  tmanager,
  -- multiplexer,
  zellij,
}
