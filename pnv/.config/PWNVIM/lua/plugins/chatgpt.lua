
local gpt4 = {
    "jackMort/ChatGPT.nvim",
    cmd = { "ChatGPT", "ChatGPTRun", "ChatGPTActAs", "ChatGPTCompleteCode", "ChatGPTEditWithInstructions" },
    keys = {
      { "<leader>aa", "<cmd>ChatGPT<cr>", desc = "Chat" },
      { "<leader>ac", "<cmd>ChatGPTRun complete_code<cr>", mode = { "n", "v" }, desc = "Complete Code" },
      { "<leader>ae", "<cmd>ChatGPTEditWithInstructions<cr>", mode = { "n", "v" }, desc = "Edit with Instructions" },
    },
    opts = {},
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
    },
    config = function()
      require("chatgpt").setup({
      openai_api_key = os.getenv("GPT_TOKEN"),
      -- openai_params = {
      --     model = "gpt-4-1106-preview",
      --     max_tokens = 8192,
      --   },
      -- openai_edit_params = {
      --   model = "gpt-4-1106-preview",
      --   max_tokens = 128000,
      -- },
    })      
    end,
  }

local function get_alias_output()
  local file = io.popen('bw_lb_gpt4')
  local result = file:read('*a')
  file:close()
  vim.notify("openai_api_key: " .. result, vim.log.levels.INFO, { title = "GP Config" })
  print('OPENAI RESULT ---> ', result)
  return result
end

local gpt3 = {
  "robitx/gp.nvim",
  keys = {
    -- Invoke the GpChatToggle command
    { "<C-g>t", ":GpChatToggle<CR>",  desc = 'GP CHAT TOGGLE',  mode = { "n", "v" } },
    { "<C-g>n", ":GpChatNew<CR>",     desc = 'GP CHAT new ',  mode = { "n", "v" } },
    { "<C-g>r", ":GpRewrite<CR>",     desc = 'GP CHAT rewrite',  mode = { "v" } },
    -- { "<C-g>a", ":GpAppend<CR>",        mode = { "v" } },
    -- { "<C-g>d", "<cmd>GpChatDelete<CR>" },
    -- { "<C-g>f", "<cmd>GpChatFinder<CR>" },
  },

  config = function()
		require("gp").setup({
      openai_api_key = os.getenv("GPT_TOKEN"),
		})

	end,
  }


-- Autosugestion
local codeium_nvim = {
    "Exafunction/codeium.nvim",
    -- event = "BufEnter",
    -- enable = true,
    -- lazzy = false,
    dependencies = {
        "nvim-lua/plenary.nvim",
        "hrsh7th/nvim-cmp",
    },
    config = function()
        require("codeium").setup({})
    end,
}

local codeium_vim =  {
    'Exafunction/codeium.vim',
    event = 'BufEnter',
    keys = {
      {'<C-g>', '<cmd>Codeium<cr>', desc = 'Codeium', mode = {"n", "i"}},
      {'<C-]', '<cmd>CodeiumAccept<cr>', desc = 'Codeium accept', mode = {"i"}},
      {'<C-x>', '<cmd>CodeiumCancel<cr>', desc = 'Codeium cancel', mode = {"i"}},
      {'<C-s>', '<cmd>CodeiumReject<cr>', desc = 'Codeium reject', mode = {"i"}},
      {'<C-l>', '<cmd>CodeiumClear<cr>', desc = 'Codeium clear', mode ={"i"}},
      {'g]', '<cmd>CodeiumComplete<cr>', desc = 'Codeium complete', mode = {"n"}}, 
      {'gx', '<cmd>CodeiumRun<cr>', desc = 'Codeium run', mode = {"n"}},
    },
    init = function()
      -- Set up the Codeium mappings
      vim.g.codeium_disable_bindings = 1
      vim.keymap.set("i", "<C-g>", "<Cmd>Codeium<CR>", { silent = true, expr = true })
      vim.keymap.set("i", "<C-]>", "<Cmd>CodeiumAccept<CR>", { silent = true, expr = true })
      vim.keymap.set("i", "<C-x>", "<Cmd>CodeiumCancel<CR>", { silent = true, expr = true })
      vim.keymap.set("i", "<C-s>", "<Cmd>CodeiumReject<CR>", { silent = true, expr = true })
      vim.keymap.set("i", "<C-l>", "<Cmd>CodeiumClear<CR>", { silent = true, expr = true })
      vim.keymap.set("n", "g]", "<Cmd>CodeiumComplete<CR>", { silent = true })
      vim.keymap.set("n", "gx", "<Cmd>CodeiumRun<CR>", { silent = true })
  end,
}


return {gpt4, gpt3, 
  codeium_nvim, 
  codeium_vim
}
