local cmp_lsp = {
  "hrsh7th/cmp-nvim-lsp",
}

local compleate = {
  "hrsh7th/nvim-cmp",
  event = "InsertEnter",
  dependencies = {
    "hrsh7th/cmp-buffer", -- source for text in buffer
    "hrsh7th/cmp-path", -- source file system path
    "L3MON4D3/LuaSnip", -- snipe engine
    "saadparwaiz1/cmp-luasnip", -- for autocompletion
    "rafamadriz/friendly-snipets", -- usefull snipets

    "hrsh7th/cmp-nvim-lsp",
    "hrsh7th/cmp-nvim-lua",
    "hrsh7th/cmp-cmdline",
    -- "Exafunction/codeium.nvim",
  },

  config = function()
    local cmp = require("cmp")
    local luasnip = require("luasnip")

    require("luasnip.loaders.from_vscode").lazy_load()

    cmp.setup({
      completion = {
        completeopt = "menu,menuone,preview,noselect",
      },
      snippet = {
        expand = function(args)
          luasnip.lsp_expand(args.body)
        end,
      },
      mapping = cmp.mapping.preset.insert({
        ["C-k"] = cmp.mapping.select_prev_item(),
        ["C-j"] = cmp.mapping.select_next_item(),
        ["C-b"] = cmp.mapping.scroll_docs(-4),
        ["C-f"] = cmp.mapping.scroll_docs(4),
        ["C-Space"] = cmp.mapping.complete(),
        ["C-e"] = cmp.mapping.abort(),
        ["<CR>"] = cmp.mapping.confirm({ select = false }),
      }),
      sources = cmp.config.sources({
        { name = "luasnip" }, -- snipets
        { name = "buffer" }, -- text within current buffer
        { name = "path" }, -- file  system path
        { name = "codeium" },
      }),
      formatting = {
        fields = { "menu", "abbr", "kind" },
        format = function(entry, item)
          local menu_icon = {
            nvim_lsp = "λ",
            luasnip = "⋗",
            buffer = "Ω",
            path = "🖫",
          }

          item.menu = menu_icon[entry.source.name]

          return item
        end,
      },
    })
  end,
}

local cmp = {
  "hrsh7th/nvim-cmp",
  event = "InsertEnter",
  dependencies = {
    "hrsh7th/cmp-nvim-lsp",
    "hrsh7th/cmp-path",
    "hrsh7th/cmp-buffer",
    "hrsh7th/cmp-nvim-lua",
    "hrsh7th/cmp-cmdline",
    "saadparwaiz1/cmp-luasnip",
    "L3MON4D3/LuaSnip",
    "rafamadriz/friendly-snippets",
  },

  config = function()
    local cmp = require("cmp")
    local luasnip = require("luasnip")

    require("luasnip.loaders.from_vscode").lazy_load()

    cmp.setup({
      completion = {
        completeopt = "menu,menuone,noselect,noinsert",
      },
      snippet = {
        expand = function(args)
          luasnip.lsp_expand(args.body)
        end,
      },
      mapping = cmp.mapping.preset.insert({
        ["<C-j>"] = cmp.mapping.select_next_item(),
        ["<C-k>"] = cmp.mapping.select_prev_item(),
        ["<C-b>"] = cmp.mapping.scroll_docs(-4),
        ["<C-f>"] = cmp.mapping.scroll_docs(4),
        ["<C-Space>"] = cmp.mapping.complete(),
        ["<C-e>"] = cmp.mapping.abort(),
        ["<CR>"] = cmp.mapping.confirm({ select = false }),
      }),
      sources = cmp.config.sources({
        { name = "nvim_lsp" },
        { name = "luasnip" },
        { name = "buffer" },
        { name = "path" },
      }),
      formatting = {
        fields = { "abbr", "kind", "menu" },
        format = function(entry, item)
          local kind_labels = {
            Function = "Func",
            Variable = "Var",
            Class = "Class",
            Method = "Method",
            Snippet = "Snippet",
            Text = "Text",
            Keyword = "Keyword",
            Module = "Module",
          }

          local source_labels = {
            nvim_lsp = "LSP",
            luasnip = "Snippet",
            buffer = "Buffer",
            path = "Path",
          }

          local function truncate(str, max_len)
            return #str > max_len and str:sub(1, max_len - 1) .. "…" or str
          end

          item.kind = truncate(kind_labels[item.kind] or item.kind, 10)
          item.menu = truncate(source_labels[entry.source.name] or entry.source.name, 10)
          item.abbr = truncate(item.abbr, 30)

          return item
        end,
      },
    })

    cmp.setup.cmdline(":", {
      mapping = cmp.mapping.preset.cmdline(),
      sources = cmp.config.sources({
        { name = "path" },
        { name = "cmdline" },
      }),
    })
  end,
}

