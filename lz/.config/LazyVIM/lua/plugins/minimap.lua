-- mini.map — code minimap (bird's-eye "map code") with change bars.
--
-- Pulls colors from gitsigns: added / changed / deleted lines show as colored
-- marks down the map, plus diagnostics and search hits. Works in normal buffers
-- AND in DiffView panes (focus the right pane → its file's map with git changes).
--
-- Navigation:
--   <leader>mm  toggle the map on/off
--   <leader>mf  focus the map → move j/k (source view follows live) → <CR> jump,
--               <Esc> cancel. With focusable=true you can also CLICK in the map.
--   <leader>mr  refresh
--
-- Related (already native in DiffView, no plugin needed):
--   <C-h> / <C-l>   switch between the left (old) and right (new) diff pane
--   zo / za         uncollapse hidden context (GitHub-style expand)
--   zR / zM         show the WHOLE file / collapse back to changes only
return {
  {
    "echasnovski/mini.map",
    version = false,
    -- lazy-load triggers: the keys below AND the user commands (so the palette /
    -- `:Minimap*` work even before the first keypress — lazy creates stubs).
    cmd = { "MinimapToggle", "MinimapFocus", "MinimapRefresh" },
    keys = {
      { "<leader>mm", function() require("mini.map").toggle() end, desc = "Minimap: toggle" },
      { "<leader>mf", function() require("mini.map").toggle_focus() end, desc = "Minimap: focus (navigate + <CR>)" },
      { "<leader>mr", function() require("mini.map").refresh() end, desc = "Minimap: refresh" },
    },
    config = function()
      local map = require("mini.map")
      map.setup({
        integrations = {
          map.gen_integration.builtin_search(),
          map.gen_integration.diagnostic(),
          map.gen_integration.gitsigns(), -- add/change/delete color bars from gitsigns
        },
        symbols = {
          -- braille dots = a readable zoomed-out "code map"; try block('3x2') too
          encode = map.gen_encode_symbols.dot("4x2"),
          scroll_line = "█",
          scroll_view = "┃",
        },
        window = {
          side = "right",
          width = 12,
          winblend = 20,
          focusable = true, -- allow mouse click into the map to jump
          show_integration_count = false,
          zindex = 10,
        },
      })
      -- User commands (so they surface in the commander/legendary palette and `:`).
      vim.api.nvim_create_user_command("MinimapToggle", function() map.toggle() end,
        { desc = "Minimap · toggle code map (gitsigns change bars)" })
      vim.api.nvim_create_user_command("MinimapFocus", function() map.toggle_focus() end,
        { desc = "Minimap · focus map → j/k navigate, <CR> jump, <Esc> cancel" })
      vim.api.nvim_create_user_command("MinimapRefresh", function() map.refresh() end,
        { desc = "Minimap · refresh" })
    end,
  },
}
