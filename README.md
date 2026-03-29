# dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/) and automated via [just](https://github.com/casey/just).

## Quick start

```bash
git clone <repo> ~/dotfiles
cd ~/dotfiles
just setup
```

This installs stow (if missing) and stows the core packages: `claude`, `zsh`, `tmux`, `kitty`, `lz`, `yazi`.

## Packages

| Package | Description | Target |
|---------|-------------|--------|
| `claude` | Claude Code settings, hooks, sounds, statusline, commands | `~/.claude/*`, `~/CLAUDE.md` |
| `zsh` | Zsh config, zinit plugins, zsh_spaces | `~/.zshrc`, `~/.zsh_spaces/` |
| `tmux` | Tmux config | `~/.tmux.conf`, `~/.tmux.conf.local` |
| `kitty` | Kitty terminal config | `~/.config/kitty/` |
| `lz` | LazyVIM neovim config | `~/.config/LazyVIM/` |
| `pnv` | PWNVIM neovim config | `~/.config/PWNVIM/` |
| `tnv` | TNVIM neovim config | `~/.config/TNVIM/` |
| `yazi` | Yazi file manager | `~/.config/yazi/` |
| `todoist` | Todoist CLI config | `~/.config/todoist/` |
| `fonts` | Nerd fonts | `~/.local/share/fonts/` |
| `hyperland` | Hyprland WM (Linux) | `~/.config/hypr/` |

## Usage

```bash
just setup          # Core packages
just all            # All packages
just claude         # Single package
just remove claude  # Unstow a package
```

## Structure

Each directory is a stow package. Files mirror the home directory structure:

```
dotfiles/
├── claude/
│   ├── .claude/
│   │   ├── settings.json
│   │   ├── hooks/
│   │   ├── sounds/
│   │   ├── statusline.sh
│   │   └── commands/
│   └── CLAUDE.md          → ~/CLAUDE.md
├── zsh/
│   └── .zshrc             → ~/.zshrc
├── tmux/
│   └── .tmux.conf         → ~/.tmux.conf
├── ...
└── justfile
```

All packages use `stow --no-folding` to create individual file symlinks without replacing entire directories.

## Private config

Files matching `*.private` and `*.secure` are gitignored. Private Claude context lives in a separate zetelekasten repo at `~/zetelekasten/claude_code/`.

## New system setup

1. Clone this repo to `~/dotfiles`
2. Run `just setup` (installs stow + core packages)
3. Clone zetelekasten repo to `~/zetelekasten` (for private Claude context)
4. Authenticate Claude Code: `claude login`