local merge_cmp = {
  "hrsh7th/nvim-cmp",
  event = "InsertEnter",
  dependencies = {
    "hrsh7th/cmp-nvim-lsp",
    "hrsh7th/cmp-nvim-lua",
    "hrsh7th/cmp-buffer",
    "hrsh7th/cmp-path",
    "hrsh7th/cmp-cmdline",
    "saadparwaiz1/cmp-luasnip", -- ✔️ corrected
    "L3MON4D3/LuaSnip",
  },

  config = function()
    local cmp = require("cmp")
    local luasnip = require("luasnip")

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
      mapping = cmp.mapping.preset.insert({
        ["<Up>"] = cmp.mapping.select_prev_item(),
        ["<Down>"] = cmp.mapping.select_next_item(),
        ["<C-u>"] = cmp.mapping.scroll_docs(-4),
        ["<C-d>"] = cmp.mapping.scroll_docs(4),
        ["<C-Space>"] = cmp.mapping.complete(),
        ["<C-e>"] = cmp.mapping.abort(),
        ["<CR>"] = cmp.mapping.confirm({ select = true }),

        -- Tab to expand snippets (optional)
        -- ["<Tab>"] = cmp.mapping(function(fallback)
        --   if cmp.visible() then
        --     cmp.select_next_item()
        --   elseif luasnip.expand_or_jumpable() then
        --     luasnip.expand_or_jump()
        --   else
        --     fallback()
        --   end
        -- end, { "i", "s" }),

        -- ["<S-Tab>"] = cmp.mapping(function(fallback)
        --   if cmp.visible() then
        --     cmp.select_prev_item()
        --   elseif luasnip.jumpable(-1) then
        --     luasnip.jump(-1)
        --   else
        --     fallback()
        --   end
        -- end, { "i", "s" }),
      }),
      formatting = {
        fields = { "kind", "abbr", "menu" }, -- Correct order
        format = function(entry, item)
          local kind_labels = {
            Text = "Text",
            Method = "Method",
            Function = "Function",
            Constructor = "Ctor",
            Field = "Field",
            Variable = "Variable",
            Class = "Class",
            Interface = "Iface",
            Module = "Module",
            Property = "Prop",
            Unit = "Unit",
            Value = "Value",
            Enum = "Enum",
            Keyword = "Keyword",
            Snippet = "Snippet",
            Color = "Color",
            File = "File",
            Reference = "Ref",
            Folder = "Folder",
            EnumMember = "EnumMem",
            Constant = "Const",
            Struct = "Struct",
            Event = "Event",
            Operator = "Op",
            TypeParameter = "TParam",
          }

          local source_labels = {
            nvim_lsp = "LSP",
            nvim_lua = "Lua",
            luasnip = "Snip",
            buffer = "Buffer",
            path = "Path",
          }

          -- Truncate helper
          local function truncate(str, max_len)
            return #str > max_len and str:sub(1, max_len - 1) .. "…" or str
          end

          item.abbr = truncate(item.abbr, 25)
          item.kind = truncate(kind_labels[item.kind] or item.kind or "", 12)
          item.menu = truncate(source_labels[entry.source.name] or entry.source.name, 10)

          return item
        end,
      },

      -- formatting = {
      --   fields = { "abbr", "menu", "kind" },
      --   format = function(entry, item)
      --     local source_labels = {
      --       nvim_lsp = "[LSP]",
      --       nvim_lua = "[Lua]",
      --       luasnip = "[Snip]",
      --       buffer = "[Buffer]",
      --       path = "[Path]",
      --     }
      --
      --     item.menu = source_labels[entry.source.name] or "[Other]"
      --     item.kind = item.kind or ""
      --     return item
      --   end,
      -- },
      --
      -- sources = cmp.config.sources({
      --   { name = "nvim_lsp", max_item_count = 10 },
      --   { name = "nvim_lua", max_item_count = 10 },
      --   { name = "luasnip" },
      --   { name = "buffer", max_item_count = 5 },
      --   { name = "path", max_item_count = 5 },
      -- }),

      experimental = {
        ghost_text = true,
      },
    })
  end,
}

return {
  -- compleate,
  -- cmp,
  merge_cmp,
  -- cmp_lsp,
}
