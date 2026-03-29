default:
    @just --list

# Setup core packages on a new system
setup: install-deps claude zsh tmux kitty lz yazi
    @echo "Core packages stowed successfully"

# Install stow if missing
install-deps:
    @command -v stow >/dev/null 2>&1 || just _install-stow
    @echo "Dependencies ready"

# --- Packages ---

# Claude Code settings, hooks, sounds, statusline, commands
claude:
    stow --no-folding --restow -t ~ claude

# Zsh config, plugins, spaces
zsh:
    stow --no-folding --restow -t ~ zsh

# Tmux config
tmux:
    stow --no-folding --restow -t ~ tmux

# Kitty terminal config
kitty:
    stow --no-folding --restow -t ~ kitty

# LazyVIM neovim config
lz:
    stow --no-folding --restow -t ~ lz

# PWNVIM neovim config
pnv:
    stow --no-folding --restow -t ~ pnv

# TNVIM neovim config
tnv:
    stow --no-folding --restow -t ~ tnv

# Yazi file manager config
yazi:
    stow --no-folding --restow -t ~ yazi

# Todoist config
todoist:
    stow --no-folding --restow -t ~ todoist

# Nerd fonts
fonts:
    stow --no-folding --restow -t ~ fonts

# Hyprland config (Linux only)
hyperland:
    stow --no-folding --restow -t ~ hyperland

# --- Bulk operations ---

# Stow all packages
all: claude zsh tmux kitty lz pnv tnv yazi todoist fonts hyperland
    @echo "All packages stowed"

# --- Remove ---

# Unstow a package: just remove <pkg>
remove pkg:
    stow -D -t ~ {{pkg}}

# --- Migration ---

# Remove existing manual symlinks so stow can take over (one-time migration)
migrate:
    #!/usr/bin/env bash
    set -euo pipefail
    dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    echo "Removing manual symlinks pointing into dotfiles..."
    count=0
    while IFS= read -r -d '' link; do
        target=$(readlink "$link" 2>/dev/null || true)
        if [[ "$target" == "$dotfiles_dir"/* ]] || [[ "$target" == *"/dotfiles/"* ]]; then
            echo "  removing: $link → $target"
            rm "$link"
            count=$((count + 1))
        fi
    done < <(find ~ -maxdepth 3 -type l -print0 2>/dev/null)
    echo "Removed $count manual symlinks. Run 'just setup' now."

# --- Internal ---

[private]
_install-stow:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Installing stow..."
    if command -v brew >/dev/null 2>&1; then
        brew install stow
    elif command -v apt >/dev/null 2>&1; then
        sudo apt install -y stow
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm stow
    else
        echo "Could not install stow automatically. Install it manually."
        exit 1
    fi
