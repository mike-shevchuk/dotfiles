-- Helper function to search for the previous triple backtick and return its position
local function find_prev_backtick()
    vim.cmd('normal! ?```python\r')
    return vim.api.nvim_win_get_cursor(0)
end

-- Helper function to search for the next triple backtick and return its position
local function find_next_backtick()
    vim.cmd('normal! /```\r')
    return vim.api.nvim_win_get_cursor(0)
end

-- Helper function to select text between two positions
local function select_text(start_pos, end_pos)
    -- Move to the line after the starting position
    local start_line = start_pos[1] + 1
    local start_col = 0

    -- Move to the line before the ending position
    local end_line = end_pos[1] - 1
    local end_col = vim.api.nvim_buf_line_count(0)

    -- Select the text between the adjusted positions
    vim.api.nvim_win_set_cursor(0, {start_line, start_col})
    vim.cmd('normal! V')
    vim.api.nvim_win_set_cursor(0, {end_line, end_col})

end


-- Function to create a new cell above the current cell
local function CreateCellAbove()
    -- Save the current cursor position
    local start_pos = vim.api.nvim_win_get_cursor(0)

    -- Find the position of the previous ```python
    local prev_pos = find_prev_backtick()

    -- Insert a new cell above the current cell
    vim.api.nvim_buf_set_lines(0, prev_pos[1] - 1, prev_pos[1] - 1, true, {
        "",
        "```python",
        "",
        "```",
        "",
    })

    -- Restore the original cursor position
    vim.api.nvim_win_set_cursor(0, start_pos)
end


-- Function to create a new cell below the current cell
function CreateCellBelow()
    -- Save the current cursor position
    local start_pos = vim.api.nvim_win_get_cursor(0)

    -- Find the position of the next ```
    local next_pos = find_next_backtick()

    -- Insert a new cell below the current cell
    vim.api.nvim_buf_set_lines(0, next_pos[1] + 1, next_pos[1] + 1, true, {
        "```python",
        "",
        "```"
    })

    -- Restore the original cursor position
    vim.api.nvim_win_set_cursor(0, start_pos)
end


function MoveToPrevCell()
    -- Find the position of the previous ```python
    local prev_pos = find_prev_backtick()

    -- Move the cursor to the start of the previous cell
    vim.api.nvim_win_set_cursor(0, prev_pos)
end

-- Function to move to the next cell
function MoveToNextCell()
    -- Find the position of the next ```
    local next_pos = find_next_backtick()

    -- Move the cursor to the start of the next cell
    vim.api.nvim_win_set_cursor(0, next_pos)
end


local function SelectAndRunCell()
    -- Save the current cursor position
    local start_pos = vim.api.nvim_win_get_cursor(0)

    -- Find the positions of the previous and next triple backticks
    local prev_pos = find_prev_backtick()
    local next_pos = find_next_backtick()

    -- Select the text between the previous and next triple backticks
    select_text(prev_pos, next_pos)
    vim.cmd('normal! y')
    -- Run the selected text using MoltenEvaluateVisual
    vim.cmd('MoltenEvaluateVisual')

    -- Reselect the cell
    -- select_text(prev_pos, next_pos)

    -- Restore the original cursor position
    vim.api.nvim_win_set_cursor(0, start_pos)
end











-- Plugin Manager: lazy.nvim
local commander =  {
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
        -- "SET",
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

    commander.add({
-- add fucntion to run cell 
      { keys = {"n", "<leader>mm"}, cmd=function() SelectAndRunCell() end, desc = "Run cell", show=true },
      { keys = {"n", "<leader>mp"}, cmd=function() MoveToPrevCell() end, desc = "MoveToPrevCell", show=true },
      { keys = {"n", "<leader>mn"}, cmd=function() MoveToNextCell() end, desc = "MoveToNextCell", show=true },
    })

  end,
}









local legendary = {
  "mrjones2014/legendary.nvim",
  dependencies = { "kkharji/sqlite.lua", "stevearc/dressing.nvim" },

  config = function()
    local leg = require("legendary")
    require("legendary").setup { include_builtin = true, auto_register_which_key = true }
    -- local commander = require("commander")
    -- local commander_commands = commander.get_commands()

        -- leg.keymap(commander)
    -- leg.keymap(keymap)
    leg.setup({
      keymaps = {
        -- vim.g.legendary_keymaps,

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
          ':DeleteWhitespaces',
          function()
            print('Delete whitespaces in file')
            vim.api.nvim_command(":%s/\\s\\+$//e")

          end,
          description = 'Delete whitespaces',
          mode = {'n'},
        },





        {
        ':RunCell',
        function ()
          SelectAndRunCell()
        end,
        description = 'Select all cell',
        mode = {'n'},
        },

        {
          ':CreateCellAbove',
          function ()
            CreateCellAbove()
          end,
          description = 'Create cell above',
          mode = {'n'},
        },

        {
          ':CreateCellBelow',
          function ()
            CreateCellBelow()
          end,
          description = 'Create cell below',
          mode = {'n'},
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
        which_key = {
          auto_register = true,
          do_binding = true,
          use_groups = true,
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


