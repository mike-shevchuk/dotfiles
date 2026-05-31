-- Completion (nvim-cmp) + macros.
-- NOTE: diffview/neogit now live in their own canonical spec: plugins/diffview.lua.
-- The old duplicate cmp specs (compleate/cmp) were removed — this is the single
-- source of truth, with an ACTIVE `sources` list (previously commented out, which
-- silently disabled completion).

local macros = {
  "ecthelionvi/NeoComposer.nvim",
  dependencies = { "kkharji/sqlite.lua" },
  opts = {},
}

local cmp = {
  "hrsh7th/nvim-cmp",
  event = "InsertEnter",
  dependencies = {
    "hrsh7th/cmp-nvim-lsp",
    "hrsh7th/cmp-nvim-lua",
    "hrsh7th/cmp-buffer",
    "hrsh7th/cmp-path",
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
        ["<C-k>"] = cmp.mapping.select_prev_item(),
        ["<C-j>"] = cmp.mapping.select_next_item(),
        ["<C-u>"] = cmp.mapping.scroll_docs(-4),
        ["<C-d>"] = cmp.mapping.scroll_docs(4),
        ["<C-Space>"] = cmp.mapping.complete(),
        ["<C-e>"] = cmp.mapping.abort(),
        ["<CR>"] = cmp.mapping.confirm({ select = false }),
      }),
      -- The fix: an ACTIVE source list. Order = priority.
      sources = cmp.config.sources({
        { name = "nvim_lsp" },
        { name = "nvim_lua" },
        { name = "luasnip" },
        { name = "buffer" },
        { name = "path" },
      }),
      formatting = {
        fields = { "kind", "abbr", "menu" },
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
          local function truncate(str, max_len)
            return #str > max_len and str:sub(1, max_len - 1) .. "…" or str
          end
          item.abbr = truncate(item.abbr, 25)
          item.kind = truncate(kind_labels[item.kind] or item.kind or "", 12)
          item.menu = truncate(source_labels[entry.source.name] or entry.source.name, 10)
          return item
        end,
      },
      experimental = {
        ghost_text = true,
      },
    })

    -- `:` command-line completion.
    cmp.setup.cmdline(":", {
      mapping = cmp.mapping.preset.cmdline(),
      sources = cmp.config.sources({
        { name = "path" },
        { name = "cmdline" },
      }),
    })
  end,
}

return {
  cmp,
  macros,
}
