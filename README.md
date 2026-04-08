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

# See all available commands
just
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
```

### Key Commands

| Command | What |
|---------|------|
| `just setup` | Install deps + stow core packages |
| `just health` | Check all dependencies |
| `just status` | Show stow status of all packages |
| `just all` | Stow everything |
| `just remove <pkg>` | Unstow a package |
| `just migrate` | Remove manual symlinks (one-time) |

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
