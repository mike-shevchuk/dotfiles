local st=vim.keymap.set

vim.keymap.set('n', 'e', '<cmd>Neotree Toogle<CR>', { desc = "Neotree" })

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
st('n', "<leader>ee", "<cmd>Neotree toggle<cr>", {desc="Neovim"})


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
