local cmd=vim.cmd

cmd("set expandtab")
cmd("set tabstop=2")
cmd("set softtabstop=2")
cmd("set shiftwidth=2")
cmd("set clipboard=unnamedplus")
vim.g.mapleader = " "
vim.g.background = "light"
-- vim.g.markdown_folding = 1,
-- vim.opt.swapfile = false

-- vim.opt.foldmethod = "expr" -- default is "normal"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()" -- default is ""
vim.opt.foldenable = false --
vim.opt.foldmethod = "indent"
vim.opt.foldlevel = 99



-- vim.wo.number = true

