# Dotfiles

macOS + Linux dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Quick Start

```bash
cd ~/dotfiles

# Symlink a package (e.g. zsh configs → ~/.zshrc, ~/.zsh_zinit, etc.)
stow zsh

# Symlink everything
stow kitty yazi zsh tmux hammerspoon

# Dry run — see what would be linked without changing anything
stow --dry-run -v zsh
```

## Packages

| Package | Stows to | What |
|---------|----------|------|
| `zsh` | `~/.zshrc`, `~/.zsh_zinit`, `~/.zsh_spaces/` | ZSH config, zinit plugins, spaces (job/ssh modules) |
| `tmux` | `~/.tmux.conf`, `~/.tmux.conf.local` | tmux base config + local overrides with TPM |
| `kitty` | `~/.config/kitty/` | Kitty terminal config |
| `hammerspoon` | `~/.hammerspoon/` | Hammerspoon window mgmt, launchers, tools |
| `yazi` | `~/.config/yazi/` | Yazi file manager config |
| `hyperland` | `~/.config/hypr/` | Hyprland WM config (Linux) |
| `lz` | `~/.config/LazyVIM/` | LazyVIM neovim config |
| `tnv` | `~/.config/tnvim/` | TNVIM neovim config |
| `pnv` | `~/.config/pwnvim/` | PWNVIM neovim config |

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

### Plugins (TPM — via `.tmux.conf.local`)

| Plugin | What |
|--------|------|
| `tmux-resurrect` | Save/restore sessions (`prefix C-s` save, `prefix C-r` restore) |
| `tmux-continuum` | Auto-save sessions every 15 min |
| `tmux-yank` | System clipboard integration |

Install plugins: `prefix + I`

### DevOps Layouts

| Key | Layout |
|-----|--------|
| `prefix D` | 3-pane: editor top, logs + shell bottom |
| `prefix C-d` | 4-pane quad: for log tailing |

### Session Manager (`ts`)

```bash
ts    # fzf-pick a project dir → create/attach tmux session
      # if .tmux_setup.sh exists in the dir, it runs automatically
```

---

## Hammerspoon Cheatsheet

All hotkeys use **Alt+Shift** as modifier (referred to as `hyper` below).

### App Launchers

