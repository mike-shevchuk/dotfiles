-- Plugin Manager: lazy.nvim

-- Helper command: :BranchDiff [3dot|2dot]
-- Opens DiffView for current branch vs detected default base (origin/main OR origin/master).
-- Falls back to `origin/main` if symbolic-ref lookup fails.
vim.api.nvim_create_user_command("BranchDiff", function(opts)
  local mode = (opts.args == "" or opts.args == nil) and "3dot" or opts.args
  local out = vim.fn.systemlist({ "git", "symbolic-ref", "refs/remotes/origin/HEAD" })
  local base = "origin/main"
  if vim.v.shell_error == 0 and out[1] and out[1] ~= "" then
    base = (out[1]:gsub("^refs/remotes/", ""))
  end
  local sep = mode == "2dot" and ".." or "..."
  vim.cmd("DiffviewOpen " .. base .. sep .. "HEAD")
end, {
  nargs = "?",
  complete = function() return { "3dot", "2dot" } end,
  desc = "DiffView · branch vs detected default base (auto: origin/main or origin/master)",
  force = true,
})

-- Backward-compat alias: old name kept so muscle memory / older notes still work.
vim.api.nvim_create_user_command("DvBranchHead", function(o)
  vim.cmd("BranchDiff " .. o.args)
end, {
  nargs = "?",
  complete = function() return { "3dot", "2dot" } end,
  desc = "alias → :BranchDiff",
  force = true,
})

-- Helper command: :WtSwitch — fuzzy-pick a git worktree and tcd into it.
-- Parses `--porcelain` → clean rows "● branch  ·  dir  (sha)" instead of raw
-- absolute paths. Current worktree marked ● and sorted first. fuzzy over the
-- whole row (branch + dir) via dressing → telescope.
vim.api.nvim_create_user_command("WtSwitch", function()
  local out = vim.fn.systemlist({ "git", "worktree", "list", "--porcelain" })
  if vim.v.shell_error ~= 0 then
    vim.notify("Not a git repo", vim.log.levels.ERROR)
    return
  end
  local cur = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })[1] or ""

  -- Parse porcelain blocks into {path, sha, branch}.
  local entries, e = {}, nil
  for _, line in ipairs(out) do
    if line:match("^worktree ") then
      e = { path = line:sub(10) }
      entries[#entries + 1] = e
    elseif e and line:match("^HEAD ") then
      e.sha = line:sub(6, 12)
    elseif e and line:match("^branch ") then
      e.branch = line:gsub("^branch refs/heads/", "")
    elseif e and line == "detached" then
      e.branch = "(detached)"
    end
  end
  for _, x in ipairs(entries) do
    x.dir = vim.fn.fnamemodify(x.path, ":t")
    x.branch = x.branch or "(no branch)"
    x.current = x.path == cur
  end
  -- Current worktree first, then alphabetical by branch.
  table.sort(entries, function(a, b)
    if a.current ~= b.current then
      return a.current
    end
    return a.branch < b.branch
  end)

  vim.ui.select(entries, {
    prompt = "Switch to worktree:",
    format_item = function(x)
      return string.format("%s %-42s  %s  (%s)", x.current and "●" or " ", x.branch, x.dir, x.sha or "-------")
    end,
  }, function(choice)
    if not choice then
      return
    end
    vim.cmd("tcd " .. vim.fn.fnameescape(choice.path))
    vim.notify("cwd → " .. choice.dir .. "  [" .. choice.branch .. "]")
  end)
end, { desc = "Worktree · fuzzy-switch cwd to another git worktree", force = true })

-- Helper command: :PrDiff [number] — review a PR purely as a DiffView (no
-- checkout, no octo). Resolves head/base via gh, fetches them, opens the
-- 3-dot diff (= GitHub "Files changed"). With no arg, uses current branch's PR.
vim.api.nvim_create_user_command("PrDiff", function(o)
  local args = (o.args ~= "") and { "gh", "pr", "view", o.args, "--json", "headRefName,baseRefName" }
    or { "gh", "pr", "view", "--json", "headRefName,baseRefName" }
  local out = vim.fn.system(args)
  if vim.v.shell_error ~= 0 then
    vim.notify("gh pr view failed:\n" .. out, vim.log.levels.ERROR)
    return
  end
  local ok, data = pcall(vim.fn.json_decode, out)
  if not ok or not data.headRefName then
    vim.notify("Could not resolve PR head/base", vim.log.levels.ERROR)
    return
  end
  vim.notify(("PrDiff: fetching %s + %s …"):format(data.baseRefName, data.headRefName))
  local fetch = vim.fn.system({ "git", "fetch", "origin", data.baseRefName, data.headRefName })
  if vim.v.shell_error ~= 0 then -- fork PR / offline → refs missing or stale; don't diff silently
    vim.notify("git fetch failed (fork PR or offline?):\n" .. fetch, vim.log.levels.ERROR)
    return
  end
  vim.cmd(("DiffviewOpen origin/%s...origin/%s"):format(data.baseRefName, data.headRefName))
end, {
  nargs = "?",
  desc = "Review PR · open a PR as DiffView (by number, or current branch) — no checkout, no comments",
  force = true,
})

