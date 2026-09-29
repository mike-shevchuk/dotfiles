-- Editing extras.
--
-- NOTE on completion: this config uses LazyVim's default engine, **blink.cmp**
-- (see lazy-lock.json). The previous nvim-cmp specs in this file were inert
-- (blink is the active engine) and a manually-loaded nvim-cmp would compete with
-- blink and produce double completion menus — so they were removed. Tune
-- completion via LazyVim's blink.cmp spec, not here.
--
-- diffview/neogit live in plugins/diffview.lua; char-level diff in plugins/codediff.lua.

return {
  {
    "ecthelionvi/NeoComposer.nvim",
    dependencies = { "kkharji/sqlite.lua" },
    opts = {},
  },
}
