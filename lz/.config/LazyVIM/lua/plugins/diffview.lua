-- DiffView configuration override — show branch/rev labels above each pane.
-- Triggered by `prefix V/A/M/N/O` tmux popups via ~/dotfiles/tmux/scripts/git-compare.sh.
return {
  {
    "sindrets/diffview.nvim",
    opts = {
      -- winbar shows the diff symbol (a/b) + the rev being viewed on each pane.
      -- Combined with nvim's default statusline, you get left=base@rev, right=HEAD@rev.
      view = {
        default = {
          winbar_info = true,
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
          width = 35,
        },
      },
      -- Hooks: customize winbar string per window for clearer "branch @ commit" labels
      hooks = {
        view_opened = function(view)
          -- Set winbar on each diff pane: "[role] branch@commit  /  file_path"
          for _, win in ipairs(view.cur_layout.windows or {}) do
            local rev = win.file and win.file.rev or nil
            if rev then
              local label = ""
              if rev.type == 1 then -- LOCAL (working tree)
                label = "● WORKING TREE"
              elseif rev.type == 2 then -- COMMIT
                label = string.format("◀ %s", rev.commit and rev.commit:sub(1, 8) or "?")
              elseif rev.type == 3 then -- STAGE (index)
                label = "◆ STAGED"
              elseif rev.type == 4 then -- CUSTOM
                label = "◇ CUSTOM"
              end
              vim.api.nvim_set_option_value("winbar", label .. "  %f", { win = win.id })
            end
          end
        end,
      },
    },
  },
}
