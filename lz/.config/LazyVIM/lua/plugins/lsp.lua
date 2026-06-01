-- LSP — cross-platform (Linux + macOS).
-- Modern mason-lspconfig 2.x flow: NO `setup_handlers` (removed in 2.x).
-- We register global defaults with `vim.lsp.config` and let mason-lspconfig
-- auto-enable installed servers (`automatic_enable`, on by default).
return {
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {},
  },
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "mason-org/mason.nvim",
      "mason-org/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
      "ray-x/lsp_signature.nvim",
      "mrjones2014/legendary.nvim",
      "FeiyouG/commander.nvim",
    },
    config = function()
      local mason = require("mason")
      local mason_lspconfig = require("mason-lspconfig")
      local cmp_nvim_lsp = require("cmp_nvim_lsp")

      -- Servers we want installed + enabled, derived from the shared single
      -- source of truth (user/lsp_servers.lua) so the list can't drift from the
      -- startup health check. `ts_ls` is the current name for the TS server.
      local servers = vim.tbl_map(function(s)
        return s.lspconfig
      end, require("user.lsp_servers"))
      table.insert(servers, "ruff") -- python linter + formatter (not a hover/completion LSP)

      mason.setup()
      mason_lspconfig.setup({
        ensure_installed = servers,
        automatic_enable = true, -- enables installed servers via vim.lsp.enable
      })

      -- Global defaults applied to every server (capabilities for nvim-cmp).
      local capabilities = cmp_nvim_lsp.default_capabilities()
      vim.lsp.config("*", { capabilities = capabilities })

      -- Attach-time behaviour: signature hints. Runs for every server.
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("user_lsp_attach", { clear = true }),
        callback = function(args)
          local ok, sig = pcall(require, "lsp_signature")
          if ok then
            sig.on_attach({
              bind = true,
              handler_opts = { border = "rounded" },
              hint_prefix = "💡 ",
            }, args.buf)
          end
        end,
      })

      -- LSP actions surfaced in commander / legendary palettes (discoverable via
      -- <leader>fk / <leader>fi). These reference vim.lsp.buf.* which no-op
      -- cleanly outside an LSP buffer.
      local ok, commander = pcall(require, "commander")
      if ok then
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
          {
            keys = { "n", "[d" },
            cmd = function()
              vim.diagnostic.jump({ count = -1 })
            end,
            desc = "LSP: Prev Diagnostic",
          },
          {
            keys = { "n", "]d" },
            cmd = function()
              vim.diagnostic.jump({ count = 1 })
            end,
            desc = "LSP: Next Diagnostic",
          },
          { keys = { "n", "<leader>dl" }, cmd = vim.diagnostic.open_float, desc = "LSP: Show Line Diagnostic" },
        })
      end
    end,
  },
}