-- Git + Code-Review palette: surfaced in commander (`<leader>fk`) and legendary (`<leader>fc`).
-- No keybinds — fuzzy-search by category prefix:
--   "diff" / "branch" → DiffView entries
--   "log" / "commit"  → lazygit / neogit / fugitive
--   "pr" / "review"   → Octo PR + review
--   "issue"           → Octo issues
--   "react"           → Octo reactions
--   "hunk" / "blame"  → gitsigns
local git_review_palette = {
  -- ───── 🧪 Try-grid for code review — A/B compare each tool ─────────────
  -- Fuzzy-search hints:
  --   "try"          → all tests (every plugin)
  --   "try octo"     → only Octo tests
  --   "try diffview" → only DiffView tests
  --   "try blame"    → blame across tools
  --   "try hunk"     → hunk navigation/stage across tools

  -- ─ Octo: GitHub PR review (comments + threads + reactions)
  -- Find a PR
  { cmd = "Octo pr list",                              desc = "Try Octo · 1 — list open PRs (current repo)" },
  { cmd = "Octo pr list state=all",                    desc = "Try Octo · 2 — list ALL PRs (open + closed + merged)" },
  { cmd = "Octo pr list state=closed",                 desc = "Try Octo · 3 — list closed/merged PRs (good for testing)" },
  { cmd = "Octo pr list assignee=@me",                 desc = "Try Octo · 4 — PRs assigned to me" },
  { cmd = "Octo pr search is:open author:@me",         desc = "Try Octo · 5 — my open PRs (search syntax)" },
  { cmd = "Octo pr search is:open review-requested:@me", desc = "Try Octo · 6 — PRs awaiting my review" },
  -- Inspect the PR overview
  { cmd = "Octo pr files",                             desc = "Try Octo · 7 — list changed files in current PR" },
  { cmd = "Octo pr diff",                              desc = "Try Octo · 8 — raw unified diff buffer" },
  { cmd = "Octo pr commits",                           desc = "Try Octo · 9 — list commits in current PR" },
  { cmd = "Octo pr checks",                            desc = "Try Octo · 10 — CI checks status" },
  { cmd = "Octo pr changes",                           desc = "Try Octo · 11 — show high-level change stats" },
  -- Enter review mode (the diff with comments)
  { cmd = "Octo review start",                         desc = "Try Octo · 12 — start review (file tree + diff + threads)" },
  { cmd = "Octo review resume",                        desc = "Try Octo · 13 — resume in-progress review (drafts)" },
  { cmd = "Octo review discard",                       desc = "Try Octo · 14 — discard pending review (drop drafts)" },
  -- Read existing comments
  { cmd = "Octo review comments",                      desc = "Try Octo · 15 — list every review comment in PR" },
  -- Add your own feedback
  { cmd = "Octo comment add",                          desc = "Try Octo · 16 — add comment on current line (visual-select first)" },
  { cmd = "Octo thread resolve",                       desc = "Try Octo · 17 — resolve thread under cursor" },
  { cmd = "Octo thread unresolve",                     desc = "Try Octo · 18 — unresolve thread under cursor" },
  -- Reactions (great for bot reviews — Cursor/Bugbot)
  { cmd = "Octo reaction thumbs_up",                   desc = "Try Octo · 19 — 👍 reaction on comment under cursor" },
  { cmd = "Octo reaction thumbs_down",                 desc = "Try Octo · 20 — 👎 reaction on comment under cursor" },
  { cmd = "Octo reaction heart",                       desc = "Try Octo · 21 — ❤️ reaction on comment under cursor" },
  { cmd = "Octo reaction rocket",                      desc = "Try Octo · 22 — 🚀 reaction on comment under cursor" },
  { cmd = "Octo reaction eyes",                        desc = "Try Octo · 23 — 👀 reaction (I'm looking at this)" },
  -- Submit / link out
  { cmd = "Octo review submit",                        desc = "Try Octo · 24 — submit review (approve/comment/request changes)" },
  { cmd = "Octo pr browser",                           desc = "Try Octo · 25 — open current PR in GitHub browser" },
  { cmd = "Octo pr url",                               desc = "Try Octo · 26 — copy PR URL to clipboard" },

  -- ─ DiffView: universal side-by-side for any pair of refs
  { cmd = "BranchDiff 3dot",                         desc = "Try DiffView · 1 — branch vs detected base (3-dot, PR-style, auto main/master)" },
  { cmd = "BranchDiff 2dot",                         desc = "Try DiffView · 2 — branch vs detected base (2-dot, only my commits)" },
  { cmd = "DiffviewOpen HEAD~1...HEAD",                desc = "Try DiffView · 3 — last commit vs HEAD" },
  { cmd = "DiffviewOpen",                              desc = "Try DiffView · 4 — uncommitted (working tree vs index)" },
  { cmd = "DiffviewOpen HEAD",                         desc = "Try DiffView · 5 — uncommitted + staged vs HEAD" },
  { cmd = "DiffviewOpen --cached",                     desc = "Try DiffView · 6 — staged-only vs HEAD" },
  { cmd = "DiffviewFileHistory %",                     desc = "Try DiffView · 7 — current file history (walk every commit)" },
  { cmd = "DiffviewFileHistory",                       desc = "Try DiffView · 8 — repo-wide file history" },
  { cmd = "DiffviewToggleFiles",                       desc = "Try DiffView · 9 — toggle file panel inside DiffView" },

  -- ─ CodeDiff: char-level diff (VSCode-style)
  { cmd = "CodeDiff",                                  desc = "Try CodeDiff · 1 — char-level diff for current file vs HEAD" },

  -- ─ Gitsigns: inline hunks + blame in the current buffer (no extra window)
  { cmd = "Gitsigns preview_hunk",                     desc = "Try Gitsigns · 1 — preview hunk under cursor (floating)" },
  { cmd = "Gitsigns next_hunk",                        desc = "Try Gitsigns · 2 — jump to next hunk (also ]c)" },
  { cmd = "Gitsigns prev_hunk",                        desc = "Try Gitsigns · 3 — jump to previous hunk (also [c)" },
  { cmd = "Gitsigns stage_hunk",                       desc = "Try Gitsigns · 4 — stage hunk without leaving file" },
  { cmd = "Gitsigns reset_hunk",                       desc = "Try Gitsigns · 5 — discard hunk" },
  { cmd = "Gitsigns diffthis",                         desc = "Try Gitsigns · 6 — split-diff current file vs index" },
  { cmd = "Gitsigns blame_line",                       desc = "Try Gitsigns · 7 — blame popup for current line" },
  { cmd = "Gitsigns toggle_current_line_blame",        desc = "Try Gitsigns · 8 — inline blame on every line (toggle)" },
  { cmd = "Gitsigns setloclist",                       desc = "Try Gitsigns · 9 — list every hunk in loclist (jump grid)" },
  { cmd = "Gitsigns toggle_deleted",                   desc = "Try Gitsigns · 10 — show deleted lines inline" },

  -- ─ LazyGit: full git TUI
  { cmd = "LazyGit",                                   desc = "Try LazyGit · 1 — full TUI (press ? for help)" },
  { cmd = "LazyGitCurrentFile",                        desc = "Try LazyGit · 2 — TUI scoped to current file" },
  { cmd = "LazyGitFilter",                             desc = "Try LazyGit · 3 — commits filtered to branch" },
  { cmd = "LazyGitFilterCurrentFile",                  desc = "Try LazyGit · 4 — commits filtered to current file" },

  -- ─ Neogit: magit-style status buffer
  { cmd = "Neogit",                                    desc = "Try Neogit · 1 — status buffer (s=stage, c c=commit, P p=push)" },
  { cmd = "Neogit commit",                             desc = "Try Neogit · 2 — commit popup directly" },
  { cmd = "Neogit log",                                desc = "Try Neogit · 3 — log popup" },
  { cmd = "Neogit kind=split",                         desc = "Try Neogit · 4 — open status in horizontal split" },

  -- ─ Fugitive: Tpope classic (minimal, command-driven)
  { cmd = "G",                                         desc = "Try Fugitive · 1 — :G status buffer" },
  { cmd = "Gclog",                                     desc = "Try Fugitive · 2 — :Gclog repo commit log" },
  { cmd = "0Gclog",                                    desc = "Try Fugitive · 3 — :0Gclog current file log" },
  { cmd = "Gdiffsplit",                                desc = "Try Fugitive · 4 — split-diff current file vs index" },
  { cmd = "Gdiffsplit HEAD",                           desc = "Try Fugitive · 5 — split-diff current file vs HEAD" },
  { cmd = "Git blame",                                 desc = "Try Fugitive · 6 — vertical blame panel" },
  { cmd = "Gvdiffsplit!",                              desc = "Try Fugitive · 7 — 3-way merge diff (during conflicts)" },

  -- ───── Git Diff (working tree / index / branch) ─────────────────────────
  { cmd = "DiffviewOpen",                              desc = "Git Diff · working tree vs index (DiffView)" },
  { cmd = "DiffviewOpen HEAD",                         desc = "Git Diff · working tree + staged vs HEAD" },
  { cmd = "DiffviewOpen --cached",                     desc = "Git Diff · staged vs HEAD" },
  { cmd = "BranchDiff 3dot",                         desc = "Git Diff · branch vs detected base (3-dot, PR-style, auto main/master)" },
  { cmd = "BranchDiff 2dot",                         desc = "Git Diff · branch vs detected base (2-dot, only my commits)" },
  { cmd = "DiffviewClose",                             desc = "Git Diff · close DiffView" },
  { cmd = "DiffviewRefresh",                           desc = "Git Diff · refresh DiffView" },
  { cmd = "DiffviewToggleFiles",                       desc = "Git Diff · toggle file panel" },
  { cmd = "DiffviewFocusFiles",                        desc = "Git Diff · focus file panel" },
  { cmd = "DiffviewFileHistory %",                     desc = "Git Diff · file history (current file)" },
  { cmd = "DiffviewFileHistory",                       desc = "Git Diff · file history (whole repo)" },

  -- ───── Char-level diff (VSCode-style) ───────────────────────────────────
  { cmd = "CodeDiff",                                  desc = "Git Diff · char-level (CodeDiff, VSCode-style) — press t for inline/unified" },

  -- ───── Code Map (mini.map minimap) ──────────────────────────────────────
  { cmd = "MinimapToggle",                             desc = "Code Map · toggle minimap (gitsigns add/del/chg bars + diagnostics)" },
  { cmd = "MinimapFocus",                              desc = "Code Map · focus map → j/k navigate, <CR> jump, <Esc> cancel (mouse click works too)" },
  { cmd = "MinimapRefresh",                            desc = "Code Map · refresh minimap" },

  -- ───── Git TUIs / log / commit ──────────────────────────────────────────
  { cmd = "LazyGit",                                   desc = "Git Log · open lazygit (full TUI)" },
  { cmd = "LazyGitCurrentFile",                        desc = "Git Log · lazygit for current file" },
  { cmd = "LazyGitFilter",                             desc = "Git Log · lazygit filtered commits (branch)" },
  { cmd = "LazyGitFilterCurrentFile",                  desc = "Git Log · lazygit filtered commits (file)" },
  { cmd = "Neogit",                                    desc = "Git Log · neogit (magit-style status)" },
  { cmd = "Neogit commit",                             desc = "Git Commit · neogit commit popup" },
  { cmd = "G",                                         desc = "Git Status · fugitive (:G)" },
  { cmd = "Gclog",                                     desc = "Git Log · fugitive repo log" },
  { cmd = "0Gclog",                                    desc = "Git Log · fugitive log for current file" },
  { cmd = "Gdiffsplit",                                desc = "Git Diff · fugitive split for current file" },
  { cmd = "Git blame",                                 desc = "Git Blame · fugitive blame for current file" },

  -- ───── Gitsigns (hunks / blame) ─────────────────────────────────────────
  { cmd = "Gitsigns preview_hunk",                     desc = "Git Hunk · preview hunk under cursor" },
  { cmd = "Gitsigns stage_hunk",                       desc = "Git Hunk · stage hunk under cursor" },
  { cmd = "Gitsigns reset_hunk",                       desc = "Git Hunk · reset hunk under cursor" },
  { cmd = "Gitsigns undo_stage_hunk",                  desc = "Git Hunk · undo stage hunk" },
  { cmd = "Gitsigns stage_buffer",                     desc = "Git Hunk · stage entire buffer" },
  { cmd = "Gitsigns diffthis",                         desc = "Git Diff · diff this buffer vs index" },
  { cmd = "Gitsigns toggle_current_line_blame",        desc = "Git Blame · toggle inline blame" },
  { cmd = "Gitsigns blame_line",                       desc = "Git Blame · blame line popup" },
  { cmd = "Gitsigns toggle_deleted",                   desc = "Git Diff · toggle deleted lines inline" },

  -- ───── Octo PR ──────────────────────────────────────────────────────────
  { cmd = "Octo pr list",                              desc = "Review PR · list open pull requests" },
  { cmd = "Octo pr search",                            desc = "Review PR · search pull requests" },
  { cmd = "Octo pr create",                            desc = "Review PR · create new pull request" },
  { cmd = "Octo pr checkout",                          desc = "Review PR · checkout PR branch locally" },
  { cmd = "Octo pr merge",                             desc = "Review PR · merge pull request" },
  { cmd = "Octo pr close",                             desc = "Review PR · close pull request" },
  { cmd = "Octo pr reopen",                            desc = "Review PR · reopen pull request" },
  { cmd = "Octo pr ready",                             desc = "Review PR · mark draft as ready for review" },
  { cmd = "Octo pr browser",                           desc = "Review PR · open in GitHub browser" },
  { cmd = "Octo pr url",                               desc = "Review PR · copy PR URL to clipboard" },
  { cmd = "Octo pr commits",                           desc = "Review PR · list commits in PR" },
  { cmd = "Octo pr files",                             desc = "Review PR · list changed files" },
  { cmd = "Octo pr diff",                              desc = "Review PR · open raw diff" },
  { cmd = "Octo pr checks",                            desc = "Review PR · show CI checks status" },
  { cmd = "Octo pr reload",                            desc = "Review PR · reload current PR buffer" },

  -- ───── Octo Review (the diff+comments mode) ─────────────────────────────
  { cmd = "Octo review start",                         desc = "Review PR · start review (diff + inline comments)" },
  { cmd = "Octo review resume",                        desc = "Review PR · resume pending review" },
  { cmd = "Octo review discard",                       desc = "Review PR · discard in-progress review" },
  { cmd = "Octo review submit",                        desc = "Review PR · submit (approve / comment / request changes)" },
  { cmd = "Octo review comments",                      desc = "Review PR · list all review comments" },
  { cmd = "PrDiff",                                    desc = "Review PR · open as DiffView (no checkout, no comments)" },

  -- ───── Octo comments / threads ──────────────────────────────────────────
  { cmd = "Octo comment add",                          desc = "Review Comment · add comment on line" },
  { cmd = "Octo comment delete",                       desc = "Review Comment · delete comment under cursor" },
  { cmd = "Octo thread resolve",                       desc = "Review Thread · resolve review thread" },
  { cmd = "Octo thread unresolve",                     desc = "Review Thread · unresolve review thread" },

  -- ───── Octo reactions ───────────────────────────────────────────────────
  { cmd = "Octo reaction thumbs_up",                   desc = "Review React · 👍 thumbs up" },
  { cmd = "Octo reaction thumbs_down",                 desc = "Review React · 👎 thumbs down" },
  { cmd = "Octo reaction heart",                       desc = "Review React · ❤️ heart" },
  { cmd = "Octo reaction laugh",                       desc = "Review React · 😄 laugh" },
  { cmd = "Octo reaction hooray",                      desc = "Review React · 🎉 hooray" },
  { cmd = "Octo reaction rocket",                      desc = "Review React · 🚀 rocket" },
  { cmd = "Octo reaction eyes",                        desc = "Review React · 👀 eyes" },
  { cmd = "Octo reaction confused",                    desc = "Review React · 😕 confused" },

  -- ───── Octo issues ──────────────────────────────────────────────────────
  { cmd = "Octo issue list",                           desc = "Issue · list open issues" },
  { cmd = "Octo issue create",                         desc = "Issue · create new issue" },
  { cmd = "Octo issue search",                         desc = "Issue · search issues" },
  { cmd = "Octo issue close",                          desc = "Issue · close issue" },
  { cmd = "Octo issue reopen",                         desc = "Issue · reopen issue" },
  { cmd = "Octo issue browser",                        desc = "Issue · open in GitHub browser" },

  -- ───── Octo misc ────────────────────────────────────────────────────────
  { cmd = "Octo search",                               desc = "GitHub · search (issues + PRs)" },
  { cmd = "Octo notification list",                    desc = "GitHub · list notifications" },
  { cmd = "Octo gist list",                            desc = "GitHub · list gists" },
  { cmd = "Octo repo list",                            desc = "GitHub · list your repositories" },

  -- ───── 🗒️ Zettelkasten (telekasten) ─────────────────────────────────────
  -- Fuzzy hint: "zettel"
  { cmd = "Telekasten goto_today",                     desc = "Zettel · daily note (today, active context)" },
  { cmd = "Telekasten goto_thisweek",                  desc = "Zettel · weekly note (this week)" },
  { cmd = "Telekasten goto_thismonth",                 desc = "Zettel · monthly note (this month)" },
  { cmd = "Telekasten switch_vault",                   desc = "Zettel · switch context (work/life/sport/general)" },
  { cmd = "Telekasten search_notes",                   desc = "Zettel · search all notes (full text)" },
  { cmd = "Telekasten find_notes",                     desc = "Zettel · find note by title" },
  { cmd = "Telekasten show_tags",                      desc = "Zettel · browse tags" },
  { cmd = "Telekasten show_backlinks",                 desc = "Zettel · backlinks to current note" },
  { cmd = "Telekasten show_calendar",                  desc = "Zettel · calendar" },
  { cmd = "Telekasten new_note",                       desc = "Zettel · new note" },
  { cmd = "ZkHelp",                                    desc = "Zettel · help cheatsheet panel" },

  -- ───── 🐍 Python ─────────────────────────────────────────────────────────
  -- Fuzzy hint: "python" / "venv"
  { cmd = "VenvSelect",                                desc = "Python · select venv (fix pyright imports)" },
  { cmd = "lua vim.lsp.buf.format()",                  desc = "Python · format buffer (ruff)" },
  { cmd = "lua vim.lsp.buf.code_action()",             desc = "Python · code action (auto-import / quick-fix)" },
  { cmd = "lua vim.lsp.buf.references()",              desc = "Python · find references (where used)" },
  { cmd = "lua vim.lsp.buf.rename()",                  desc = "Python · rename symbol (project-wide)" },
  { cmd = "lua vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())", desc = "Python · toggle inlay hints (inferred types)" },
  { cmd = "LspRestart",                                desc = "Python · restart LSP (pyright/ruff)" },

  -- ───── 🌳 Worktree ───────────────────────────────────────────────────────
  -- Fuzzy hint: "worktree"
  { cmd = "WtSwitch",                                  desc = "Worktree · fuzzy-switch cwd to another worktree" },
  { cmd = "BranchDiff 3dot",                         desc = "Worktree · review this branch vs base (PR-style diff)" },
}

