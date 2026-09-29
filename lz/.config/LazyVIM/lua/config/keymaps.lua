-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local st = vim.keymap.set

-- Independent maps — set these FIRST, before the commander guard, because they
-- don't depend on commander. Window navigation especially must survive even if
-- commander fails to load.
-- <C-hjkl> window/pane nav now owned by smart-splits.nvim (plugins/navigation.lua):
-- it moves between nvim splits AND crosses into tmux panes (Claude Code) seamlessly.
-- (Old plain :wincmd maps removed — they shadowed smart-splits.)
st("n", "<leader>md", "<cmd>NoiceDismiss<cr>", { desc = "Dismiss message" })

-- <leader>? / :Cheat — live keymap cheat-sheet. Dumps the REAL keymaps (those
-- with a desc) from nvim_get_keymap, grouped by <leader> namespace, into a
-- scrollable float. Generated from live maps → never goes stale (no hand-written
-- second source of truth). Inside: `/` search, j/k scroll, q/<Esc> close.
local function show_cheatsheet()
  local order = {
    { "z", "Zettelkasten" }, { "t", "Terminal" }, { "g", "LSP / Goto" },
    { "f", "Find / Palette" }, { "b", "Buffers" }, { "o", "Octo / GitHub" },
    { "a", "AI" }, { "v", "Python venv" }, { "d", "Diagnostics" },
    { "l", "LSP misc" }, { "r", "Rename / Reload" }, { "c", "Code action" },
    { "w", "Workspace" }, { "s", "Symbols" }, { "m", "Misc" },
  }
  -- keep only maps with a meaningful desc; drop nvim's built-in `:help …-default` noise.
  local function keep(d)
    return d and d ~= "" and not d:match("%-default$") and not vim.startswith(d, ":help")
  end
  local leader_groups, other, termins = {}, {}, {}
  for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
    if keep(m.desc) then
      local lhs = m.lhs
      if lhs:sub(1, 1) == " " and #lhs >= 2 then
        local g = lhs:sub(2, 2)
        leader_groups[g] = leader_groups[g] or {}
        table.insert(leader_groups[g], { lhs = "<leader>" .. lhs:sub(2), desc = m.desc })
      else
        table.insert(other, { lhs = lhs, desc = m.desc })
      end
    end
  end
  for _, mode in ipairs({ "t", "i" }) do
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
      if keep(m.desc) then
        table.insert(termins, { lhs = "[" .. mode .. "] " .. m.lhs, desc = m.desc })
      end
    end
  end

  local lines = { "  ⌨  KEYMAP CHEAT-SHEET   ( / search · j/k scroll · q close )", "" }
  local function section(title, items)
    if #items == 0 then
      return
    end
    table.sort(items, function(a, b)
      return a.lhs < b.lhs
    end)
    lines[#lines + 1] = "▍ " .. title
    for _, it in ipairs(items) do
      lines[#lines + 1] = string.format("   %-18s %s", it.lhs, it.desc)
    end
    lines[#lines + 1] = ""
  end

  local seen = {}
  for _, pair in ipairs(order) do
    local g = pair[1]
    if leader_groups[g] then
      section("<leader>" .. g .. "   " .. pair[2], leader_groups[g])
      seen[g] = true
    end
  end
  for g, items in pairs(leader_groups) do
    if not seen[g] then
      section("<leader>" .. g, items)
    end
  end
  section("Other keys (no <leader>)", other)
  section("Terminal / Insert mode", termins)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "help"
  local width = math.min(vim.o.columns - 8, 92)
  local height = math.min(vim.o.lines - 6, #lines)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " keymaps (live) ",
    title_pos = "center",
  })
  vim.wo[win].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder"
  vim.wo[win].cursorline = true
  for _, k in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", k, "<cmd>close<CR>", { buffer = buf, nowait = true, silent = true })
  end
end
vim.api.nvim_create_user_command("Cheat", show_cheatsheet, { desc = "Keymap cheat-sheet (live)" })
st("n", "<leader>?", show_cheatsheet, { desc = "Cheat-sheet — all keymaps (live)" })

-- commander is eager-loaded; guard anyway so a load-order change can't break
-- startup. Everything below this point depends on commander, so a clean return
-- here skips only the commander.add registrations — not the maps above.
local ok_commander, commander = pcall(require, "commander")
if not ok_commander then
  return
end

local get_input = function(prompt)
  local co = coroutine.running()
  assert(co, "must be running under a coroutine")

  vim.ui.input({ prompt = prompt .. ": " }, function(str)
    -- (2) the asynchronous callback called when user inputs something
    coroutine.resume(co, str)
  end)

  -- (1) Suspends the execution of the current coroutine, context switching occurs
  local input = coroutine.yield()

  -- (3) return the function
  return { input = input }
end

local wrapped_get_input = function()
  local x
  -- Execute get_input() inside a new coroutine.
  coroutine.wrap(function()
    x = get_input("Input >")
    vim.print("User input: " .. x.input)
  end)()
  return x or "NO RESULT SET"
end

local function rename_session()
  local new_session_name = ""

  -- Coroutine to handle user input
  coroutine.wrap(function()
    vim.ui.input({ prompt = "Enter new tmux session name: " }, function(input)
      if input then
        new_session_name = input
        -- Construct the tmux command to rename the current session
        local command = string.format("tmux rename-session %s", input)

        -- Execute the tmux command
        local result = os.execute(command)

        -- Check the result of the command execution
        if result == 0 then
          print(string.format("Successfully renamed the current tmux session to '%s'.", input))
        else
          print(string.format("Failed to rename the current tmux session to '%s'.", input))
        end
      else
        print("No input provided. Session name not changed.")
      end
    end)
  end)()

  return new_session_name
end

commander.add({
  {
    desc = "Legendary",
    keys = { "n", "<leader>fi" },
    cmd = "<cmd>Legendary<cr>",
  },

  -- {
  --   desc = "Legendary",
  --   keys = {
  --     { "i", "n", "t" },
  --     "<M-p>",
  --   },
  --   cmd = "<cmd>Legendary<cr>",
  -- },
  -- -- st('n', '<C-p>', '<cmd>Legendary<cr>', { desc='Command Pallete'})
  --
  {
    desc = "Exit Terminal Mode",
    keys = { "t", "<C-n>" },
    cmd = function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, true, true), "n", true)
    end,
  },

  {
    desc = "Go to normal mode",
    keys = { { "t", "i" }, "<C-j>" },
    cmd = function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, true, true), "n", true)
    end,
  },

  {
    desc = "Switch window in terminal mode",
    -- was "C-w" (no angle brackets) — bound the literal keys C,-,w instead of Ctrl-W
    keys = { "t", "<C-w>" },
    cmd = function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n><C-w>w", true, true, true), "n", true)
    end,
  },

  {
    desc = "the toogle terminal manager",
    keys = { { "i", "n", "t" }, "<C-t>" },
    cmd = "<cmd>Telescope toggleterm_manager<cr>",
  },

  -- (removed: Alpha on <C-H> — alpha-nvim isn't installed (commented out in
  --  utils.lua) so it errored, and <C-H> IS <C-h> in a terminal, colliding
  --  with window-nav-left)

  { desc = "The end of the line", keys = { { "i" }, "<C-e>" }, cmd = "<esc>A" },
  { desc = "The beg of the line", keys = { { "i" }, "<C-a>" }, cmd = "<esc>I" },

  { desc = "The end of the line", keys = { { "n" }, "<C-e>" }, cmd = "<esc>$" },
  { desc = "The beg of the line", keys = { { "n" }, "<C-a>" }, cmd = "<esc>^" },
})

