return {
  {
    'rmagatti/auto-session',
    dependencies = {
      'nvim-telescope/telescope.nvim', -- Only needed if you want to use sesssion lens
    },
    enable = true,

    config = function()
      require('legendary').setup({ extensions = { lazy_nvim = true } })
      require('auto-session').setup({
        auto_session_enable_last_session = true,
        auto_session_suppress_dirs = { '~/', '~/Projects', '~/Downloads', '/', '~/dotfiles' },
        session_lens = {
          buftypes_to_ignore = {},
          load_on_setup = true,
          theme_conf = {border = true},
          previewer = false,
        },
        keymaps = {
          {
            "<leader>fs",
            '<cmd>Telescope commander<cr>',
            desc = 'FCK Find session',
            mode = {"n"},
          },
        },
      })
    end,
  },
}
