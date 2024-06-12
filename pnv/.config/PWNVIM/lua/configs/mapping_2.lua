local function search_file_telescope(path_arg)
  local cwd = path_arg
  if vim.fn.isdirectory(cwd) == 0 then
    vim.notify("No such directory: " .. cwd, vim.log.levels.ERROR)
    return
  end
  
  local search_dirs = {}
  table.insert(search_dirs, cwd)
  
  if vim.tbl_isempty(search_dirs) then
    utils.notify("No user configuration files found", vim.log.levels.WARN)
  else
    if #search_dirs == 1 then cwd = search_dirs[1] end
    require("telescope.builtin").find_files {
      prompt_title = "Search in learn dir",
      search_dirs = search_dirs,
      cwd = cwd,
      follow = true,
    }
  end
end

local function delete_whitespaces()
  vim.api.nvim_command(":%s/\\s\\+$//e")
end



local mappings = {
  n = {
    ["L"] = { function() require("astronvim.utils.buffer").nav(vim.v.count > 0 and vim.v.count or 1) end, desc = "Next buffer" },
    ["H"] = { function() require("astronvim.utils.buffer").nav(-(vim.v.count > 0 and vim.v.count or 1)) end, desc = "Previous buffer" },
    ["<C-e>"] = { "<esc>A", desc = "The end of the line" },
    ["<C-a>"] = { "<esc>I", desc = "The beginning of the line" },
    ["<leader>3"] = { ":Neotree left reveal<cr>", desc = "Change directory", silent = true, noremap = true },
    ["<leader>md"] = { ":NoiceDismiss<cr>", desc = "Dismiss message" },
    ["<leader>bD"] = { function() require("astronvim.utils.status").heirline.buffer_picker(function(bufnr) require("astronvim.utils.buffer").close(bufnr) end) end, desc = "Pick to close" },
    ["<leader>TR"] = { function() require("astronvim.utils").reload() end, desc = "Reload nvim" },
    ["<leader>b"] = { name = "Buffers" },
    ["<C-f>"] = { ":HopChar1<cr>", desc = "Find char", noremap = false, silent = false },
    ["<leader>T"] = { name = "Toggle" },
    ["<leader>TA"] = { ":AerialToggle<cr>", desc = "Aerial for navigation" },
    ["<leader>TC"] = { ":Cheatsheet<cr>", desc = "Toggle cheatsheet telescope" },
    ["<leader>TT"] = { ":TroubleToggle<cr>", desc = "TroubleToggle" },
    ["<leader>Tc"] = { desc = "Calendar and time" },
    ["<leader>Tct"] = { ":Calendar -view=clock <cr>", desc = "Toggle clock" },
    ["<leader>Tcc"] = { ":Calendar<cr>", desc = "Toggle Calendar" },
    ["<leader>TB"] = { ":DBUIToggle<cr>", desc = "Toggle DBUI" },
    ["<leader>Tl"] = { desc = "Lsp Diagnostic" },
    ["<leader>Tll"] = { ":ToggleDiag<cr>", desc = "Toggle lsp diagnostics" },
    ["<leader>Tm"] = { ":MarkdownHeaders<cr>", desc = "MarkdownHeaders" },
    ["<leader>Tn"] = { ":tabnew<cr>", desc = "Tab new" },
    ["<leader>tt"] = { ":ToggleTerm direction=tab<cr>", desc = "ToggleTerm in new tab" },
    ["<leader>tj"] = { ":%!jq .<cr>", desc = "Format json" },
    ["<leader>tw"] = { delete_whitespaces, desc = "Delete whitespaces" },
    ["<leader>TD"] = { desc = "Debugging" },
    ["<leader>TDD"] = { function() require("dapui").toggle() end, desc = "DAPUI Toggle" },
    ["<leader>TDc"] = { ":lua require'dap'.continue()<cr>", desc = "Continue" },
    ["<leader>TDo"] = { ":lua require'dap'.step_over()<cr>", desc = "Step over" },
    ["<leader>TDi"] = { ":lua require'dap'.step_into()<cr>", desc = "Step into" },
    ["<leader>TDt"] = { ":lua require'dap'.toggle_breakpoint()<cr>", desc = "Toggle breakpoint" },
    ["<leader>Tg"] = { desc = "GptChat" },
    ["<leader>Tgt"] = { ":GpChatToggle<cr>", desc = "Toggle chat" },
    ["<leader>Tgg"] = { ":GpChatFinder<cr>", desc = "Respond chat" },
    ["<leader>tr"] = { ":RunFile<cr>", desc = "Run current file" },
    ["<leader>N"] = { name = "Notice" },
    ["<leader>f."] = { name = "MyWorld" },
    ["<leader>fs"] = { ":Spectre<cr>", desc = "Replace characters" },
    ["<leader>f.c"] = { function() search_file_telescope('/home/mike/myworld/code/live_coding') end, desc = "Find my live_coding files", silent = true },
    ["<leader>f.l"] = { function() search_file_telescope('$HOME/myworld/code/learn') end, desc = "Find my learn file", silent = true },
  },
  t = {
    ["<C-b>"] = { "<C-\\><C-n><cr>", desc = "Escape terminal mode" },
    ["<C-n>"] = { "<C-\\><C-n><cr>", desc = "Escape terminal mode" },
    ["<C-t>"] = { "<C-\\><C-n>:ToggleTermAll<cr>", desc = "Toggle terminal mode" },
  },
  i = {
    ["<C-f>"] = { ":HopChar1<cr>", desc = "Find char", noremap = false, silent = false },
    ["<C-e>"] = { "<esc>A", desc = "The end of the line" },
    ["<C-a>"] = { "<esc>I", desc = "The beginning of the line" },
  },
}

