
local mason = {
  "williamboman/mason.nvim",
  -- overrides `require("mason").setup(...)`

  opts = function(_, opts)
    -- add more things to the ensure_installed table protecting against community packs modifying it
    opts.ensure_installed = require("astronvim.utils").list_insert_unique(opts.ensure_installed, {
      "stylua",
      -- "shellcheck",
      "beautysh",
      -- "shfmt",
      "flake8",
      "black",
      "isort",
      "prettier",
    })
  end,
}

local log_syntax = {
  'fei6409/log-highlight.nvim',
  config = function()
    require('log-highlight').setup {}
  end,
}

local md_headers = {
  'AntonVanAssche/md-headers.nvim',
  version = '*',
  lazy = false,
  dependencies = {
    'nvim-lua/plenary.nvim',
    -- 'nvim-treesitter/nvim-treesitter',
  },
  config = function()
    require('md-headers').setup {}
  end,
}


local mason_null_ls = {
  -- use mason-null-ls to configure Formatters/Linter installation for null-ls sources

  "jay-babu/mason-null-ls.nvim",
  -- overrides `require("mason-null-ls").setup(...)`
  opts = function(_, opts)
    -- add more things to the ensure_installed table protecting against community packs modifying it
    opts.ensure_installed = require("astronvim.utils").list_insert_unique(opts.ensure_installed, {
      -- "prettier",
      -- "stylua",
    })
  end,
}



local mason_dap = {
  -- use mason-dap to configure DAP installations
  "jay-babu/mason-nvim-dap.nvim",
  -- overrides `require("mason-nvim-dap").setup(...)`
  opts = function(_, opts)
    -- add more things to the ensure_installed table protecting against community packs modifying it
    opts.ensure_installed = require("astronvim.utils").list_insert_unique(opts.ensure_installed, {
      -- "python",
    })
  end,
}

local highlight_args = {
    "m-demare/hlargs.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = true,
}


--
local luaSnip = {
  "L3MON4D3/LuaSnip",
  keys = function() return {} end,
}
-- then: setup supertab in cmp
local nvim_cmp = {
  "hrsh7th/nvim-cmp",
  event = {"BufRead", "BufNewFile"},
  dependencies = {
    "hrsh7th/cmp-emoji",
    "hrsh7th/cmp-nvim-lsp",
    "hrsh7th/cmp-buffer",
    "hrsh7th/cmp-path",
    "hrsh7th/cmp-cmdline",
    "saadparwaiz1/cmp_luasnip",
    "rafamadriz/friendly-snippets",
    "windwp/nvim-autopairs",
    "windwp/nvim-ts-autotag",
    "onsails/lspkind-nvim",
  },
  config = function()
    local cmp = require("cmp")
    local cmp_autopairs = require("nvim-autopairs.completion.cmp")
    local luasnip = require("luasnip")
    local lspkind = require("lspkind")

    require("nvim-autopairs").setup()

    cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())

    --load snippet
    require("luasnip.loaders.from_vscode").lazy_load()
    
    cmp.setup({
      snippet = {
        expand = function(args)
          luasnip.lsp_expand(args.body)
        end,
      },
      window = {
        completion = cmp.config.window.bordered(),
        documentation = cmp.config.window.bordered(),
      },
      mapping = {
        ["<C-p>"] = cmp.mapping.select_prev_item(),
        ["<C-n>"] = cmp.mapping.select_next_item(),
        -- ["<C-d>"] = cmp.mapping.scroll_docs(-4),
        -- ["<C-f>"] = cmp.mapping.scroll_docs(4),
        ["<C-Space>"] = cmp.mapping.complete(),
        ["C-c"] = cmp.mapping.close(),
        ["<C-e>"] = cmp.mapping.close(),
        ["<CR>"] = cmp.mapping.confirm({ select = true }),
        
        ["<Tab>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_next_item()
          elseif luasnip.expand_or_jumpable() then
            luasnip.expand_or_jump()
          else
            fallback()
          end
        end, { "i", "s" }),

        ["<S-Tab>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_prev_item()
          elseif luasnip.jumpable(-1) then
            luasnip.jump(-1)
          else
            fallback()
          end
        end, { "i", "s" }),
        
      },

      sources = cmp.config.sources({
        { name = "nvim_lsp", max_item_count = 10},
        { name = "luasnip", max_item_count = 5 },
        { name = "codeium", max_item_count = 5},
        { name = "buffer"},
        { name = "path", max_item_count = 5 },
        { name = "emoji", max_item_count = 3 },
        

    }),
      formatting = {
        expandable_indicator = true,
        format = lspkind.cmp_format({
          mode = "symbol_text",
          maxwidth = 100,
          ellipsis_char = "...",
          symbol_map ={
            codeium = "",
          },
        }),
      },


      experiremental = {
        ghost_text = true,
         
      },virtual
    })

  end,
}

local toggle_lsp = {
    'WhoIsSethDaniel/toggle-lsp-diagnostics.nvim',
    config = function()
      require('toggle_lsp_diagnostics').init({
        start_on = true,
        virtual_text= false,
        underline = false,
        signs = true,
        update_in_insert = true,
        severity_sort = true,
        float = {
          focusable = true,
          style = "minimal",
          border = "rounded",
          source = "always",
          header = "",
          prefix = "",
        },
      })
    end,
  }

  local hover = {
    "lewis6991/hover.nvim",
    config = function()
      require("hover").setup ({
        init = function()
          -- Require providers
          require("hover.providers.lsp")
          -- require('hover.providers.gh')
          -- require('hover.providers.gh_user')
          -- require('hover.providers.jira')
          -- require('hover.providers.man')
          -- require('hover.providers.dictionary')
        end,
        preview_opts = {
          border = 'single'
        },
        -- Whether the contents of a currently open hover window should be moved
        -- to a :h preview-window when pressing the hover keymap.
        preview_window = false,
        title = true,
        mouse_providers = {
          'LSP'
        },
        mouse_delay = 1000
      })


      -- Setup keymaps
      vim.keymap.set("n", "K", require("hover").hover, {desc = "hover.nvim"})
      vim.keymap.set("n", "gK", require("hover").hover_select, {desc = "hover.nvim (select)"})
      vim.keymap.set("n", "<C-p>", function() require("hover").hover_switch("previous") end, {desc = "hover.nvim (previous source)"})
      vim.keymap.set("n", "<C-n>", function() require("hover").hover_switch("next") end, {desc = "hover.nvim (next source)"})

      -- Mouse support
      -- vim.keymap.set('n', '<MouseMove>', require('hover').hover_mouse, { desc = "hover.nvim (mouse)" })
      -- vim.o.mousemoveevent = false
  end,
}


return { mason, mason_null_ls, mason_dap, nvim_cmp, luaSnip, toggle_lsp, hover, highlight_args, log_syntax, md_headers }