local function palette_for_commander()
  local out = {}
  for _, e in ipairs(git_review_palette) do
    table.insert(out, { cmd = "<CMD>" .. e.cmd .. "<CR>", desc = e.desc, show = true })
  end
  return out
end

local function palette_for_legendary()
  local out = {}
  for _, e in ipairs(git_review_palette) do
    table.insert(out, { ":" .. e.cmd, description = e.desc })
  end
  return out
end

-- Group palette by category prefix → returns legendary `itemgroup` specs.
-- In `:Legendary` you'll see one entry per group (e.g. "🧪 Try Octo")
-- which expands when selected to show its commands. Massively cleaner UX
-- than 80+ flat entries.
local function build_legendary_itemgroups()
  local groups, order = {}, {}
  for _, e in ipairs(git_review_palette) do
    local prefix = e.desc:match("^(.-) ·")
    if prefix then
      if not groups[prefix] then
        groups[prefix] = {}
        table.insert(order, prefix)
      end
      table.insert(groups[prefix], { ":" .. e.cmd, description = e.desc })
    end
  end
  local out = {}
  for _, name in ipairs(order) do
    table.insert(out, {
      itemgroup = name,
      description = string.format("%s — %d items", name, #groups[name]),
      commands = groups[name],
    })
  end
  return out
end

-- Demo Lua functions surfaced in legendary (`:Legendary functions`).
-- Shows what's possible: copy URLs, jump to repo root, open in browser, etc.
local legendary_demo_funcs = {
  {
    function()
      local branch = vim.fn.systemlist({ "git", "rev-parse", "--abbrev-ref", "HEAD" })[1] or ""
      vim.fn.setreg("+", branch)
      vim.notify("Copied branch: " .. branch)
    end,
    description = "Func · copy current branch name to clipboard",
  },
  {
    function()
      local top = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })[1]
      if top and top ~= "" then
        vim.cmd("lcd " .. vim.fn.fnameescape(top))
        vim.notify("cwd → " .. top)
      end
    end,
    description = "Func · cd to git root (window-local)",
  },
  {
    function()
      local file = vim.fn.expand("%:p")
      local top = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })[1]
      if not top or top == "" then
        vim.notify("Not in a git repo", vim.log.levels.ERROR)
        return
      end
      local rel = file:sub(#top + 2)
      local branch = vim.fn.systemlist({ "git", "rev-parse", "--abbrev-ref", "HEAD" })[1]
      local remote = vim.fn.systemlist({ "git", "config", "--get", "remote.origin.url" })[1] or ""
      local org_repo = remote:match("github.com[:/]([^/]+/[^%.]+)")
      if not org_repo then
        vim.notify("Not a GitHub remote", vim.log.levels.ERROR)
        return
      end
      local line = vim.fn.line(".")
      local url = string.format("https://github.com/%s/blob/%s/%s#L%d", org_repo, branch, rel, line)
      vim.fn.setreg("+", url)
      vim.notify("Copied: " .. url)
    end,
    description = "Func · copy GitHub blob URL for current line",
  },
  {
    function()
      vim.cmd("!gh browse " .. vim.fn.shellescape(vim.fn.expand("%:p")) .. ":" .. vim.fn.line("."))
    end,
    description = "Func · open current line in GitHub browser (gh browse)",
  },
  {
    function()
      local out = vim.fn.systemlist({ "gh", "pr", "view", "--json", "number,title,url,state,headRefName" })
      vim.notify(table.concat(out, "\n"))
    end,
    description = "Func · gh pr view (current branch's PR, JSON)",
  },
  {
    function()
      local count = 0
      for _ in pairs(vim.api.nvim_get_commands({})) do
        count = count + 1
      end
      vim.notify("Total :user commands: " .. count)
    end,
    description = "Func · count all registered :user commands",
  },
  {
    function()
      require("legendary").repeat_previous()
    end,
    description = "Func · repeat last legendary item (same as :LegendaryRepeat)",
  },
}

