
return {
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        config = function () 
            local configs = require("nvim-treesitter.configs")
            configs.setup({
                -- 安装 language parser
                -- :TSInstallInfo 命令查看支持的语言
                ensure_installed = {
                    "html",
                    "json",
                    "css",
                    "vim",
                    "lua",
                    "javascript",
                    "typescript",
                    "python",
                    "c",
                    "java",
                    "julia",
                    "query",
                    "markdown",
                    "markdown_inline",
                    "bash",
                },
                -- 启用代码高亮功能
                highlight = {
                    enable = true,
                    --additional_vim_regex_highlighting = false
                    additional_vim_regex_highlighting = { "markdown" },
                },
                -- 启用增量选择
                incremental_selection = {
                    enable = true,
                    keymaps = {
                        --- init_selection = '<TAB>',
                        node_incremental = '<TAB>',
                        node_decremental = '<S-TAB>',
                        --- scope_incremental = '<TAB>',
                    }
                },
                rainbow = {
                    enable = true,
                    extended_mode = true, -- Also highlight non-bracket delimiters like html tags, boolean or table: lang -> boolean
                    max_file_lines = nil, -- Do not enable for files with more than n lines, int
                    colors = {}, -- table of hex strings
                    termcolors = {} -- table of colour name strings
                },
                -- 启用基于Treesitter的代码格式化(=) . NOTE: This is an experimental feature.
                indent = {
                    enable = false
                },
                playground = {
                    enable = true,
                    disable = {},
                    updatetime = 25, -- Debounced time for highlighting nodes in the playground from source code
                    persist_queries = false, -- Whether the query persists across vim sessions
                    keybindings = {
                        toggle_query_editor = 'o',
                        toggle_hl_groups = 'i',
                        toggle_injected_languages = 't',
                        toggle_anonymous_nodes = 'a',
                        toggle_language_display = 'I',
                        focus_language = 'f',
                        unfocus_language = 'F',
                        update = 'R',
                        goto_node = '<cr>',
                        show_help = '?',
                    },
                },
                query_linter = {
                    enable = true,
                    use_virtual_text = true,
                    lint_events = {"BufWrite", "CursorHold"},
                },
            })
            vim.wo.foldmethod = 'expr'
            vim.wo.foldexpr = 'nvim_treesitter#foldexpr()'
            -- 默认不要折叠
            -- https://stackoverflow.com/questions/8316139/how-to-set-the-default-to-unfolded-when-you-open-a-file
            vim.wo.foldlevel = 99
        end
    },
    {
        "nvim-treesitter/playground",
        cmd = "TSPlaygroundToggle",
    },
}

