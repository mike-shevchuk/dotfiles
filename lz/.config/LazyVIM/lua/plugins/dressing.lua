-- dressing.nvim configuration — controls the popup size for ALL `vim.ui.select`
-- and `vim.ui.input` calls (legendary, code actions, rename, etc.).
-- Bigger popup so long entries (Try* / GitDiff* / ReviewPR*) fit comfortably.
return {
  {
    "stevearc/dressing.nvim",
    lazy = true,
    init = function()
      vim.ui.select = function(...)
        require("lazy").load({ plugins = { "dressing.nvim" } })
        return vim.ui.select(...)
      end
      vim.ui.input = function(...)
        require("lazy").load({ plugins = { "dressing.nvim" } })
        return vim.ui.input(...)
      end
    end,
    opts = {
      input = {
        enabled = true,
        default_prompt = "❯ ",
        win_options = { winblend = 0 },
        get_config = function()
          return { relative = "cursor" }
        end,
      },
      select = {
        enabled = true,
        backend = { "telescope", "builtin" },
        telescope = {
          layout_strategy = "vertical",
          layout_config = {
            width = 0.85,
            height = 0.85,
            preview_cutoff = 1,
            mirror = false,
            prompt_position = "top",
          },
          sorting_strategy = "ascending",
        },
        builtin = {
          win_options = { winblend = 0 },
          max_width = { 200, 0.9 },
          min_width = { 80, 0.6 },
          max_height = 0.9,
          min_height = { 20, 0.6 },
          relative = "editor",
        },
      },
    },
  },
}
