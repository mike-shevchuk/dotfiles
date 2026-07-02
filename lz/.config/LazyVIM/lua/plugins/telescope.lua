return {
  {
    "nvim-telescope/telescope-ui-select.nvim",
  },

  {
    "nvim-telescope/telescope-file-browser.nvim",
    dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
  },

  -- Native C sorter — the single biggest telescope speed win
  {
    "nvim-telescope/telescope-fzf-native.nvim",
    build = "make",
  },

  -- Dynamic rg args mid-prompt:  "pattern -g '*.py'"  /  "pattern -t py"
  {
    "nvim-telescope/telescope-live-grep-args.nvim",
  },

  {
    "willthbill/opener.nvim",
    config = function()
      -- NOTE: telescope.setup() is called ONCE in the main telescope spec below
      -- (multiple setup() calls silently wipe each other's config — whichever
      -- plugin loads last used to win). Extension config lives there too.
      require("opener").setup({
        pre_open = function(new_dir)
          print("Yay, opening " .. new_dir .. " in a moment")
        end,
        post_open = {
          "NeoTree",
          function(new_dir)
            print(new_dir .. " was opened")
          end,
        },
      })
      require("telescope").load_extension("opener")
      vim.api.nvim_set_keymap("n", "<Leader>fd", ":Telescope opener<CR>", { noremap = true })
      vim.api.nvim_set_keymap("n", "<Leader>fD", ":Telescope opener hidden=true<CR>", { noremap = true })
    end,
  },

  {
    "otavioschwanck/arrow.nvim",
    config = function()
      require("arrow").setup({
        show_icons = true,
        leader_key = ";", -- Recommended to be a single key
        buffer_leader_key = "m", -- Per Buffer Mappings
      })
    end,
  },

  {
    "kdheepak/lazygit.nvim",
    cmd = {
      "LazyGit",
      "LazyGitConfig",
      "LazyGitCurrentFile",
      "LazyGitFilter",
      "LazyGitFilterCurrentFile",
    },
    -- optional for floating window border decoration
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    -- setting the keybinding for LazyGit with 'keys' is recommended in
    -- order to load the plugin when the command is run for the first time
    keys = {
      { "<leader>lg", "<cmd>LazyGit<cr>", desc = "LazyGit Test" },
    },
  },

  {
    "nvim-telescope/telescope.nvim",
    -- tag pin removed: 0.1.5 was Nov-2023 vintage and already broke against
    -- nvim-treesitter `main` (see the themes-previewer note below)
    dependencies = {
      "nvim-lua/plenary.nvim",
      "debugloop/telescope-undo.nvim",
      "andrew-george/telescope-themes",
      "folke/noice.nvim",
      "nvim-telescope/telescope-fzf-native.nvim",
      "nvim-telescope/telescope-live-grep-args.nvim",
    },
    keys = {
      {
        "<leader>fg",
        -- live_grep_args: type extra rg flags right in the prompt,
        -- e.g.  handler -g '*.py'   or   AlertType -t py
        function()
          require("telescope").extensions.live_grep_args.live_grep_args()
        end,
        desc = "live grep (args)",
        mode = "n",
      },
      {
        "<leader>fG",
        -- grep EVERYTHING — including .gitignore'd files (node_modules, .venv)
        "<cmd>Telescope live_grep additional_args=--no-ignore<cr>",
        desc = "live grep (no ignore)",
        mode = "n",
      },
      {
        "<leader>fw",
        "<cmd>Telescope grep_string<cr>",
        desc = "grep word under cursor",
        mode = "n",
      },
      {
        "<leader>fT",
        "<cmd>TodoTelescope<cr>",
        desc = "search TODO/FIXME",
        mode = "n",
      },
      {
        "<leader>ff",
        "<cmd>Telescope find_files<cr>",
        desc = "Find files",
        mode = "n",
      },
      {
        "<leader>fh",
        "<cmd>Telescope find_files hidden=true no_ignore=true<cr>",
        desc = "Find files (+ignored)",
        mode = "n",
      },
      {
        "<leader>ft",
        "<cmd>Telescope themes<cr>",
        desc = "change themes",
        mode = "n",
      },
      {
        "<leader>fb",
        "<cmd>Telescope buffers<cr>",
        desc = "buffers",
        mode = "n",
      },
      {
        "<leader><leader>",
        "<cmd>Telescope oldfiles<cr>",
        desc = "recent files",
        mode = "n",
      },
      {
        "<leader>Tu",
        "<cmd>Telescope undo<cr>",
        desc = "undo history",
        mode = "n",
      },
    },

    config = function()
      require("telescope").setup({
        defaults = {
          vimgrep_arguments = {
            "rg",
            "--color=never",
            "--no-heading",
            "--with-filename",
            "--line-number",
            "--column",
            "--smart-case",
            "--hidden",
            "--follow",
            -- NOT --no-ignore: default grep respects .gitignore (no node_modules/
            -- .venv noise). <leader>fG is the grep-everything variant.
            "--glob",
            "!.git/",
          },
        },
        pickers = {
          find_files = {
            hidden = true,
            -- fd: fast, .gitignore-aware (was health-checked but never wired in)
            find_command = { "fd", "--type", "f", "--hidden", "--follow", "--exclude", ".git" },
          },
        },
        extensions = {
          fzf = {}, -- native C sorter, default opts
          opener = {
            use_telescope = true,
            hidden = false, -- do not show hidden directories
            root_dir = "$HOME", -- search from home directory by default
            -- respect_gitignore = true, -- respect .gitignore files
          },
          undo = {
            -- telescope-undo.nvim config, see below
          },
          ["ui-select"] = {
            require("telescope.themes").get_dropdown({}),
          },
          -- nvim-treesitter is on the `main` rewrite which dropped
          -- `parsers.ft_to_lang`; the themes previewer used to crash on it with
          -- the old pinned telescope. Kept disabled (the dropdown UI doesn't
          -- need a preview) — re-enable to test after a telescope update.
          themes = {
            enable_previewer = false,
          },
        },
      })

      require("telescope").load_extension("fzf")
      require("telescope").load_extension("live_grep_args")
      require("telescope").load_extension("undo")
      require("telescope").load_extension("ui-select")
      require("telescope").load_extension("themes")
      require("telescope").load_extension("noice")
      require("telescope").load_extension("file_browser")
    end,
  },
}
