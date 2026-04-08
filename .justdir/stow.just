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
        [tmux-sidebar]="tmux-plugins/tmux-sidebar"
    )
    for name in "${!plugins[@]}"; do
        if [ ! -d "$plugins_dir/$name" ]; then
            echo "  installing $name..."
            git clone --depth 1 "https://github.com/${plugins[$name]}" "$plugins_dir/$name"
        fi
    done
    # opensessions: clone + install deps + apply patches
    os_dir="$plugins_dir/opensessions"
    if [ ! -d "$os_dir" ]; then
        echo "  installing opensessions..."
        git clone "https://github.com/Ataraxy-Labs/opensessions.git" "$os_dir"
    fi
    if command -v bun >/dev/null 2>&1 || [ -x "$HOME/.bun/bin/bun" ]; then
        BUN="${HOME}/.bun/bin/bun"
        (cd "$os_dir" && "$BUN" install --frozen-lockfile 2>/dev/null || "$BUN" install 2>/dev/null) >/dev/null
    fi
    chmod +x "$os_dir"/integrations/tmux-plugin/scripts/*.sh 2>/dev/null || true
    # Apply local patches
    for patch in "{{justfile_directory()}}"/tmux/patches/*.patch; do
        [ -f "$patch" ] || continue
        if ! git -C "$os_dir" apply --check "$patch" 2>/dev/null; then
            echo "  patch already applied: $(basename "$patch")"
        else
            git -C "$os_dir" apply "$patch"
            echo "  applied: $(basename "$patch")"
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
