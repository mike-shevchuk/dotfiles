return {
  'renerocksai/telekasten.nvim',
  dependencies = {'nvim-telescope/telescope.nvim'},
  keys = {
    { "<leader>zZ", "<cmd>Telekasten panel<CR>", desc="Telekasten Panel", mode={'n'}},
    { "<leader>zt", "<cmd>Telekasten show_tags<CR>", desc="Telekasten show tags", mode={'n'}},
    { "<leader>zg", "<cmd>Telekasten search_notes<CR>", desc="Telekasten search notes", mode={'n'}},
    { "<leader>zd", "<cmd>Telekasten goto_today<CR>", desc="Telekasten go today notes", mode={'n'}},
    { "<leader>zz", "<cmd>Telekasten folow_links<CR>", desc="Telekasten follow links", mode={'n'}},
    { "<leader>zn", "<cmd>Telekasten new_note<CR>", desc="Telekasten create new note", mode={'n'}},
    { "<leader>zc", "<cmd>Telekasten show_calendar<CR>", desc="Telekasten calendar", mode={'n'}},
    { "<leader>zb", "<cmd>Telekasten show_backlinks<CR>", desc="Telekasten backlinks", mode={'n'}},
    { "<leader>zI", "<cmd>Telekasten insert_img_link<CR>", desc="Telekasten insert image", mode={'n'}},
  },

  config = function()
    -- require('legendary').setup({ extensions = { lazy_nvim = true } })
    require('telekasten').setup({
      home = vim.fn.expand("~/zettelkasten"), -- Put the name of your notes directory here
      dailies = vim.fn.expand("~/zettelkasten/comb-notes/daily_staff"), -- where our data files will be stored
      weeklies = vim.fn.expand("~/zettelkasten/comb-notes/weekly_staff"), -- where our data files will be stored 
      templates = vim.fn.expand("~/zettelkasten/comb-notes/trash"), -- Dir for our template files
      media_previewer = "viu-previewer",
      image_link_style = "markdown",
      -- media_previewer = "catimg-previewer",
      --
      -- 


    })
   
  
    -- Launch panel if nothing is typed after <leader>z
    -- vim.keymap.set("n", "<leader>z", "<cmd>Telekasten panel<CR>")

    -- Most used functions
    -- vim.keymap.set("n", "<leader>zf", "<cmd>Telekasten find_notes<CR>")
    -- vim.keymap.set("n", "<leader>zt", "<cmd>Telekasten show_tags<CR>")
    -- vim.keymap.set("n", "<leader>zg", "<cmd>Telekasten search_notes<CR>")
    -- vim.keymap.set("n", "<leader>zd", "<cmd>Telekasten goto_today<CR>")
    -- vim.keymap.set("n", "<leader>zz", "<cmd>Telekasten follow_link<CR>")
    -- vim.keymap.set("n", "<leader>zn", "<cmd>Telekasten new_note<CR>")
    -- vim.keymap.set("n", "<leader>zc", "<cmd>Telekasten show_calendar<CR>")
    -- vim.keymap.set("n", "<leader>zb", "<cmd>Telekasten show_backlinks<CR>")
    -- vim.keymap.set("n", "<leader>zI", "<cmd>Telekasten insert_img_link<CR>")

    -- Call insert link automatically when we start typing a link
    vim.keymap.set("i", "[[", "<cmd>Telekasten insert_link<CR>")
    
  end,
}