| Key | Action |
|-----|--------|
| `` hyper + ` `` | Dropdown terminal (Quake-style) |
| `hyper + G` | Toggle Ghostty |
| `hyper + B` | Toggle Thorium |
| `hyper + S` | Toggle Safari |
| `hyper + Space` | Command palette (fuzzy app launcher) |

### Window Management

| Key | Action |
|-----|--------|
| `hyper + Left/Right` | Left / right half |
| `hyper + Up` | Maximize |
| `hyper + Down` | Center |
| `ctrl+alt+shift + Left/Right` | Left / right third |
| `ctrl+alt+shift + Up/Down` | Left / right two-thirds |
| `hyper + [` / `]` | Move window to left / right screen |

### Tools

| Key | Action |
|-----|--------|
| `hyper + V` | Clipboard history |
| `hyper + K` | Paste bypass (type clipboard to defeat paste-blockers) |
| `hyper + J` | Scratchpad (floating notepad) |
| `hyper + Z` | Zettelkasten notetaker |
| `hyper + Q` | URL bookmarks |
| `hyper + W` | Pomodoro timer |
| `hyper + A` | Screenshot + annotate |
| `hyper + E` | Linear tasks widget |
| `hyper + D` | Brightness sliders |
| `hyper + F` | Mouse finder (flash crosshair) |

### System

| Key | Action |
|-----|--------|
| `hyper + L` | Toggle dark mode |
| `hyper + T` | Empty trash |
| `hyper + P` | Toggle pinch zoom |
| `hyper + M` | Toggle mute |
| `hyper + I` | Pick main display |
| `hyper + N` | Toggle mirror/extend displays |
| `hyper + H` | Hammerspoon console |
| `hyper + R` | Reload config |

Menubar: hammer icon = enabled, stop icon = all hotkeys disabled (guard toggle).

---

## ZSH Cheatsheet

### Spaces Architecture

ZSH config is split into "spaces" loaded from `~/.zsh_spaces/`:

- **job/** — work tools: AWS logs, git helpers, tmux manager, project auto-env
- **ssh/** — SSH utilities

### Job Space — AWS Logs

| Command | Action |
|---------|--------|
| `bb_aws_logs` | Interactive log stream picker with fzf preview |
| `bb_aws_logs_flow` | Live tail with ARN resolution |
| `bb_aws_fast_api` | Quick logs: fast-api lambda |
| `bb_aws_extractor` | Quick logs: data extractor lambda |
| `bb_aws_processor` | Quick logs: data processor lambda |
| `bb_aws_notify` | Quick logs: notification processor |
| `bb_aws_mqtt` | Quick logs: MQTT worker |
| `bb_aws_list` | List all configured log streams |
| `bb_aws_since <time>` | Set default time range (10m, 1h, 2d) |

Inside fzf log viewer: `ctrl+e` open in nvim, `ctrl+f` filter ERRORs, `ctrl+w` filter WARNs, `ctrl+i` filter INFOs.

### Job Space — Git

| Command | Action |
|---------|--------|
| `bb_git_push_origin [branch]` | Push branch with `-u` (fzf picker if no arg) |

### Job Space — Project Auto-Environment

Auto-activates on `cd` based on marker files in the directory:

| Marker file | Action |
|-------------|--------|
| `.venv/` | Activate Python virtualenv (deactivate on leave) |
| `.aws-profile` | Set `AWS_PROFILE` from file contents |
| `.docker-context` | Switch docker context |
| `.kube-context` | Switch kubectl context |

### SSH Utilities

| Command | Action |
|---------|--------|
| `ssh-add-all` | Add all private keys from `~/.ssh/` |
| `ssh-tunnel <host> <port> [remote]` | Quick SSH port forward |
| `ssh-hosts` | fzf picker from `~/.ssh/config` |

---

## Kitty Cheatsheet

Prefix is `ctrl+a`.

### Splits & Windows

| Key | Action |
|-----|--------|
| `ctrl+a s` | Split horizontal |
| `ctrl+a v` | Split vertical |
| `ctrl+a x` | Close pane (confirm) |
| `ctrl+a z` | Toggle zoom (stack layout) |
| `ctrl+h/j/k/l` | Navigate panes |
| `ctrl+a shift+h/j/k/l` | Move pane |
| `ctrl+shift+h/j/k/l` | Resize pane |

### Tabs

| Key | Action |
|-----|--------|
| `ctrl+a n` | New tab |
| `ctrl+a ,` | Rename tab |
| `ctrl+a !` | Detach pane to new tab |
| `cmd+1-9` | Go to tab N |
| `cmd+[` / `]` | Previous / next tab |
| `ctrl+q` | Last tab |

### Scrollback

| Key | Action |
|-----|--------|
| `alt+j` / `k` | Scroll down / up |
| `alt+i` / `u` | Page up / down |
| `alt+shift+k` / `j` | Jump to prev / next prompt |
| `ctrl+a Enter` | Open scrollback in nvim |
| `ctrl+a k` | Last command output in nvim |
| `ctrl+a /` | Search scrollback in nvim |

### Copy / Paste

| Key | Action |
|-----|--------|
| `cmd+c` | Copy last command output |
| `cmd+v` | Paste |
| `cmd+shift+c` | Copy selection |

---

## Yazi Cheatsheet

### Navigation

| Key | Action |
|-----|--------|
| `h` / `l` | Parent dir / open |
| `j` / `k` | Down / up |
| `gg` / `G` | First / last |
| `ctrl+d` / `u` | Page down / up |
| `/` | Search |
| `n` / `N` | Next / previous match |
| `.` | Toggle hidden files |

### File Operations

| Key | Action |
|-----|--------|
| `a` | Create file |
| `A` | Create directory |
| `r` | Rename |
| `dd` | Delete |
| `yy` | Yank (copy) |
| `pp` | Paste |
| `x` | Cut |
| `u` / `U` | Undo / redo |
| `z` / `Z` | Zip / unzip |
| `yw` | Copy filename |
| `yp` | Copy absolute path |
| `ss` | Create symlink |

### Tabs & Panes

| Key | Action |
|-----|--------|
| `T` | New tab |
| `gt` / `gT` | Next / previous tab |
| `ctrl+h/j/k/l` | Focus pane |
| `tab` | Toggle preview |
| `q` | Quit |

---

## Hyprland Cheatsheet

Super = Windows/Meta key.

### Core

| Key | Action |
|-----|--------|
| `Super+Return` | Terminal (Kitty) |
| `Super+D` | App launcher (rofi) |
| `Super+Q` | Kill window |
| `Super+F` | Fullscreen |
| `Super+Shift+F` | Toggle floating |
| `Super+E` | Quick edit Hyprland config |

### Navigation

| Key | Action |
|-----|--------|
| `Super+Left/Right/Up/Down` | Focus window |
| `Super+1-0` | Switch workspace |
| `Super+Tab` / `Shift+Tab` | Next / previous workspace |
| `Alt+Tab` | Cycle group |
| `Super+U` | Toggle special workspace |

### Window Management

| Key | Action |
|-----|--------|
| `Super+Shift+Left/Right/Up/Down` | Resize window |
| `Super+Ctrl+Left/Right/Up/Down` | Move window |
| `Super+Shift+1-0` | Move window to workspace |
| `Super+G` | Toggle group |
| `Super+M` | Split ratio |
| `Super+LMB drag` | Move window |
| `Super+RMB drag` | Resize window |

### Utilities

| Key | Action |
|-----|--------|
| `Super+Print` | Screenshot |
| `Super+Shift+S` | Screenshot area (swappy) |
| `Ctrl+Alt+L` | Lock screen |
| `Ctrl+Alt+P` | Logout menu |
| `Super+B` | Toggle waybar |
| `Super+W` | Wallpaper selector |
| `Super+Alt+V` | Clipboard manager |
| `Super+H` | Key hints |

---

## Neovim Configs

Three configs available, switchable via `NVIM_APPNAME`:

```bash
# LazyVIM (default full IDE)
NVIM_APPNAME=LazyVIM nvim

# TNVIM (lightweight)
NVIM_APPNAME=tnvim nvim

# PWNVIM
NVIM_APPNAME=pwnvim nvim
```

Stow packages: `lz` (LazyVIM), `tnv` (TNVIM), `pnv` (PWNVIM).
