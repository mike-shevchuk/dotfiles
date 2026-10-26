-- Claude Code in Neovim with Cursor-style hunk review (fork of coder/claudecode.nvim).
-- Spec from the plugin's lazyvim/claudecode.lua; buffer/selection keys moved to
-- <leader>aB / <leader>aS because cursor-agent (ai.lua) owns <leader>ab / <leader>as.
-- Review counter in the statusline lives in colors.lua (custom lualine config ignores opts).
return {
  "odiumuniverse/claudecode.nvim",
  name = "claudecode.nvim",
  dependencies = { "folke/snacks.nvim" },
  -- Not lazy on keys: a file Claude edited before a restart must come back under review as you open it.
  event = "VeryLazy",
  opts = {},
  keys = {
    { "<leader>a", "", desc = "+ai", mode = { "n", "v" } },
    { "<leader>at", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude" },
    { "<leader>am", "<cmd>ClaudeCode --permission-mode manual<cr>", desc = "Claude in Manual mode" },
    { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus Claude" },
    { "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "Resume Claude" },
    { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude" },
    { "<leader>aB", "<cmd>ClaudeCodeAdd %<cr>", desc = "Claude: Add current buffer" },
    { "<leader>aS", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Claude: Send selection" },
    { "<leader>aS", "<cmd>ClaudeCodeTreeAdd<cr>", desc = "Claude: Add file", ft = { "NvimTree", "neo-tree", "oil" } },
    { "<leader>ak", "<cmd>ClaudeCodeReview<cr>", desc = "Files waiting for review" },
    { "<leader>an", "<cmd>ClaudeCodeReviewNotes<cr>", desc = "Notes for Claude" },
    { "<M-z>", "<cmd>ClaudeCodeZen<cr>", desc = "Claude zen" },
  },
}
