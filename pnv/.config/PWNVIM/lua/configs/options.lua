vim.cmd("set expandtab")
vim.cmd("set tabstop=2")
vim.cmd("set softtabstop=2")
vim.cmd("set shiftwidth=2")
vim.cmd("set clipboard=unnamedplus")
vim.g.mapleader = " "
vim.g.background = "light"
-- vim.g.markdown_folding = 1,
-- vim.opt.swapfile = false

-- Navigate vim panes better
local st = vim.keymap.set
st('n', '<c-k>', ':wincmd k<CR>')
st('n', '<c-j>', ':wincmd j<CR>')
st('n', '<c-h>', ':wincmd h<CR>')
st('n', '<c-l>', ':wincmd l<CR>')

st('n', '<leader>h', ':nohlsearch<CR>')
vim.wo.number = true

