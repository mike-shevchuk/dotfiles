return {
  "meatballs/notebook.nvim",
  enable = true,
  config = function(plugins, opts)
    local jupyter = require("notebook")
    jupyter.setup({
      -- Whether to insert a blank line at the top of the notebook
      insert_blank_line = true,

      -- Whether to display the index number of a cell
      show_index = true,

      -- Whether to display the type of a cell
      show_cell_type = true,

      -- Style for the virtual text at the top of a cell
      virtual_text_style = { fg = "lightblue", italic = true },
    })
  end,
}



