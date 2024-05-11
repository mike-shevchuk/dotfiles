-- Mapping data with "desc" stored directly by vim.keymap.set().
--
-- Please use this mappings table to set keyboard mapping since this is the
-- lower level configuration and more robust one. (which-key will
-- automatically pick-up stored data by this setting.)
--
function search_file_telescope(path_arg)
    -- local cwd = vim.fn.stdpath "config" .. "/.."
    -- local cwd = vim.fn.getcwd("$HOME/myworld/")
    local cwd = path_arg
    -- check is dir exists table insert else notify 
    if vim.fn.isdirectory(cwd) == 0 then
      vim.notify("No such directory: " .. cwd, vim.log.levels.ERROR)
      return
    end
    
    local search_dirs = {}
    table.insert(search_dirs, cwd)
    -- for _, dir in ipairs(astronvim.supported_configs) do -- search all supported config locations
    -- if dir == astronvim.install.home then dir = dir .. "/lua/user" end -- don't search the astronvim core files
    -- if vim.fn.isdirectory(dir) == 1 then table.insert(search_dirs, dir) end -- add directory to search if exists
    -- end
    if vim.tbl_isempty(search_dirs) then -- if no config folders found, show warning
      utils.notify("No user configuration files found", vim.log.levels.WARN)
    else
      if #search_dirs == 1 then cwd = search_dirs[1] end -- if only one directory, focus cwd
      require("telescope.builtin").find_files {
        prompt_title = "Search in learn dir",
        search_dirs = search_dirs,
        cwd = cwd,
        follow = true,
      } -- call Telescope
    end
  end

-- create method to delete whitespaces
function delete_whitespaces()
  vim.api.nvim_command(":%s/\\s\\+$//e")
end

