local tree = {
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v2.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
    "MunifTanjim/nui.nvim",
  },
  config = function()
    require("neo-tree").setup({
	    filesystem = {
	      filtered_items = {
          visible = false, -- when true, they will just be displayed differently than normal items
          hide_dotfiles = true,
          hide_gitignored = true,
          hide_by_name = {
            ".DS_Store",
            "thumbs.db"
            -- "node_modules"
          },
          never_show = { -- remains hidden even if visible is toggled to true
            ".DS_Store",
            "thumbs.db"
          },
		    filters = {
			    respect_gitignore = true,
			    gitignore_treatmente = 'symbol'	-- can be 'hidden' or 'symbol'
		    }
	    }
    }
  })
  end,
}

return tree
