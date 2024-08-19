
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

	end
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

-- local codeium_nvim_2 = {
--   "Exafunction/u
-- }







local codeium_vim =  {
  'Exafunction/codeium.vim',
  -- event = 'BufEnter',
  config = function()
    require('codeium').setup({

    })
  end,
  -- vim.keymap.set('i', '<C-g>', function() return vim.fn['codeium#Accept']() end, { expr = true, silent = true }),
  -- vim.keymap.set('i', '<C-s>', function() return vim.fn['codeium#Reject']() end, { expr = true, silent = true }),
  -- vim.keymap.set('i', '<C-v>', function() return vim.fn['codeium#Complete']() end, { expr = true, silent = true }),
  -- vim.keymap.set('i', '<C-]>', function() return vim.fn['codeium#CycleCompletions'](1) end, { expr = true, silent = true }),
  -- vim.keymap.set('i', '<C-[>', function() return vim.fn['codeium#CycleCompletions'](-1) end, { expr = true, silent = true }),
  -- vim.keymap.set('i', '<C-x>', function() return vim.fn['codeium#Clear']() end, { expr = true, silent = true }),

}

return {
  gpt4, gpt3,
  -- codeium_nvim,
  codeium_vim
}
