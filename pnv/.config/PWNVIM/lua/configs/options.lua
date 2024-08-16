vim.cmd("set expandtab")
vim.cmd("set tabstop=2")
vim.cmd("set softtabstop=2")
vim.cmd("set shiftwidth=2")
vim.cmd("set clipboard=unnamedplus")
vim.g.mapleader = " "
vim.g.background = "light"
-- vim.g.markdown_folding = 1,
-- vim.opt.swapfile = false

-- vim.opt.foldmethod = "expr" -- default is "normal"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()" -- default is ""
vim.opt.foldenable = false --
vim.opt.foldmethod = "indent"
vim.opt.foldlevel = 99




vim.wo.number = true

