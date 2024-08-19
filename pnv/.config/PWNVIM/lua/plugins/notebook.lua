local quarto = {
  "quarto-dev/quarto-nvim",
	lazy = false,
	ft = { "quarto", "markdown" },
	dev = false,
	config = function()
		require("quarto").setup({
			lspFeatures = {
				languages = { "r", "python", "rust" },
				chunks = "all",
				diagnostics = {
					enabled = true,
					triggers = { "BufWritePost" },
				},
				completion = {
					enabled = true,
				},
			},
			keymap = {
				hover = "H",
				definition = "gd",
				rename = "<leader>rn",
				references = "gr",
				format = "<leader>gf",
			},
			codeRunner = {
				enabled = true,
				default_method = "molten",
			},
		})
	end,
	dependencies = {
		"jmbuhr/otter.nvim",
		opts = {},
	},
}


local jupytertext = {
	"GCBallesteros/jupytext.nvim",
	lazy = false,
	config = function()
		require("jupytext").setup({
			style = "markdown",
			output_extension = "md",
			force_ft = "markdown",
		})
	end,
}

local molten = {
	"benlubas/molten-nvim",
	version = "^1.0.0", -- use version <2.0.0 to avoid breaking changes
	lazy = false,
	build = ":UpdateRemotePlugins",
	init = function()
		vim.g.molten_image_provider = "image.nvim"
		vim.g.molten_output_win_max_height = 12
		vim.g.molten_virt_text_output = true
		vim.g.molten_virt_lines_off_by_1 = true
		vim.g.molten_virt_text_max_lines = 1
    vim.keymap.set("n", "<leader>mi", ":MoltenInit<CR>",
    { silent = true, desc = "Molten Init Kernel" })
    vim.keymap.set("n", "<leader>ml", ":MoltenEvaluateLine<CR>",
    { silent = true, desc = "Molten Evaluate Line" })
    vim.keymap.set("v", "<leader>mv", ":<C-u>MoltenEvaluateVisual<CR>gv<ESC>",
    { silent = true, desc = "Molten Evaluate Visual" })
    vim.keymap.set("n", "<leader>mh", ":MoltenHideOutput<CR>",
    { silent = true, desc = "Molten Hide Output" })
    vim.keymap.set("n", "<leader>mo", ":noautocmd MoltenEnterOutput<CR>",
    { silent = true, desc = "Molten Enter Output" })
    vim.keymap.set("n", "<leader>mc", ":MoltenReevaluateCell<CR>",
    { silent = true, desc = "Molten Run Cell" })
	end,
}


local notebook_img = {
	-- see the image.nvim readme for more information about configuring this plugin
	"3rd/image.nvim",
	opts = {
		backend = "kitty", -- whatever backend you would like to use
		max_width = 100,
		max_height = 12,
		max_height_window_percentage = math.huge,
		max_width_window_percentage = math.huge,
		window_overlap_clear_enabled = true, -- toggles images when windows are overlapped
		window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
	},
}

-- local luarock = {
    --   "vhyrro/luarocks.nvim",
    --   priority = 1001, -- this plugin needs to run before anything else
    --   opts = {
    --     rocks = { "magick" },
    --   },
    -- },
    --


return {
  }
