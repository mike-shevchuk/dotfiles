vim.keymap.set('n', 'ee', '<cmd>Neotree Toogle<CR>', { desc = "Neotree" })

-- local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', '<cmd>Telescope find_files<cr>', { desc="Find_files"})
vim.keymap.set('n', '<leader>fb', '<cmd>Telescope buffers<cr>', { desc="Find_buffers"})
vim.keymap.set('n', '<leader>fc', '<cmd>Telescope colorsheme<cr>', { desc="colorscheme" })
-- vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
-- vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