-- Register EVERY palette entry as a real :User command so it shows up in
-- `<leader>fc` (Telescope :commands picker) — which only lists real vim
-- user commands. Naming derives from the description's category prefix:
--
--   "Try Octo · 1 — list PRs"         → :TryOcto1
--   "Git Diff · branch vs master"     → :GitDiff1, :GitDiff2, ...
--   "Review PR · list open"           → :ReviewPr1, :ReviewPr2, ...
--   "Git Hunk · preview hunk"         → :GitHunk1, ...
--
-- Fuzzy-search "try", "git diff", "review", "hunk", "blame" in <leader>fc.
local function register_palette_user_commands()
  local counters = {}
  for _, e in ipairs(git_review_palette) do
    local prefix = e.desc:match("^(.-) ·")
    if prefix then
      local clean = prefix:gsub("%s+", "")
      counters[clean] = (counters[clean] or 0) + 1
      local name = clean .. counters[clean]
      pcall(vim.api.nvim_create_user_command, name, e.cmd, { desc = e.desc, force = true })
    end
  end
end
register_palette_user_commands()

local commander = {
  "FeiyouG/commander.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
  keys = {
    { "<leader>fk", "<CMD>Telescope commander<CR>", mode = "n", desc = "Telescope command pallet" },
    -- {
    --       "<leader>fl",
    --       mode = {"n"},
    --       desc = "Search inside current buffer",
    --       cmd = "<CMD>Telescope current_buffer_fuzzy_find<CR>",
    -- },
  },

  config = function()
    local commander = require("commander")

    commander.setup({
      components = {
        "DESC",
        "KEYS",
        "CAT",
        "CMD",
        -- "SET",
      },
      sort_by = {
        "DESC",
        "KEYS",
        "CAT",
        "CMD",
      },
      -- Велике вікно замість зашитих у темі 20 рядків / center.
      -- M.config тут перемагає theme_opts у force-extend (див. theme.lua) →
      -- цей layout override спрацьовує. Resize у вікні: <M-r>/<M-R>.
      layout_strategy = "vertical",
      layout_config = {
        width = 0.9,
        height = 0.9,
        prompt_position = "top",
        mirror = false,
        preview_cutoff = 9999, -- палітрі прев'ю не треба — уся висота під список
      },
      integration = {
        telescope = {
          enable = true,
        },
        lazy = {
          enable = true,
          set_plugin_name_as_cat = true,
        },
      },
    })

    -- Git + Code-Review palette — no keybinds, discoverable via `<leader>fk`.
    commander.add(palette_for_commander())

    -- Mirror EVERY :user command into commander (searchable by NAME). Runs here,
    -- inside commander's own config, so setup + telescope extension are ready
    -- (no early force-load race). Deferred + PER-ITEM pcall so one malformed
    -- command can never corrupt the layer and break <leader>fk.
    vim.schedule(function()
      for name, def in pairs(vim.api.nvim_get_commands({})) do
        local desc = name
        if def.definition and def.definition ~= "" then
          desc = name .. "  —  " .. (def.definition:gsub("%s+", " "):sub(1, 60))
        end
        pcall(commander.add, { { cmd = "<CMD>" .. name .. "<CR>", desc = desc, cat = "cmd", show = true } })
      end
    end)
  end,
}