return {
  -- first key is the mode
  n = {
    -- second key is the lefthand side of the map

    -- navigate buffer tabs with `H` and `L`
    L = {
    function() require("astronvim.utils.buffer").nav(vim.v.count > 0 and vim.v.count or 1) end,
    desc = "Next buffer",
    },
    H = {
    function() require("astronvim.utils.buffer").nav(-(vim.v.count > 0 and vim.v.count or 1)) end,
    desc = "Previous buffer",
    },

    
    ["<C-e>"] = { "<esc>A", desc = "The end of the line" },
    ["<C-a>"] = { "<esc>I", desc = "The begining of the line" },
    -- don't show in whichkey
    ["<leader>3"] = {
      ":Neotree left reveal<cr>", desc = "Change directory", silent = true, noremap = true
    },

    ["<leader>md"] = {":NoiceDismiss<cr>", desc = "Dismiss message"},


    -- mappings seen under group name "Buffer"
    ["<leader>bD"] = {
      function()
        require("astronvim.utils.status").heirline.buffer_picker(
          function(bufnr) require("astronvim.utils.buffer").close(bufnr) end
        )
      end,
      desc = "Pick to close",
    },

    ["<leader>TR"] = {
      function()
          require("astronvim.utils").reload()
          local hls_status = vim.v.hlsearch
          for name,_ in pairs(package.loaded) do
            if name:match('^cnull') then
              package.loaded[name] = nil
            end
          end

          dofile(vim.env.MYVIMRC)
          if hls_status == 0 then
            vim.opt.hlsearch = false
          end
          vim.notify("Nvim configuration reloaded!", vim.log.levels.INFO)
      end,
      desc = "Reload nvim"
    },
    
    -- tables with the `name` key will be registered with which-key if it's installed
    -- this is useful for naming menus
    ["<leader>b"] = { name = "Buffers" },
    -- quick save
    -- ["<C-s>"] = { ":w!<cr>", desc = "Save File" },  -- change description but the same command
      ["<C-f>"] = {":HopChar1<cr>", desc = "Find char", noremap = false, silent = false },
    -- ["<C-h>"] = { "<esc>:HopWord<cr>", desc = "Find line", noremap = false, silent = false },
    -- ["<C-f>"] = { "<esc>:HopAnywhere<cr>", desc = "Find line", noremap = false, silent = false },

    ["<leader>T"] = {name= "Toggle"},
    ["<leader>TA"] = { ":AerialToggle<cr>", desc = "Aerial for navigation"},
    -- ["<leader>TT"] = { ":Telekasten<cr>", desc = "Toggle terminal"},
    ["<leader>TC"] = { ":Cheatsheet<cr>", desc = "Toggle cheatsheet telescope"},
   
    ["<leader>TT"] = { ":TroubleToggle<cr>", desc = "TroubleToggle"},
    ["<leader>Tc"] = { desc="Calendar and time"},
    ["<leader>Tct"] = { ":Calendar -view=clock <cr>", desc = "Toggle clock"},
    ["<leader>Tcc"] = { ":Calendar<cr>", desc = "Toggle Calendar"},
    
    ["<leader>TB"] = { ":DBUIToggle<cr>", desc = "Toggle DBUI"},
    ["<leader>Tl"] = { desc="Lsp Diagnostic"},
    ["<leader>Tll"] = { ":ToggleDiag<cr>", desc = "Toggle lsp diagnostics"},
    ["<Leader>Tlt"] = { ":TroubleToggle<cr>", desc = "Toggle Trouble"},

    ["<leader>Tm"] = { ":MarkdownHeaders<cr>", desc = "MarkdownHeaders"},

    ["<leader>Tn"] = { ":tabnew<cr>", desc = "Tab new"},

    ["<leader>tt"] = { ":ToggleTerm direction=tab<cr>", desc = "ToggleTerm in new tab"},
    ["<leader>tj"] = { ":%!jq .<cr>", desc = "Format json"},
    ["<leader>tw"] = { "delete_whitespaces<cr>", desc = "Delete whitespaces"},


    ["<leader>TD"] = {desc = "Debuging"},

    ["<leader>TDD"] = {
      function()
        require("dapui").toggle()
        vim.notify("DAPUI Toggled!", vim.log.levels.INFO)
      end,
      desc = "DAPUI Tooggle"
    },

    ["<leader>TDc"] = { ":lua require'dap'.continue()<cr>", desc = "Continue"},
    ["<leader>TDo"] = { ":lua require'dap'.step_over()<cr>", desc = "Step over"},
    ["<leader>TDi"] = { ":lua require'dap'.step_into()<cr>", desc = "Step into"},
    ["<leader>TDt"] = { ":lua require'dap'.toggle_breakpoint()<cr>", desc = "Toggle breakpoint"},

    ["<leader>Tg"] = {desc = "GptChat"},
    ["<leader>Tgt"] = { ":GpChatToggle<cr>", desc = "Toggle chat"},
    ["<leader>Tgg"] = { ":GpChatFinder<cr>", desc = "Respond chat"},

    ["<leader>tr"] = { ":RunFile<cr>", desc = "Run cur file"},
    
    ["<leader>N"] = {name= "Notice"},

    -- find files in dir ~/myworld/  
    ["<leader>f."] = {name = "MyWorld"},
    -- ["<leader>fp"] = { ":Telescope live_grep search_dir='~/myworld/live_coding/'<cr>", desc = "Search files in live_codding"},
    ["<leader>fs"] = {":Spectre<cr>", desc = "Replace characters"},
    ["<leader>f.c"] = {
      "<cmd>lua search_file_telescope('/home/mike/myworld/code/live_coding')<cr>",
      desc = "Find my live_coding files",
      silent = true,
    },
    ["<leader>f.l"] = {
    "<cmd>lua search_file_telescope('$HOME/myworld/code/learn')<cr>",
    desc = "Find my learn file",
    silent = true,
    },
 
  },
  t = {
    -- setting a mapping to false will disable it
    -- ["<esc>"] = false,
    ["<C-b>"] = { "<C-\\><C-n><cr>", desc = "Escape terminal mode" },
    -- create hotkey to switch to normal mode
    ["<C-n>"] = { "<C-\\><C-n><cr>", desc = "Escape terminal mode" },
    -- create hotkey to toggle between normal and terminal mode
    ["<C-t>"] = { "<C-\\><C-n>:ToggleTermAll<cr>", desc = "Toggle terminal mode" },
    -- swith to another window
    -- ["<C-ww>"] = { "<C-\\><C-n><C-ww>", desc = "Switch to another window" },
  },
  i = {
    ["<C-f>"] = {":HopChar1<cr>", desc = "Find char", noremap = false, silent = false },
    -- ["<C-h>"] = { "<esc>:HopWord<cr>", desc = "Find line", noremap = false, silent = false },
    -- ["<C-w>"] = { "<esc>:HopAnywhere<cr>", desc = "Find line", noremap = false, silent = false },
    -- rewrite method to work with insert mode instead of normal mode 
    ["<C-e>"] = { "<esc>A", desc = "The end of the line" },
    ["<C-a>"] = { "<esc>I", desc = "The begining of the line" },
  },

  -- vim.api.nvim_set_keymap("n", "<C-e>","<esc>A")
}
