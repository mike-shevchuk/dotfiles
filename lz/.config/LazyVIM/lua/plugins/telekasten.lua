-- Zettelkasten: контекст (work/life/sport/general) × період (day/week/month).
-- Структура нотаток: ~/zettelkasten/periodic/<ctx>/{daily,weekly,monthly}/
-- Перемикання контексту: <leader>zv{w,l,s,g}; період: <leader>z{d,w,m}.

local zk = vim.fn.expand("~/zettelkasten")
local tpl = zk .. "/templates"

-- Перемкнути активний vault за іменем (require всередині — виконується вже
-- після lazy-load плагіна при натисканні клавіші).
local function sw(name)
  return function()
    local t = require("telekasten")
    t.chdir(t.vaults[name])
    vim.notify("Zettel context → " .. name, vim.log.levels.INFO)
  end
end

return {
  "renerocksai/telekasten.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  -- cmd-тригери: щоб виклики з палітри (commander/legendary) вантажили плагін,
  -- навіть коли жодну z-клавішу ще не натиснуто.
  cmd = { "Telekasten", "ZkHelp" },
  keys = {
    -- Контекст (яке "життя" активне зараз)
    { "<leader>zvw", sw("work"), desc = "ZK context: work", mode = "n" },
    { "<leader>zvl", sw("life"), desc = "ZK context: life", mode = "n" },
    { "<leader>zvs", sw("sport"), desc = "ZK context: sport", mode = "n" },
    { "<leader>zvg", sw("general"), desc = "ZK context: general", mode = "n" },
    { "<leader>zv", "<cmd>Telekasten switch_vault<CR>", desc = "ZK switch context (picker)", mode = "n" },

    -- Період у активному контексті
    { "<leader>zd", "<cmd>Telekasten goto_today<CR>", desc = "ZK daily (today)", mode = "n" },
    { "<leader>zw", "<cmd>Telekasten goto_thisweek<CR>", desc = "ZK weekly (this week)", mode = "n" },
    { "<leader>zm", "<cmd>Telekasten goto_thismonth<CR>", desc = "ZK monthly (this month)", mode = "n" },

    -- Навігація / пошук / зв'язки
    { "<leader>zp", "<cmd>Telekasten panel<CR>", desc = "ZK panel", mode = "n" },
    { "<leader>zg", "<cmd>Telekasten search_notes<CR>", desc = "ZK search notes", mode = "n" },
    { "<leader>zt", "<cmd>Telekasten show_tags<CR>", desc = "ZK show tags", mode = "n" },
    { "<leader>zz", "<cmd>Telekasten follow_link<CR>", desc = "ZK follow link", mode = "n" },
    { "<leader>zn", "<cmd>Telekasten new_note<CR>", desc = "ZK new note", mode = "n" },
    { "<leader>zc", "<cmd>Telekasten show_calendar<CR>", desc = "ZK calendar", mode = "n" },
    { "<leader>zb", "<cmd>Telekasten show_backlinks<CR>", desc = "ZK backlinks", mode = "n" },
    { "<leader>zI", "<cmd>Telekasten insert_img_link<CR>", desc = "ZK insert image", mode = "n" },
    { "<leader>z3", "<cmd>Telekasten toggle_todo<CR>", desc = "ZK toggle todo", mode = "n" },

    -- Шпаргалка
    { "<leader>z?", "<cmd>ZkHelp<CR>", desc = "ZK help panel", mode = "n" },
  },

  config = function()
    -- Один контекст = свій home + daily/weekly/monthly теки; шаблони спільні.
    local function vault(ctx)
      local base = zk .. "/periodic/" .. ctx
      return {
        home = base,
        dailies = base .. "/daily",
        weeklies = base .. "/weekly",
        monthlies = base .. "/monthly",
        templates = tpl,
        template_new_note = tpl .. "/daily.md",
        template_new_daily = tpl .. "/daily.md",
        template_new_weekly = tpl .. "/weekly.md",
        template_new_monthly = tpl .. "/monthly.md",
        extension = ".md",
        media_previewer = "viu-previewer",
        image_link_style = "markdown",
      }
    end

    require("telekasten").setup({
      home = zk,
      default_vault = "work",
      vaults = {
        work = vault("work"),
        life = vault("life"),
        sport = vault("sport"),
        general = vault("general"),
      },
    })

    -- Автовставлення лінка при наборі [[
    vim.keymap.set("i", "[[", "<cmd>Telekasten insert_link<CR>")

    -- Плаваюча шпаргалка: <leader>z? / :ZkHelp
    local function zk_help()
      local t = require("telekasten")
      local home = (t.Cfg and t.Cfg.home) or ""
      local active = home:match("periodic/([^/]+)") or "?"
      local lines = {
        "  ZETTELKASTEN — шпаргалка",
        "  активний контекст: " .. active,
        "",
        "  КОНТЕКСТ (яке «життя» зараз)",
        "    <leader>zvw   work",
        "    <leader>zvl   life",
        "    <leader>zvs   sport",
        "    <leader>zvg   general (архів)",
        "    <leader>zv    вибрати зі списку",
        "",
        "  ПЕРІОД (у активному контексті)",
        "    <leader>zd    daily    сьогодні",
        "    <leader>zw    weekly   цей тиждень",
        "    <leader>zm    monthly  цей місяць",
        "",
        "  НАВІГАЦІЯ / ПОШУК",
        "    <leader>zg  пошук       <leader>zt  теги",
        "    <leader>zb  backlinks   <leader>zz  перейти по лінку",
        "    <leader>zn  нова        <leader>zc  календар",
        "    <leader>zp  панель      <leader>z3  toggle todo",
        "    [[          вставити лінк (insert-режим)",
        "",
        "  ПОТІК:  zvl → zd = life daily  ·  zvw → zm = work monthly",
        "",
        "  q / <Esc> — закрити",
      }
      local width = 0
      for _, l in ipairs(lines) do
        width = math.max(width, vim.fn.strdisplaywidth(l))
      end
      width = width + 2
      local height = #lines
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false
      vim.bo[buf].bufhidden = "wipe"
      local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        col = math.floor((vim.o.columns - width) / 2),
        row = math.floor((vim.o.lines - height) / 2),
        style = "minimal",
        border = "rounded",
        title = " Zettelkasten help ",
        title_pos = "center",
      })
      vim.wo[win].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder"
      for _, k in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", k, "<cmd>close<CR>", { buffer = buf, nowait = true, silent = true })
      end
    end
    vim.api.nvim_create_user_command("ZkHelp", zk_help, { desc = "Zettelkasten cheatsheet" })
  end,
}
