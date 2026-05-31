-- Colorschemes + visual UI plugins.
--
-- ACTIVE theme = vim-hybrid-material (set once in init.lua). It is the only theme
-- loaded eagerly (priority 1000, lazy=false). Every OTHER theme is lazy=true:
-- lazy.nvim auto-loads a colorscheme plugin when you `:colorscheme` it (e.g. via
-- <leader>ft), so they cost nothing at startup but stay available. This removes
-- the old startup flicker where NeoSolarized + catppuccin + hybrid_material all
-- fought to set the colorscheme.
return {
  -- ── ACTIVE theme ──────────────────────────────────────────────────────────
  {
    "kristijanhusak/vim-hybrid-material",
    lazy = false,
    priority = 1000,
  },

  -- ── On-demand themes (loaded only when selected) ──────────────────────────
  { "cpea2506/one_monokai.nvim", lazy = true },
  { "Tsuzat/NeoSolarized.nvim", lazy = true },
  { "scottmckendry/cyberdream.nvim", lazy = true },
  { "catppuccin/nvim", name = "catppuccin", lazy = true },
  { "neanias/everforest-nvim", lazy = true },
  { "EdenEast/nightfox.nvim", name = "nightfox", lazy = true },
  { "rebelot/kanagawa.nvim", lazy = true },
  {
    "navarasu/onedark.nvim",
    lazy = true,
    opts = {
      style = "cool",
      code_style = { comments = "italic" },
      diagnostics = { darker = true, undercurl = true, background = true },
    },
  },
  { "tjdevries/colorbuddy.nvim", lazy = true }, -- library, loaded on demand
  { "folke/lsp-colors.nvim", event = "VeryLazy" },

  -- ── Visual UI (lazy where safe) ───────────────────────────────────────────
  {
    "folke/todo-comments.nvim",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {
      keywords = {
        ERROR = { icon = " ", color = "error", alt = { "ERROR", "FUCK" } },
        TASK = { icon = "", color = "warning", alt = { "TASK", "NOW" } },
      },
    },
  },

  {
    "gen740/SmoothCursor.nvim",
    event = "VeryLazy",
    config = function()
      require("smoothcursor").setup({
        type = "matrix",
        cursor = require("smoothcursor.matrix_chars"),
        texthl = "SmoothCursorGreen",
        linehl = nil,
        speed = 40,
        threshold = 1,
      })
    end,
  },

  { "lukas-reineke/indent-blankline.nvim", main = "ibl", event = "VeryLazy", opts = {} },

  {
    "nvim-zh/colorful-winsep.nvim",
    event = "VeryLazy",
    config = function()
      require("colorful-winsep").setup({})
    end,
  },

  -- Loaded only via :Transparent* commands (it disables itself anyway).
  {
    "xiyaowong/transparent.nvim",
    cmd = { "TransparentEnable", "TransparentDisable", "TransparentToggle" },
    opts = {},
  },

  -- ── Statusline (custom, cross-platform helpers in user/lualine_tool.lua) ──
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "justinhj/battery.nvim" }, -- battery must be ready before first render
    config = function()
      local tools = require("user.lualine_tool")
      require("lualine").setup({
        options = {
          icons_enabled = true,
          theme = "powerline_dark",
          component_separators = { left = "", right = "" },
          section_separators = { left = "", right = "" },
          disabled_filetypes = { statusline = {}, winbar = {} },
          ignore_focus = {},
          always_divide_middle = true,
          globalstatus = false,
          refresh = { statusline = 1000, tabline = 1000, winbar = 1000 },
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "branch", "diff", "diagnostics" },
          lualine_c = { "filename" },
          lualine_x = {
            "fileformat",
            "filetype",
            function()
              return tools.get_keyboard_layout()
            end,
          },
          lualine_y = {
            function()
              return tools.get_battery_status()
            end,
            function()
              return tools.get_sys_status()
            end,
          },
          lualine_z = {
            "progress",
            "location",
            'os.date("%H:%M:%S %d-%m")',
          },
        },
        inactive_sections = {
          lualine_a = {},
          lualine_b = {},
          lualine_c = { "filename" },
          lualine_x = { "location" },
          lualine_y = {},
          lualine_z = {},
        },
        tabline = {},
        winbar = {},
        inactive_winbar = {},
        extensions = {},
      })
    end,
  },
}
