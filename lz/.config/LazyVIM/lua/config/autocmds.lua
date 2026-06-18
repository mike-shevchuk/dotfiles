-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- ── DiffView comfort colors — Tokyonight Night palette ──────────────────────
-- Chosen via the style lab (char-level · bright bg · line 92% / word 100%).
-- Re-applied on every :colorscheme so it survives theme swaps (<leader>ft).
-- Backgrounds are baked at 92% line intensity (mixed 8% toward the editor bg);
-- the *Text groups (changed spans) stay full strength for clear char-level diff.
local function diffview_comfort_hl()
  local set = vim.api.nvim_set_hl
  set(0, "DiffAdd", { bg = "#233b47" }) -- added line
  set(0, "DiffChange", { bg = "#233b47" }) -- changed line (whole-line bg)
  set(0, "DiffDelete", { bg = "#46262e" }) -- removed line
  set(0, "DiffText", { bg = "#61865a", fg = "NONE" }) -- changed chars (vimdiff)
  -- diffview's own two-tier char-level groups (enhanced_diff_hl = true):
  set(0, "DiffviewDiffAddText", { bg = "#61865a" }) -- added chars (new side)
  set(0, "DiffviewDiffDeleteText", { bg = "#a14f5f" }) -- removed chars (old side)
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("diffview_comfort_hl", { clear = true }),
  callback = diffview_comfort_hl,
})
diffview_comfort_hl() -- apply now (colorscheme is already set at this point)
