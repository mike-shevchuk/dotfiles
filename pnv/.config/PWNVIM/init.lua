local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("configs/options")
require("lazy").setup("plugins")

require("configs/mapping")
vim.cmd("colorscheme nightfox")

-- autocmd BufRead *.md set ft=markdown
-- vim.cmd('autocmd BufRead *.md set ft=markdown')
-- autocmd BufRead,BufNewFile *.md set filetype=markdown
--
vim.api.nvim_create_autocmd({"BufRead", "BufNewFile"}, {
  pattern = "*.md",
  command = "set filetype=markdown"
})
