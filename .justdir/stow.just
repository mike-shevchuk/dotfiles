# --- Stow packages ---

# Claude Code settings, hooks, sounds, statusline, commands
claude:
    stow --no-folding --adopt --restow -t ~ claude

# Zsh config, plugins, spaces
zsh:
    stow --no-folding --adopt --restow -t ~ zsh

# Tmux config + plugins (tpm can't auto-discover plugins from .tmux.conf.local)
tmux:
    #!/usr/bin/env bash
    set -euo pipefail
    stow --no-folding --adopt --restow -t ~ tmux
    plugins_dir="$HOME/.tmux/plugins"
    declare -A plugins=(
        [tpm]="tmux-plugins/tpm"
        [tmux-resurrect]="tmux-plugins/tmux-resurrect"
        [tmux-continuum]="tmux-plugins/tmux-continuum"
        [tmux-yank]="tmux-plugins/tmux-yank"
    )
    for name in "${!plugins[@]}"; do
        if [ ! -d "$plugins_dir/$name" ]; then
            echo "  installing $name..."
            git clone --depth 1 "https://github.com/${plugins[$name]}" "$plugins_dir/$name"
        fi
    done
    echo "tmux config and plugins ready"

# Kitty terminal config
kitty:
    stow --no-folding --adopt --restow -t ~ kitty

# LazyVIM neovim config
lz:
    stow --no-folding --adopt --restow -t ~ lz

# PWNVIM neovim config
pnv:
    stow --no-folding --adopt --restow -t ~ pnv

# TNVIM neovim config
tnv:
    stow --no-folding --adopt --restow -t ~ tnv

# Yazi file manager config
yazi:
    stow --no-folding --adopt --restow -t ~ yazi

# Todoist config
todoist:
    stow --no-folding --adopt --restow -t ~ todoist

# Nerd fonts
fonts:
    stow --no-folding --adopt --restow -t ~ fonts

# Hammerspoon system monitor (macOS only)
hammerspoon:
    stow --no-folding --adopt --restow -t ~ hammerspoon

# Hyprland config (Linux only)
hyperland:
    stow --no-folding --adopt --restow -t ~ hyperland

# Stow all packages
all: claude zsh tmux kitty lz pnv tnv yazi todoist fonts hammerspoon hyperland
    @echo "All packages stowed"

# Unstow a package: just remove <pkg>
remove pkg:
    stow -D -t ~ {{pkg}}
