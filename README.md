# Dotfiles

macOS + Linux dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/) and [just](https://github.com/casey/just).

## Quick Start

```bash
cd ~/dotfiles

# Setup everything on a new machine
just setup

# Or stow individual packages
just zsh
just tmux
just lz

# Check system health
just health

# Browse recipes interactively (fzf-powered, runs on Enter)
just help

# Pull + push both ~/dotfiles and ~/zettelkasten
just sync
```

## Packages

| Package | Stows to | What |
|---------|----------|------|
| `claude` | `~/.claude/` | Claude Code settings, hooks, sounds, statusline |
| `zsh` | `~/.zshrc`, `~/.zsh_zinit`, `~/.zsh_spaces/` | ZSH config, zinit plugins, spaces (job/ssh modules) |
| `tmux` | `~/.tmux.conf`, `~/.tmux.conf.local` | tmux base config + local overrides with TPM |
| `kitty` | `~/.config/kitty/` | Kitty terminal config |
| `lz` | `~/.config/LazyVIM/` | LazyVIM neovim config (primary IDE) |
| `tnv` | `~/.config/TNVIM/` | TNVIM neovim config (lightweight) |
| `pnv` | `~/.config/PWNVIM/` | PWNVIM neovim config |
| `yazi` | `~/.config/yazi/` | Yazi file manager config |
| `todoist` | `~/.config/todoist/` | Todoist config |
| `fonts` | `~/.local/share/fonts/` | Nerd fonts |
| `hammerspoon` | `~/.hammerspoon/` | Hammerspoon window mgmt, launchers (macOS) |
| `hyperland` | `~/.config/hypr/` | Hyprland WM config (Linux) |

## Justfile Structure

Justfile is modular — recipes split into `.justdir/`:

```
justfile                   # core: setup, migrate, install-deps
.justdir/
  stow.just                # all stow package recipes + all + remove
  health.just              # status + health diagnostics
  mise.just                # mise tool manager + nvim/ruff install
  sync.just                # multi-machine sync, fzf help, claudes/ symlinks, hooks-install
.githooks/
  pre-push                 # warns when ~/zettelkasten has unpushed commits (dotfiles only)
```

### Key Commands

| Command | What |
|---------|------|
| `just` (no args) | Open fzf recipe picker (alias for `just help`) |
| `just help` | Browse all recipes with fzf preview, run on Enter |
| `just setup` | Install deps + stow core packages + link CLAUDE.md files |
| `just sync` | `git pull --rebase --autostash` + push for both repos |
| `just sync-pull` | Pull-only variant (safe to run from shell startup hooks) |
| `just claudes-link` | (Re)create CLAUDE.md symlinks from `claudes/*/.target` |
| `just claudes-status` | Show health of every linked CLAUDE.md |
| `just claudes-add <name> <path>` | Register a new repo's CLAUDE.md under `claudes/` |
| `just hooks-install` | Activate `.githooks/` for ~/dotfiles (pre-push zettelkasten check) |
| `just health` | Check all dependencies |
| `just status` | Show stow status of all packages |
| `just all` | Stow everything |
| `just remove <pkg>` | Unstow a package |
| `just migrate` | Remove manual symlinks (one-time) |

---

## Multi-machine Sync

Two machines (Mac + Linux) share `~/dotfiles` (this repo) and `~/zettelkasten`
(private notes). Both are git-backed; `just sync` keeps them aligned.

### Daily workflow

```bash
just sync     # pull --rebase --autostash + push, for BOTH repos
```

`sync` is verbose by design — it announces each step, prints the resolved
`git` command before running, and indents the output so you can see exactly
what happened. If a rebase conflict shows up, sync stops and you resolve
it manually (`git rebase --continue` / `--abort`), then re-run.

### Auto-pull on shell startup (opt-in)

`zsh/.zsh_spaces/sync/sync-space.zsh` runs a background pull on every new
interactive shell — pulls only, never pushes, so it's safe to leave on.
Enable in your `~/.zshrc` (or any sourced file):

```zsh
export DOTFILES_AUTO_PULL=1
```

To customize repos:

```zsh
export DOTFILES_AUTO_PULL_REPOS="$HOME/dotfiles $HOME/zettelkasten $HOME/work-notes"
```

To disable for a single shell: `DOTFILES_AUTO_PULL=0 zsh`.

### CLAUDE.md storage — `claudes/` in zettelkasten

Source-of-truth for every `CLAUDE.md` (global + per-repo) lives under
`~/zettelkasten/claude_code/claudes/{name}/`:

```
~/zettelkasten/claude_code/claudes/
  global/
    CLAUDE.md          # ~/CLAUDE.md content
    .target            # "~/CLAUDE.md"
  rescue-serverless/
    CLAUDE.md
    .target            # "~/code/rescue-serverless/CLAUDE.md"
```

`.target` is a single line saying where the symlink should live (`~` is
expanded at runtime, so the same file works on every machine). On a fresh
checkout:

```bash
just claudes-link        # reads every .target, makes the symlinks
just claudes-status      # green = OK, yellow = drift, red = broken
```

### Adding a new repo to the sync

```bash
cd ~/code/some-repo
just -f ~/dotfiles/justfile claudes-add some-repo ./CLAUDE.md
# → moves CLAUDE.md into zettelkasten, replaces it with a symlink,
#   writes .target, commits + pushes zettelkasten
```

Now every machine that runs `just sync && just claudes-link` will have the
same `CLAUDE.md` at `~/code/some-repo/CLAUDE.md`.

### Pre-push hook — warns if zettelkasten is behind

`just hooks-install` (run automatically by `just setup`) sets
`core.hooksPath` to `~/dotfiles/.githooks/`. The included `pre-push`
script blocks no pushes — it just warns when `~/zettelkasten` has
unpushed commits, so you don't ship dotfiles changes that reference
content the second machine can't fetch yet:

```
⚠  ~/zettelkasten has 2 unpushed commit(s)

   a1b2c3d Register rescue-serverless CLAUDE.md under claudes/
   d4e5f6a Update global CLAUDE.md week numbering note

   If your dotfiles changes reference new claudes/ content,
   push zettelkasten first or the second machine will see stale content.

Push ~/zettelkasten now? [y/N/a=abort]
```

Bypass for one push:  `DOTFILES_SKIP_ZK_CHECK=1 git push`
Disable entirely:     `git -C ~/dotfiles config --unset core.hooksPath`

### Avoiding overwrites between machines

| Risk | Mitigation |
|------|------------|
| Editing without pulling first → divergence | `just sync` (or auto-pull on shell start) |
| Force-push wiping the other machine's commits | Never `--force` to master; PR for shared changes |
| Machine-specific tweaks polluting the synced file | Keep them in `~/.claude/settings.local.json` (gitignored) |
| Symlink drift between machines | `just claudes-status` flags it; `just claudes-link` fixes it |
| Pushing dotfiles before zettelkasten | `pre-push` hook warns and offers to push zettelkasten first |

---

## Mise (Tool Version Manager)

[mise](https://mise.jdx.dev) manages tool versions (like pyenv/nvm but for everything).

### Commands

| Command | What |
|---------|------|
| `just mise-install` | Install mise |
| `just nvim-install` | Install Neovim 0.12 via mise |
| `just nvim-install 0.11.3` | Install specific version |
| `just nvim-versions` | Show available neovim versions |
| `just ruff-install` | Install ruff (Python linter+formatter) |
| `just mise-ls` | Show all installed tools |

### Mise Cheatsheet

```bash
mise install <tool>@<ver>    # install a version
mise use <tool>@<ver>        # install + pin in .mise.toml (project-local)
mise use -g <tool>@<ver>     # install + set global default
mise ls                      # list installed tools
mise ls-remote <tool>        # list available versions
mise current                 # show active versions
mise up                      # upgrade all tools
mise prune                   # remove unused versions
mise rm <tool>               # remove tool completely
```

mise auto-switches versions per directory via `.mise.toml`.

---

## Claude Code

Claude Code CLI with custom hooks, statusline, and sound notifications.

### Hooks

| Hook | Trigger | Action |
|------|---------|--------|
| Notification | Claude sends notification | Sound + OS notification |
| Stop | Chat response finished | Sound + message preview |
| SubagentStop | Subagent completes | Sound + agent type info |

### Statusline (3 lines)

1. **Git status** — repo, branch, dirty state, ahead/behind, last commit age
2. **Model + tokens** — model name, PR number, token usage, subscription countdown
3. **Rate limits** — 5h/7d windows with progress bars, pace multiplier, reset times

### Settings

- Effort level: high
- Voice: enabled
- Plugins: context7, code-review, code-simplifier, playwright, superpowers, huggingface, claude-md-management

---

## Tmux Cheatsheet

Prefix is `C-a` (ctrl+a).

### Navigation

| Key | Action |
|-----|--------|
| `prefix c` | New window |
| `prefix C-c` | New session |
| `prefix C-f` | Find session |
| `prefix BTab` | Last session |
| `prefix Tab` | Last window |
| `prefix -` | Split horizontal |
| `prefix _` | Split vertical |
| `prefix h/j/k/l` | Navigate panes |
| `prefix H/J/K/L` | Resize panes |
| `prefix C-h` / `C-l` | Previous / next window |
| `prefix >` / `<` | Swap pane down / up |
| `prefix +` | Maximize pane |

### Copy Mode

| Key | Action |
|-----|--------|
| `prefix Enter` | Enter copy mode |
| `v` | Begin selection |
| `C-v` | Rectangle toggle |
| `y` | Copy selection |
| `H` / `L` | Start / end of line |
| `Esc` | Cancel |
| `prefix b` | List buffers |
| `prefix p` | Paste buffer |
| `prefix P` | Choose buffer |

### Plugins (TPM)

| Plugin | What |
|--------|------|
| `tmux-resurrect` | Save/restore sessions (`prefix C-s` save, `prefix C-r` restore) |
| `tmux-continuum` | Auto-save sessions every 15 min |
| `tmux-yank` | System clipboard integration |

Install plugins: `prefix + I`

### Layouts

| Key | Layout |
|-----|--------|
| `prefix D` | 3-pane: editor top, logs + shell bottom |
| `prefix C-d` | 4-pane quad: for log tailing |
| `prefix C` | 3-pane Claude Code: nvim top, claude + shell bottom |

### Session Manager (`tma`)

```bash
tma    # fzf-pick a tmux session to attach
```

---

## Neovim (LazyVIM)

Primary config: `lz` package. Requires Neovim 0.12+.

### LSP Servers

| Server | Language |
|--------|----------|
| `lua_ls` | Lua |
| `pyright` | Python (types) |
| `ruff` | Python (lint + format, replaces flake8+black) |
| `ts_ls` | TypeScript/JavaScript |
| `html` | HTML |
| `cssls` | CSS |
| `jsonls` | JSON |
| `yamlls` | YAML |
| `bashls` | Bash |
| `dockerls` | Docker |
| `marksman` | Markdown |

### Python Toolchain

- **ruff** — primary linter + formatter (fast, Rust-based)
- **black** — fallback formatter (commented in config)
- **flake8** — fallback linter (commented in config)

Switch by uncommenting in `lz/.config/LazyVIM/lua/plugins/lsp.lua`.

### Key Plugins

| Plugin | What |
|--------|------|
| `nvim-lspconfig` + `mason` | LSP auto-setup |
| `nvim-cmp` | Completion engine |
| `telescope.nvim` | Fuzzy finder |
| `neo-tree.nvim` | File explorer |
| `windsurf.nvim` | AI code completion |
| `codecompanion.nvim` | AI chat (GPT-4o) |
| `diffview.nvim` | Git diff viewer |
| `noice.nvim` | UI enhancements |
| `lualine.nvim` | Status bar with system monitor |
| `treesitter` | Syntax highlighting |

### LSP Keybindings

| Key | Action |
|-----|--------|
| `K` | Hover |
| `<leader>gd` | Go to definition |
| `<leader>gD` | Go to declaration |
| `<leader>gi` | Go to implementation |
| `<leader>gr` | Find references |
| `<leader>ca` | Code action |
| `<leader>rn` | Rename symbol |
| `<leader>lf` | Format file |
| `[d` / `]d` | Prev / next diagnostic |
| `<leader>dl` | Show line diagnostic |

### Switching Configs

```bash
NVIM_APPNAME=LazyVIM nvim    # LazyVIM (full IDE)
NVIM_APPNAME=TNVIM nvim      # TNVIM (lightweight)
NVIM_APPNAME=PWNVIM nvim     # PWNVIM
```

---

## Hammerspoon Cheatsheet (macOS)

All hotkeys use **Alt+Shift** (`hyper`).

### App Launchers

| Key | Action |
|-----|--------|
| `` hyper + ` `` | Dropdown terminal (Quake-style) |
| `hyper + G` | Toggle Ghostty |
| `hyper + B` | Toggle Thorium |
| `hyper + S` | Toggle Safari |
| `hyper + Space` | Command palette |

### Window Management

| Key | Action |
|-----|--------|
| `hyper + Left/Right` | Left / right half |
| `hyper + Up` | Maximize |
| `hyper + Down` | Center |
| `hyper + [` / `]` | Move to left / right screen |

### Tools

| Key | Action |
|-----|--------|
| `hyper + V` | Clipboard history |
| `hyper + K` | Paste bypass |
| `hyper + J` | Scratchpad |
| `hyper + Z` | Zettelkasten |
| `hyper + W` | Pomodoro |
| `hyper + A` | Screenshot + annotate |
| `hyper + R` | Reload config |

---

## ZSH

### Spaces Architecture

ZSH config split into "spaces" loaded from `~/.zsh_spaces/`:

- **job/** — work tools: AWS logs, git helpers, tmux manager, project auto-env
- **ssh/** — SSH utilities

### Project Auto-Environment

Auto-activates on `cd` based on marker files:

| Marker | Action |
|--------|--------|
| `.venv/` | Activate Python virtualenv |
| `.aws-profile` | Set `AWS_PROFILE` |
| `.docker-context` | Switch docker context |
| `.kube-context` | Switch kubectl context |

### AWS Log Viewer

```bash
bb_aws_logs        # Interactive log stream picker with fzf
bb_aws_logs_flow   # Live tail with ARN resolution
bb_aws_since 1h    # Set default time range
```

Inside fzf: `ctrl+e` open in nvim, `ctrl+f` filter ERRORs, `ctrl+w` WARNs, `ctrl+i` INFOs.

---

## Kitty Cheatsheet

Prefix is `ctrl+a`.

### Splits & Tabs

| Key | Action |
|-----|--------|
| `ctrl+a s` | Split horizontal |
| `ctrl+a v` | Split vertical |
| `ctrl+a x` | Close pane |
| `ctrl+a z` | Toggle zoom |
| `ctrl+h/j/k/l` | Navigate panes |
| `ctrl+a n` | New tab |
| `cmd+1-9` | Go to tab N |

### Scrollback

| Key | Action |
|-----|--------|
| `alt+j/k` | Scroll down/up |
| `ctrl+a Enter` | Open scrollback in nvim |
| `ctrl+a k` | Last command output in nvim |
| `ctrl+a /` | Search scrollback in nvim |

---

## Yazi Cheatsheet

| Key | Action |
|-----|--------|
| `h/l` | Parent dir / open |
| `j/k` | Down / up |
| `/` | Search |
| `.` | Toggle hidden |
| `a` / `A` | Create file / directory |
| `r` | Rename |
| `dd` | Delete |
| `yy` / `pp` | Copy / paste |
| `yp` | Copy absolute path |
| `T` | New tab |
| `q` | Quit |

---

## Hyprland Cheatsheet (Linux)

Super = Windows/Meta key.

| Key | Action |
|-----|--------|
| `Super+Return` | Terminal (Kitty) |
| `Super+D` | App launcher (rofi) |
| `Super+Q` | Kill window |
| `Super+F` | Fullscreen |
| `Super+1-0` | Switch workspace |
| `Super+Shift+Left/Right/Up/Down` | Resize window |
| `Super+Ctrl+Left/Right/Up/Down` | Move window |
| `Super+Print` | Screenshot |
| `Super+Shift+S` | Screenshot area |
