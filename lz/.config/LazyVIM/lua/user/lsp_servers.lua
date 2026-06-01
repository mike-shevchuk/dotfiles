-- Single source of truth for the LSP servers this config wants.
--
-- Both consumers derive from this list, so they can't drift:
--   • plugins/lsp.lua    → uses `lspconfig` names for mason `ensure_installed`
--   • user/health_check  → uses `mason_bin` names to detect what's installed
--     *before* lspconfig lazy-loads (it stats ~/.local/share/nvim/mason/bin).
--
-- `display` is the friendly language label shown in the health report.
return {
  { display = "lua", lspconfig = "lua_ls", mason_bin = "lua-language-server" },
  { display = "python", lspconfig = "pyright", mason_bin = "pyright-langserver" },
  { display = "go", lspconfig = "gopls", mason_bin = "gopls" },
  { display = "rust", lspconfig = "rust_analyzer", mason_bin = "rust-analyzer" },
  { display = "typescript/react", lspconfig = "ts_ls", mason_bin = "typescript-language-server" },
  { display = "html", lspconfig = "html", mason_bin = "vscode-html-language-server" },
  { display = "css", lspconfig = "cssls", mason_bin = "vscode-css-language-server" },
  { display = "json", lspconfig = "jsonls", mason_bin = "vscode-json-language-server" },
  { display = "yaml", lspconfig = "yamlls", mason_bin = "yaml-language-server" },
  { display = "bash", lspconfig = "bashls", mason_bin = "bash-language-server" },
  { display = "ruby", lspconfig = "ruby_lsp", mason_bin = "ruby-lsp" },
  { display = "docker", lspconfig = "dockerls", mason_bin = "docker-langserver" },
  { display = "markdown", lspconfig = "marksman", mason_bin = "marksman" },
  -- `ruff` (python linter/formatter) is installed but has no health entry —
  -- it's not a hover/completion LSP, so it's added directly in lsp.lua.
}
