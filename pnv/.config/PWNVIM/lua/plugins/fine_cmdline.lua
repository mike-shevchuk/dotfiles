return {
  'VonHeikemen/fine-cmdline.nvim',
  enable = true,
  dependencies = 'MunifTanjim/nui.nvim',
  config = function(plugins, opts)
    local f_cmdline = require("fine-cmdline")



    f_cmdline.setup({


      cmdline = {
        enable_keymaps = true,
        smart_history = true,
        prompt = ': '
      },
      popup = {
        position = {
          row = '10%',
          col = '50%',
        },
        size = {
          width = '60%',
        },
        border = {
          style = 'rounded',
        },
        win_options = {
          winhighlight = 'Normal:Normal,FloatBorder:FloatBorder',
        },
        buf_options = {
          -- Setup a special file type if you need to
          filetype = 'FineCmdlinePrompt'
        },
      },
      hooks = {
        before_mount = function(input)
          -- code
        end,
        after_mount = function(input)
          -- code
        end,
        set_keymaps = function(imap, feedkeys)
          -- code
        end
      }
    })
    vim.api.nvim_set_keymap('n', ':', '<cmd>FineCmdline<CR>', {noremap = true})
  end,
}
