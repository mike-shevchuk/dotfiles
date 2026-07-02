-- Stub for telescope-diffview extension (the real one isn't installed).
-- Some plugin in the chain calls require('telescope').load_extension('diffview')
-- on diffview.nvim startup; without this stub, that throws a warning every time
-- DiffView opens. Returning a minimal valid extension silences it.
-- See: ~/.local/share/LazyVIM/lazy/telescope.nvim/lua/telescope/_extensions/init.lua
return require("telescope").register_extension({
  exports = {
    -- empty — no :Telescope diffview subcommand provided, but no error either
  },
})
