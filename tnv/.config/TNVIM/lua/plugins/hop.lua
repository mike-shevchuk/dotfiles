return  {
  "phaazon/hop.nvim",
  enable = true,
  keys = {    
    {"<C-f>", "<cmd>HopChar1<cr>", desc = "Find char 1"}
  },
  config = function()
    require("hop").setup({ keys = "etovxqpdygfblzhckisuran" })
  end,
}
