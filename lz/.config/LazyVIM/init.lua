-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

require("user.lualine_tool")
require("user.health_check")

vim.cmd("colorscheme hybrid_material")