commander.add({
  { keys = { "n", "<leader>bn" }, cmd = "<cmd>bn<cr>", desc = "next tab" },
  { keys = { "n", "<leader>bp" }, cmd = "<cmd>bp<cr>", desc = "previous tab" },
  { keys = { "n", "<leader>bd" }, cmd = "<cmd>bd<cr>", desc = "close tub" },

  -- { keys = { "n", "<leader>bn" }, cmd = "<cmd>tabnew<cr>", desc = "new tab" },
  -- { keys = { "n", "<leader>bP" }, cmd = "<cmd>tabp<cr>", desc = "previous tab" },
  -- { keys = { "n", "<leader>bN" }, cmd = "<cmd>tabnext<cr>", desc = "next tab" },
})

-- (window-nav + <leader>md maps moved to the top of the file, above the
-- commander guard, so they survive even if commander fails to load.)

-- st("n", "<leader>h", ":nohlsearch<CR>")

-- st('t', "<C-n>", "<C-\\><C-n><cr>", {desc = "Escape terminal mode"})
-- st('n', '<C-t>', '<cmd>Telescope toggleterm_manager<cr>', {desc= 'term manager'})
-- st('t', "<C-t>", "<C-\\><C-n><cmd>Telescope toggleterm_manager<cr>", { desc = "Toggle terminal mode" })

-- st('i', "<C-f>", "<cmd>HopChar1<cr>", {desc = "Find char"})