local legendary = {
  "mrjones2014/legendary.nvim",
  dependencies = { "kkharji/sqlite.lua", "stevearc/dressing.nvim" },

  config = function()
    local leg = require("legendary")
    -- ЄДИНИЙ setup (раніше було два — другий перетирав include_builtin, і вбудовані
    -- мапи зникали зі списку). Тепер повний список: builtin + усі lazy keys +
    -- зареєстровані команди + which-key групи.
    leg.setup({
      include_builtin = true, -- вбудовані vim-мапи у списку
      include_legendary_cmds = true, -- власні :Legendary* команди
      auto_register_which_key = true,
      keymaps = {
        -- vim.g.legendary_keymaps,

        -- map keys to a command
        -- { '<leader>ff', ':Telescope find_files<cr>', description = 'Telescope Find files' },
        { "<leader>fc", ":Telescope commands<cr>", description = "Telescope commands pallete" },
        {
          "<leader>fl",
          "<CMD>Telescope current_buffer_fuzzy_find<CR>",
          mode = { "n" },
          desc = "Search inside current buffer",
        },
        { "<leader>fr", "<cmd>Telescope oldfiles<CR>", mode = { "n" }, desc = "Telescope Recent files" },
        { "<leader>fs", "<cmd>Telescope session-lens<CR>", mode = { "n" }, desc = "Telescope search session" },

        -- map keys to a function
      },
      commands = {
        -- easily create user commands
        {
          ":SayHello",
          function()
            print("hello world!")
          end,
          description = "Say hello as a command",
        },

        {
          ":DeleteWhitespaces",
          function()
            print("Delete whitespaces in file")
            vim.api.nvim_command(":%s/\\s\\+$//e")
          end,
          description = "Delete whitespaces",
          mode = { "n" },
        },

        {
          ":SNV",
          ":source $MYVIMRC<cr>",
          description = "Reload nvim config",
          mode = "n",
        },

        {
          ":CWD",
          function()
            vim.cmd("Neotree focus reveal toggle show_hidden true")
          end,
          description = "Toggle show hidden files",
          mode = { "n" },
        },

        {
          ":Cls",
          ":qa",
          desc = "close all safe",
          mode = { "n" },
        },

        {
          ":Kll",
          ":qa!",
          desc = "close all without saves",
          mode = { "n" },
        },

        { ":glow", description = "preview markdown", filters = { ft = "markdown" } },
        -- { ':cls', ':qa!', description = 'close without saves'},
      },

      extensions = {
        -- automatically load keymaps from lazy.nvim's `keys` option
        lazy_nvim = true,
        -- load keymaps and commands from nvim-tree.lua
        nvim_tree = true,
        -- which_key = true,
        -- load commands from smart-splits.nvim
        -- and create keymaps, see :h legendary-extensions-smart-splits.nvim
        smart_splits = {
          directions = { "h", "j", "k", "l" },
          mods = {
            move = "<C>",
            resize = "<M>",
          },
        },
        which_key = {
          auto_register = true,
          do_binding = true,
          use_groups = true,
        },
        -- load commands from op.nvim
        op_nvim = true,
        -- load keymaps from diffview.nvim
        diffview = true,
      },
    })

    -- Git + Code-Review palette — flat list (good for direct text-search).
    leg.commands(palette_for_legendary())

    -- Same palette grouped — appears as itemgroups in `:Legendary`.
    -- Press <CR> on a group to drill into its commands. Cleaner than 80+ flat rows.
    for _, group in ipairs(build_legendary_itemgroups()) do
      leg.itemgroup(group)
    end

    -- Demo Lua functions — discoverable via `:Legendary functions`.
    leg.func(legendary_demo_funcs)
  end,
}

return {
  commander,
  legendary,
}
