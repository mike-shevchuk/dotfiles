# --- Stow packages ---

# Claude Code settings, hooks, sounds, statusline, commands
claude:
    stow --no-folding --adopt --restow -t ~ claude

# Stow Codex configuration into ~/.codex
codex:
    #!/usr/bin/env bash
    set -euo pipefail
    config="$HOME/.codex/config.toml"
    if [ -f "$config" ] && [ ! -L "$config" ]; then
        backup="$config.pre-stow-$(date +%Y%m%d-%H%M%S)"
        mv "$config" "$backup"
        echo "Backed up existing Codex config to $backup"
    fi
    stow --no-folding --restow -t ~ codex

# Zsh config, plugins, spaces
zsh:
    stow --no-folding --adopt --restow -t ~ zsh

# Tmux config + plugins (tpm can't auto-discover plugins from .tmux.conf.local)
tmux:
    #!/usr/bin/env bash
    set -euo pipefail
    stow --no-folding --adopt --restow -t ~ tmux
    plugins_dir="$HOME/.tmux/plugins"
    plugins="
        tpm=tmux-plugins/tpm
        tmux-yank=tmux-plugins/tmux-yank
        tmux-sidebar=tmux-plugins/tmux-sidebar
    "
    # Disabled plugins (uncomment in .tmux.conf.local to re-enable):
    #   tmux-resurrect=tmux-plugins/tmux-resurrect  — session save/restore across reboots
    #   tmux-continuum=tmux-plugins/tmux-continuum   — auto-saves sessions every N min
    for entry in $plugins; do
        name="${entry%%=*}"
        repo="${entry#*=}"
        if [ ! -d "$plugins_dir/$name" ]; then
            echo "  installing $name..."
            git clone --depth 1 "https://github.com/$repo" "$plugins_dir/$name"
        fi
    done
    # opensessions: clone + install deps + apply patches
    os_dir="$plugins_dir/opensessions"
    if [ ! -d "$os_dir" ]; then
        echo "  installing opensessions..."
        git clone "https://github.com/Ataraxy-Labs/opensessions.git" "$os_dir"
    fi
    # bun from PATH (mise, pacman…) first; ~/.bun is only the curl installer's spot
    BUN=$(command -v bun || { [ -x "$HOME/.bun/bin/bun" ] && echo "$HOME/.bun/bin/bun"; } || true)
    if [ -n "$BUN" ]; then
        echo "  opensessions deps: (cd $os_dir && $BUN install)" >&2
        (cd "$os_dir" && { "$BUN" install --frozen-lockfile >/dev/null || "$BUN" install >/dev/null; }) \
            || echo "  WARN: bun install failed (opensessions sidebar may not work)" >&2
    else
        echo "  WARN: no bun — skipped opensessions deps" >&2
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

# fastfetch: LAN IP, gateway, DNS, Wi-Fi, load, memory pressure, Claude/tmux sessions
fastfetch:
    stow --no-folding --adopt --restow -t ~ fastfetch

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
all: claude codex zsh tmux kitty lz pnv tnv yazi fastfetch todoist fonts hammerspoon hyperland
    @echo "All packages stowed"

# Unstow a package: just remove <pkg>
remove pkg:
    stow -D -t ~ {{pkg}}
