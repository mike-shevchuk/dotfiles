-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local st = vim.keymap.set

local leg = require("legendary")
local commander = require("commander")
-- local print = require("notify").print
-- leg.bind_whichkey(keymap, v_opts, false)
-- leg.bind_whichkey(keymap, opts, false)

local get_input = function(prompt)
  local co = coroutine.running()
  assert(co, "must be running under a coroutine")

  vim.ui.input({ prompt = prompt .. ": " }, function(str)
    -- (2) the asynchronous callback called when user inputs something
    coroutine.resume(co, str)
  end)

  -- (1) Suspends the execution of the current coroutine, context switching occurs
  local input = coroutine.yield()

  -- (3) return the function
  return { input = input }
end

local wrapped_get_input = function()
  local x
  -- Execute get_input() inside a new coroutine.
  coroutine.wrap(function()
    x = get_input("Input >")
    vim.print("User input: " .. x.input)
  end)()
  return x or "NO RESULT SET"
end

local function rename_session()
  local new_session_name = ""

  -- Coroutine to handle user input
  coroutine.wrap(function()
    vim.ui.input({ prompt = "Enter new tmux session name: " }, function(input)
      if input then
        new_session_name = input
        -- Construct the tmux command to rename the current session
        local command = string.format("tmux rename-session %s", input)

        -- Execute the tmux command
        local result = os.execute(command)

        -- Check the result of the command execution
        if result == 0 then
          print(string.format("Successfully renamed the current tmux session to '%s'.", input))
        else
          print(string.format("Failed to rename the current tmux session to '%s'.", input))
        end
      else
        print("No input provided. Session name not changed.")
      end
    end)
  end)()

  return new_session_name
end

commander.add({
  {
    desc = "Legendary",
    keys = { "n", "<leader>fi" },
    cmd = "<cmd>Legendary<cr>",
  },

  -- {
  --   desc = "Legendary",
  --   keys = {
  --     { "i", "n", "t" },
  --     "<M-p>",
  --   },
  --   cmd = "<cmd>Legendary<cr>",
  -- },
  -- -- st('n', '<C-p>', '<cmd>Legendary<cr>', { desc='Command Pallete'})
  --
  {
    desc = "Exit Terminal Mode",
    keys = { "t", "<C-n>" },
    cmd = function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, true, true), "n", true)
    end,
  },

  {
    desc = "Go to normal mode",
    keys = { { "t", "i" }, "<C-j>" },
    cmd = function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, true, true), "n", true)
    end,
  },

  {
    desc = "Switch window in terminal mode",
    keys = { "t", "C-w" },
    cmd = function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n><C-w>w", true, true, true), "n", true)
    end,
  },

  {
    desc = "the toogle terminal manager",
    keys = { { "i", "n", "t" }, "<C-t>" },
    cmd = "<cmd>Telescope toggleterm_manager<cr>",
  },

  {
    desc = "Alpha",
    cmd = function()
      require("alpha").start()
    end,
    keys = { { "n", "i" }, "<C-H>" },
  },

  { desc = "The end of the line", keys = { { "i" }, "<C-e>" }, cmd = "<esc>A" },
  { desc = "The beg of the line", keys = { { "i" }, "<C-a>" }, cmd = "<esc>I" },

  { desc = "The end of the line", keys = { { "n" }, "<C-e>" }, cmd = "<esc>$" },
  { desc = "The beg of the line", keys = { { "n" }, "<C-a>" }, cmd = "<esc>^" },
})

commander.add({
  { keys = { "n", "<leader>bn" }, cmd = "<cmd>bn<cr>", desc = "next tab" },
  { keys = { "n", "<leader>bp" }, cmd = "<cmd>bp<cr>", desc = "previous tab" },
  { keys = { "n", "<leader>bd" }, cmd = "<cmd>bd<cr>", desc = "close tub" },

  -- { keys = { "n", "<leader>bn" }, cmd = "<cmd>tabnew<cr>", desc = "new tab" },
  -- { keys = { "n", "<leader>bP" }, cmd = "<cmd>tabp<cr>", desc = "previous tab" },
  -- { keys = { "n", "<leader>bN" }, cmd = "<cmd>tabnext<cr>", desc = "next tab" },
})

st("n", "<leader>md", "<cmd>NoiceDismiss<cr>", { desc = "Dismiss message" })

-- Navigate vim panes better
-- local st = vim.keymap.set
st("n", "<c-k>", ":wincmd k<CR>")
st("n", "<c-j>", ":wincmd j<CR>")
st("n", "<c-h>", ":wincmd h<CR>")
st("n", "<c-l>", ":wincmd l<CR>")

-- st("n", "<leader>h", ":nohlsearch<CR>")

-- st('t', "<C-n>", "<C-\\><C-n><cr>", {desc = "Escape terminal mode"})
-- st('n', '<C-t>', '<cmd>Telescope toggleterm_manager<cr>', {desc= 'term manager'})
-- st('t', "<C-t>", "<C-\\><C-n><cmd>Telescope toggleterm_manager<cr>", { desc = "Toggle terminal mode" })

-- st('i', "<C-f>", "<cmd>HopChar1<cr>", {desc = "Find char"})
