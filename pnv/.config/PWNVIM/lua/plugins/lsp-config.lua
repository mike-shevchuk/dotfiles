local lsp_conf =   {
  "neovim/nvim-lspconfig",
  lazy = false,
  config = function()

    local lspconfig = require("lspconfig")
    local commander = require("commander")
    local lsp_buf = vim.lsp.buf


  -- Define a function to setup LSP servers with common capabilities
    local function setup_lsp_server(server_name)
      local capabilities = require('cmp_nvim_lsp').default_capabilities()
      lspconfig[server_name].setup({
        capabilities = capabilities
      })
    end

    setup_lsp_server("tsserver")
    setup_lsp_server("pyright")
    setup_lsp_server("solargraph")
    setup_lsp_server("html")
    setup_lsp_server("lua_ls")

    -- lspconfig.lua_ls.setup({})
    --
    -- lspconfig.tsserver.setup({
    --   capabilities = capabilities
    -- })
    -- lspconfig.solargraph.setup({
    --   capabilities = capabilities
    -- })
    -- lspconfig.html.setup({
    --   capabilities = capabilities
    -- })
    -- lspconfig.lua_ls.setup({
    --   capabilities = capabilities
    -- })
    -- lspconfig.pyright.setup({
    --   capabilities = capabilities
    -- })
    --
    commander.add({
        { keys = {"n", "K"},  cmd = lsp_buf.hover, desc = "lsp hoover" },
        { keys = {"n", "<leader>gd"},  cmd = lsp_buf.definition, desc = "lsp definition" },

        { keys = {"n", "<leader>gD"},  cmd = lsp_buf.declaration, desc = "lsp declaration" },
        { keys = {"n", "<leader>gr"},  cmd = lsp_buf.references, desc = "lsp references" },
        { keys = { {"n", "v"}, "<leader>ca"},  cmd = lsp_buf.code_action, desc = "lsp code_action" },

    })

    -- vim.keymap.set("n", "K", vim.lsp.buf.hover, {})
    -- vim.keymap.set("n", "<leader>gd", vim.lsp.buf.definition, {})
    -- vim.keymap.set("n", "<leader>gr", vim.lsp.buf.references, {})
    -- vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, {})
  end,
}

local lsp_zero = {
  'VonHeikemen/lsp-zero.nvim', 
  branch = 'v4.x',
  keys = {
    { '<leader>li', '<cmd>LspInfo<cr>', desc = 'Lsp Info'},
  }

}




return {
  {
    "williamboman/mason.nvim",
    lazy = false,
    config = function()
      require("mason").setup()
    end,
  },

  {
    "williamboman/mason-lspconfig.nvim",
    lazy = false,
    opts = {
      auto_install = true,
    },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = {
        -- Download lls servers
          "lua_ls", "bashls", "pyright", "html", "cssls", "jsonls"
        },
    })
    end,
  },


  lsp_conf,

}
