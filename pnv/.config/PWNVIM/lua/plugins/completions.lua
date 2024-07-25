return {
  {
    "hrsh7th/cmp-nvim-lsp"
  },
  {
    "L3MON4D3/LuaSnip",
    dependencies = {
      "saadparwaiz1/cmp_luasnip",
      "rafamadriz/friendly-snippets",
    },
  },
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-nvim-lua",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
      "saadparwaiz1/cmp_luasnip",
      "L3MON4D3/LuaSnip",
    },

    config = function()
      local cmp = require("cmp")
      require("luasnip.loaders.from_vscode").lazy_load()

      cmp.setup({
        snippet = {
          expand = function(args)
            require("luasnip").lsp_expand(args.body)
          end,
        },
        window = {
          completion = cmp.config.window.bordered(),
          documentation = cmp.config.window.bordered(),

        },
        mapping = cmp.mapping.preset.insert({
          ['<Up>'] = cmp.mapping.select_prev_item(select_opts),
          ['<Down>'] = cmp.mapping.select_next_item(select_opts),

          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),

          -- ["<Tab>"] = cmp.mapping(function(fallback)
          --   -- Hint: if the completion menu is visible select next one
          --   if cmp.visible() then
          --       cmp.select_next_item()
          --   elseif luasnip.expand_or_jumpable() then
          --     luasnip.expand_or_jump()
          --   elseif has_words_before() then
          --       cmp.complete()
          --   else
          --       fallback()
          --   end
          -- end, {"i",  "s" }), -- i - insert mode; s - select mode
          --
          -- ["<S-Tab>"] = cmp.mapping(function(fallback)
          --   if cmp.visible() then
          --       cmp.select_prev_item()
          --   elseif luasnip.jumpable( -1) then
          --       luasnip.jump( -1)
          --   else
          --       fallback()
          --   end
          -- end, { "i", "s" }),

        }),

        formatting = {
          -- Set order from left to right
          -- kind: single letter indicating the type of completion
          -- abbr: abbreviation of "word"; when not empty it is used in the menu instead of "word"
          -- menu: extra text for the popup menu, displayed after "word" or "abbr"
          fields = { 'abbr', 'menu', 'kind'},

          -- customize the appearance of the completion menu
          format = function(entry, vim_item)
              
              vim_item.menu = ({
                  nvim_lsp = '[Lsp]',
                  codeium = '[Codeium]',
                  nvim_lua = '[Lua]',
                  luasnip = '[Luasnip]',
                  buffer = '[File]',
                  path = '[Path]',
              })[entry.source.name]
              return vim_item
          end,
        },

        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "codeium", max_item_count = 10, keyword = 1, priority = 1000},
          { name = "nvim_lua" },
          { name = "luasnip" }, -- For luasnip users.
          { name = "path" },
          { name = "buffer" },

        }),
        
        experimental = {
          ghost_text = true,
        },

           



      })
    end,
  },
}
