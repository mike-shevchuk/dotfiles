return {
  {
    "nvim-telescope/telescope-ui-select.nvim",
  },
  {
    'gelguy/wilder.nvim',
    config = function()
      -- config goes here
    end,
  },
  {
    "nvim-telescope/telescope.nvim",
    tag = "0.1.5",
    dependencies = { 
      "nvim-lua/plenary.nvim",
      'andrew-george/telescope-themes',
    },
    config = function()
      require("telescope").setup({
        defaults = {
          vimgrep_arguments = {
            'rg',
            '--color=never',
            '--no-heading',
            '--with-filename',
            '--line-number',
            '--column',
            '--smart-case',
            '--no-ignore', -- **This is the added flag**
            '--hidden' -- **Also this flag. The combination of the two is the same as `-uu`** 
          },
        },
        extensions = {
          ["ui-select"] = {
            require("telescope.themes").get_dropdown({}),
          },
          picker = {
            enable_preview = true,
            find_files = {
              hidden = true
            }
          },
        },
      })
      local builtin = require("telescope.builtin")
      -- vim.keymap.set("n", "<C-p>", builtin.find_files, {})
      vim.keymap.set("n", "<leader>fg", builtin.live_grep, {})
      vim.keymap.set("n", "<leader><leader>", builtin.oldfiles, {})

      require("telescope").load_extension("ui-select")
      require("telescope").load_extension('themes')
    end,
  },
}
