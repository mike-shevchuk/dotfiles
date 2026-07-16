-- DiffView configuration override — show branch/rev labels above each pane.
-- Triggered by `prefix V/A/M/N/O` tmux popups via ~/dotfiles/tmux/scripts/git-compare.sh.
return {
  {
    "sindrets/diffview.nvim",
    opts = {
      -- Char-level (two-tier) diff highlighting: dims delete fill-chars and, in
      -- diff2, paints DiffviewDiffAddText / DiffviewDiffDeleteText on the exact
      -- changed spans. Diff colors themselves are set in config/autocmds.lua
      -- (Tokyonight Night palette, chosen via the style lab).
      enhanced_diff_hl = true,
      -- winbar shows the diff symbol (a/b) + the rev being viewed on each pane.
      -- Combined with nvim's default statusline, you get left=base@rev, right=HEAD@rev.
      view = {
        default = {
          -- winbar_info=false: diffview's own "sha:path" winbar re-sets itself on
          -- every file switch and clobbers custom labels — we fully own the winbar
          -- via the diff_buf_win_enter hook below (branch names, not bare SHAs).
          winbar_info = false,
          layout = "diff2_horizontal", -- left | right (true side-by-side)
        },
        merge_tool = {
          winbar_info = true,
        },
        file_history = {
          winbar_info = true,
        },
      },
      -- Keep the file panel visible by default so you see what's changed across files
      file_panel = {
        listing_style = "tree",
        win_config = {
          position = "left",
          width = 35, -- starting width; resize it live with the keymaps below or the mouse
        },
      },
      -- Make the left file panel resizeable. Mouse drag on the separator already
      -- works (tmux `mouse on` + nvim mouse=a), and native <C-w>> / <C-w>< too —
      -- these add discoverable arrow-key bindings that work while focus is in the
      -- panel. The resize sticks for the session (DiffView won't snap it back).
      keymaps = {
        file_panel = {
          { "n", "<C-Right>", "<Cmd>vertical resize +5<CR>", { desc = "Diffview: widen file panel" } },
          { "n", "<C-Left>", "<Cmd>vertical resize -5<CR>", { desc = "Diffview: narrow file panel" } },
          { "n", "<C-Up>", "<Cmd>vertical resize 60<CR>", { desc = "Diffview: file panel wide" } },
          { "n", "<C-Down>", "<Cmd>vertical resize 35<CR>", { desc = "Diffview: file panel reset (35)" } },
        },
      },
      -- Hooks: customize winbar string per window for clearer "branch @ commit" labels
      hooks = {
        -- Force treesitter syntax on BOTH diff panes. The old/blob side (a previous
        -- commit, loaded as a git blob buffer) frequently does NOT auto-attach
        -- treesitter, so it renders flat grey while the new side is colored — that's
        -- the "no syntax on the left" symptom. Starting TS per buffer fixes it.
        -- Guarded with pcall so files without a parser just fall back to plain text.
        diff_buf_read = function(bufnr)
          local ft = vim.bo[bufnr].filetype
          if ft == "" then return end
          local ok, lang = pcall(vim.treesitter.language.get_lang, ft)
          lang = (ok and lang) or ft
          if pcall(vim.treesitter.language.add, lang) then
            pcall(vim.treesitter.start, bufnr, lang)
          end
        end,
        -- Winbar per diff window: "[role] BRANCH @ commit  /  file_path".
        -- SHAs alone don't tell you WHAT is being compared, so resolve each
        -- commit to a ref name (origin/main, my-branch, main~2 …) via name-rev.
        -- Fired on EVERY diff-buffer↔window bind (each file switch), so the
        -- label persists — unlike a one-shot view_opened hook.
        diff_buf_win_enter = function(_, winid, _)
          local ok, lib = pcall(require, "diffview.lib")
          if not ok then return end
          local view = lib.get_current_view()
          if not (view and view.cur_layout) then return end
          local function ref_name(sha)
            local out = vim.fn.systemlist({ "git", "name-rev", "--name-only", "--exclude", "tags/*", sha })
            local name = (vim.v.shell_error == 0 and out[1]) or ""
            if name == "" or name == "undefined" then return nil end
            return (name:gsub("^remotes/", "")) -- remotes/origin/main → origin/main
          end
          for _, win in ipairs(view.cur_layout.windows or {}) do
            if win.id == winid then
              local rev = win.file and win.file.rev or nil
              if rev then
                local label = ""
                if rev.type == 1 then -- LOCAL (working tree)
                  local cur_branch = vim.fn.systemlist({ "git", "branch", "--show-current" })[1] or ""
                  label = "● WORKING TREE" .. (cur_branch ~= "" and (" · " .. cur_branch) or "")
                elseif rev.type == 2 then -- COMMIT
                  local sha8 = rev.commit and rev.commit:sub(1, 8) or "?"
                  local name = rev.commit and ref_name(rev.commit) or nil
                  label = "◀ " .. (name and (name .. " @ " .. sha8) or sha8)
                elseif rev.type == 3 then -- STAGE (index)
                  label = "◆ STAGED"
                elseif rev.type == 4 then -- CUSTOM
                  label = "◇ CUSTOM"
                end
                label = label:gsub("%%", "%%%%") -- '%' is special in 'winbar'
                vim.api.nvim_set_option_value("winbar", label .. "  %f", { win = winid })
              end
            end
          end
        end,
      },
    },
  },
}
