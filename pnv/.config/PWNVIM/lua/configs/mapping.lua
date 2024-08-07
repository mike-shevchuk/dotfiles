local st=vim.keymap.set


local leg = require("legendary")
local commander = require("commander")
-- local print = require("notify").print
-- leg.bind_whichkey(keymap, v_opts, false)
-- leg.bind_whichkey(keymap, opts, false)


local get_input = function(prompt)
    local co = coroutine.running()
    assert(co, "must be running under a coroutine")

    vim.ui.input({prompt = prompt .. ": "}, function(str)
        -- (2) the asynchronous callback called when user inputs something
        coroutine.resume(co, str)
    end)

    -- (1) Suspends the execution of the current coroutine, context switching occurs
    local input = coroutine.yield()

    -- (3) return the function
    return {input = input}
end

local wrapped_get_input = function()
    local x
    -- Execute get_input() inside a new coroutine.
    coroutine.wrap(
      function()
        x = get_input("Input >")
        vim.print("User input: " .. x.input)
      end
    )()
    return x or "NO RESULT SET"
end


local rename_session_2 = function()
    local new_session_name
      -- wrapped_get_input()
      --
      --
      coroutine.wrap(
        function()
          new_session_name = get_input("Enter new termux session")
          new_session_name = new_session_name.input
          vim.print("User input: " .. new_session_name)
        end
      )()
    return new_session_name or ""
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
    desc = "Test Neotree",
    keys = {"n", "<leader>fi"},
    cmd = "<cmd>Neotree toggle<cr>"
  },



  {
    desc = "Alpha",
    cmd = function()
      require("alpha").start()
    end,
    keys = {"n", "<leader>H"}
  },


  {
    desc = "Renamr this terminal seesion",
    keys = {"n", "<leader>sr"},
    cmd = function()
      local new_session_name = rename_session()
      if new_session_name ~= nil then
          os.execute("tmux rename-window " .. new_session_name)
          print("renamed tmux window to " .. new_session_name)
        else
          print("Enter new session name")
        end

      -- wrapped_get_input()
    end

   -- cmd =  function()
   --    local new_session_name
   --    coroutine.wrap(function()
   --      new_session_name = get_input("Enter new termux session")
   --      vim.print("User input: " .. new_session_name)
   --
   --    )
   --    local new_session_name = get_input("Enter new termux session")
   --    if new_session_name ~= nil then
   --      os.execute("tmux rename-wiindow " .. new_session_name)
   --      print("renamed tmux window to " .. new_session_name)
   --    else 
   --      print("Enter new session name")
   --
   --    end
   --
   --  end,
  },

})



-- leg.keymap = {
--   { '<leader>E', '<cmd>Neotree toggle<cr>', description = 'FUCK Neotree' },
-- }

-- local leg = require('legendary')

-- local leg.keymaps = {
--   { '<leader>E', '<cmd>Neotree toggle<cr>', desc = 'Neotree' },
-- }

-- vim.keymap.set('n', 'e', '<cmd>Neotree Toogle<CR>', { desc = "Neotree" })

st("n", "<leader>ff", '<cmd>Telescope find_files<cr>', { desc="Find files"})
st('n', '<leader>fh', '<cmd>Telescope find_files hidden=true no_ignore=true<cr>', { desc="Find_files"})
-- st('n', '<C-p>', '<cmd>Telescope commands<cr>', { desc='Command Pallete'})

st('n', '<C-p>', '<cmd>Legendary<cr>', { desc='Command Pallete'})
st('n', '<leader>fb', '<cmd>Telescope buffers<cr>', { desc="Find_buffers"})
st('n', '<leader>ft', '<cmd>Telescope themes<cr>', { desc="colorscheme" })
--

-- ["<leader>3"] = { ":Neotree left reveal<cr>", desc = "Change directory", silent = true, noremap = true },
-- st('n', "<leader>ee", "<cmd>Neotree toggle<cr>", {desc="Neovim"})
-- st('n', "<leader>3", "<cr>Neotree left reveal<cr>", {desk="Change directory", silent = true, noremap = true})




st('n', '<leader>md', '<cmd>NoiceDismiss<cr>', {desc = 'Dismiss message' })
st('n', "<leader>3", '<cmd>Neotree left reveal<cr>', {desc='Change directory'})
st('n', "<leader>e", "<cmd>Neotree toggle<cr>", {desc="Neovim"})




st('n', '<C-o>', '<cmd>Telescope toggleterm_manager<cr>', {desc= 'term manager'})


st('t', "<C-b>", "<C-\\><C-n><cr>", {desc = "Escape terminal mode"})
-- st('t', "<C-n>", "<C-\\><C-n><cr>", {desc = "Escape terminal mode"})
-- st('n', '<C-t>', '<cmd>Telescope toggleterm_manager<cr>', {desc= 'term manager'})
-- st('t', "<C-t>", "<C-\\><C-n><cmd>Telescope toggleterm_manager<cr>", { desc = "Toggle terminal mode" })
st('t', '<C-o>', '<C-\\><C-n><cmd>ToggleTermToggleAll<CR>', {desc= 'Term toggle'})



-- st('i', "<C-f>", "<cmd>HopChar1<cr>", {desc = "Find char"})
st('i', "<C-e>", "<esc>A", {desc = "The end of the line" })
st('i', "<C-a>", "<esc>I", {desc = "The beginning of the line" })


local toggleterm_manager = require("toggleterm-manager")
local actions = toggleterm_manager.actions

-- commander.add({
--   { keys = {{"i", "n"}, "<leader>Tc"}, cmd = actions.create_and_name_term, desc = 'create_and_name_term' },
--   { keys = {{"i", "n"}, "<leader>Td"}, cmd = actions.delete_term, desc = 'delete_term' },
--
-- })
--
commander.add({
  -- { keys = { "n", "<C-t>"}, cmd = "Telescope toggleterm_manager", desc="ToggleTermAll"},
  { keys = { "n", "<leader>tt"}, cmd = "<cmd>Telescope toggleterm_manager<cr>", desc="ToggleTermAll"},

})




toggleterm_manager.setup {
	mappings = {
	    i = {
	      ["<leader>Tc"] = { action = actions.create_and_name_term, exit_on_action = true },
	      ["<leader>Td"] = { action = actions.delete_term, exit_on_action = false },
	    },
	    n = {
	      ["<leader>Tc"] = { action = actions.create_and_name_term, exit_on_action = true },
	      ["<leader>Td"] = { action = actions.delete_term, exit_on_action = false },
	    },
	},
}


-- t = {
--     ["<C-b>"] = { "<C-\\><C-n><cr>", desc = "Escape terminal mode" },
--     ["<C-n>"] = { "<C-\\><C-n><cr>", desc = "Escape terminal mode" },
--     ["<C-t>"] = { "<C-\\><C-n>:ToggleTermAll<cr>", desc = "Toggle terminal mode" },
--   },
--   i = {
--     ["<C-f>"] = { ":HopChar1<cr>", desc = "Find char", noremap = false, silent = false },
--     ["<C-e>"] = { "<esc>A", desc = "The end of the line" },
--     ["<C-a>"] = { "<esc>I", desc = "The beginning of the line" },
--   },

-- 
--
--
--
--
--
