local lsp_old = {
  "neovim/nvim-lspconfig",
  event = { "BufReadPre", "BufNewFile" },
  dependencies = {
    -- Mason installer
    "williamboman/mason.nvim",
    "williamboman/mason-lspconfig.nvim",
    -- Optional: auto-install for null-ls tools
    "jay-babu/mason-null-ls.nvim",

    -- Extra LSP enhancements
    "nvimtools/none-ls.nvim", -- null-ls
    "nvim-lua/plenary.nvim", -- needed for null-ls
    "j-hui/fidget.nvim", -- status UI
    "ray-x/lsp_signature.nvim", -- inline arg hints
    "folke/neodev.nvim", -- better Lua dev
  },

  config = function()
    -- === Setup core plugins ===
    require("mason").setup()
    require("fidget").setup()
    require("neodev").setup({})

    local lspconfig = require("lspconfig")
    local mason_lspconfig = require("mason-lspconfig")
    local null_ls = require("null-ls")
    local mason_null_ls = require("mason-null-ls")

    -- === Setup LSP servers ===
    local capabilities = require("cmp_nvim_lsp").default_capabilities()

    local servers = {
      lua_ls = {},
      pyright = {},
      tsserver = {},
      html = {},
      cssls = {},
      jsonls = {},
      yamlls = {},
      bashls = {},
      dockerls = {},
      marksman = {},
    }

    mason_lspconfig.setup({
      ensure_installed = vim.tbl_keys(servers),
      automatic_installation = true,
    })

    for name, opts in pairs(servers) do
      lspconfig[name].setup({
        capabilities = capabilities,
        settings = opts,
        on_attach = function(_, bufnr)
          require("lsp_signature").on_attach({
            bind = true,
            hint_prefix = "💡 ",
            handler_opts = { border = "rounded" },
          }, bufnr)
        end,
      })
    end

    -- === Setup Null-LS ===
    null_ls.setup({
      sources = {
        -- Formatters
        null_ls.builtins.formatting.prettier.with({
          filetypes = { "json", "yaml", "markdown", "html", "css", "javascript" },
        }),
        null_ls.builtins.formatting.black, -- python
        null_ls.builtins.formatting.stylua, -- lua

        -- Linters
        null_ls.builtins.diagnostics.flake8,
        null_ls.builtins.diagnostics.eslint,
      },
      on_attach = function(client, bufnr)
        if client.supports_method("textDocument/formatting") then
          vim.api.nvim_create_autocmd("BufWritePre", {
            buffer = bufnr,
            callback = function()
              vim.lsp.buf.format({ bufnr = bufnr })
            end,
          })
        end
      end,
    })

    -- Automatically install formatters/linters
    mason_null_ls.setup({
      ensure_installed = {
        "prettier",
        "stylua",
        "black",
        "flake8",
        "eslint_d",
      },
      automatic_installation = true,
    })
  end,
}

local merg_lsp = {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
      "ray-x/lsp_signature.nvim",
      "folke/neodev.nvim",
      "mrjones2014/legendary.nvim", -- or commander.nvim (your choice)
    },
    config = function()
      local lspconfig = require("lspconfig")
      local mason = require("mason")
      local mason_lspconfig = require("mason-lspconfig")
      local cmp_nvim_lsp = require("cmp_nvim_lsp")
      local commander = require("commander")

      mason.setup()
      mason_lspconfig.setup({
        ensure_installed = {
          "typescript-language-server", -- ✅ correct
          "lua_ls",
          "bashls",
          "pyright",
          "html",
          "cssls",
          "jsonls",
          "tsserver",
          "marksman",
        },
        automatic_installation = true,
      })

      require("neodev").setup({})

      local capabilities = cmp_nvim_lsp.default_capabilities()

      local function on_attach(_, bufnr)
        require("lsp_signature").on_attach({
          bind = true,
          handler_opts = { border = "rounded" },
          hint_prefix = "💡 ",
        }, bufnr)

        -- Register all LSP commands via commander
        commander.add({
          { keys = { "n", "K" }, cmd = vim.lsp.buf.hover, desc = "LSP: Hover" },
          { keys = { "n", "<leader>gd" }, cmd = vim.lsp.buf.definition, desc = "LSP: Go to Definition" },
          { keys = { "n", "<leader>gD" }, cmd = vim.lsp.buf.declaration, desc = "LSP: Go to Declaration" },
          { keys = { "n", "<leader>gi" }, cmd = vim.lsp.buf.implementation, desc = "LSP: Go to Implementation" },
          { keys = { "n", "<leader>gr" }, cmd = vim.lsp.buf.references, desc = "LSP: Find References" },
          { keys = { "n", "<leader>ca" }, cmd = vim.lsp.buf.code_action, desc = "LSP: Code Action" },
          { keys = { "n", "<leader>rn" }, cmd = vim.lsp.buf.rename, desc = "LSP: Rename Symbol" },
          { keys = { "n", "<leader>ds" }, cmd = vim.lsp.buf.document_symbol, desc = "LSP: Document Symbols" },
          { keys = { "n", "<leader>ws" }, cmd = vim.lsp.buf.workspace_symbol, desc = "LSP: Workspace Symbols" },
          -- Navigation like VSCode
          { keys = { "n", "<leader>g<" }, cmd = "<C-o>", desc = "LSP: Go Back (Jump List)" },
          { keys = { "n", "<leader>g>" }, cmd = "<C-i>", desc = "LSP: Go Forward (Jump List)" },

          {
            keys = { "n", "<leader>lf" },
            cmd = function()
              vim.lsp.buf.format({ async = true })
            end,
            desc = "LSP: Format File",
          },

          -- Diagnostics
          { keys = { "n", "[d" }, cmd = vim.diagnostic.goto_prev, desc = "LSP: Prev Diagnostic" },
          { keys = { "n", "]d" }, cmd = vim.diagnostic.goto_next, desc = "LSP: Next Diagnostic" },
          { keys = { "n", "<leader>dl" }, cmd = vim.diagnostic.open_float, desc = "LSP: Show Line Diagnostic" },
        })
      end

      -- Auto-setup all servers via mason
      mason_lspconfig.setup_handlers({
        function(server_name)
          lspconfig[server_name].setup({
            capabilities = capabilities,
            on_attach = on_attach,
          })
        end,
      })
    end,
  },
}

return {
  merg_lsp,
}
