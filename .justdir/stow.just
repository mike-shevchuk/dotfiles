# --- Stow packages ---

# Stow one package with the REPO as the source of truth. Never use --adopt:
# it moves a pre-existing local file INTO the repo, overwriting the tracked
# config (a fresh Claude Code install's 3-line settings.json once replaced the
# real 158-line one that way). Instead, every real file sitting where a link
# must go is moved aside to <file>.pre-stow-<timestamp>, then stow links in.
[private]
_stow pkg:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    ts=$(date +%Y%m%d-%H%M%S)
    # dry run lists conflicts as "... over existing target <rel> since ..."
    conflicts=$(stow -n --no-folding --restow -t ~ "{{pkg}}" 2>&1 \
        | sed -n 's/.* over existing target \(.*\) since .*/\1/p' || true)
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        mv "$HOME/$rel" "$HOME/$rel.pre-stow-$ts"
        echo "  backed up ~/$rel → ~/$rel.pre-stow-$ts" >&2
    done <<< "$conflicts"
    # any conflict the dry run didn't name makes this fail loudly — never adopts
    stow --no-folding --restow -t ~ "{{pkg}}"

# Claude Code settings, hooks, sounds, statusline, commands
claude:
    @just --justfile "{{justfile()}}" _stow claude

# Stow Codex configuration into ~/.codex
codex:
    @just --justfile "{{justfile()}}" _stow codex

# Zsh config, plugins, spaces
zsh:
    @just --justfile "{{justfile()}}" _stow zsh

# Tmux config + plugins (tpm can't auto-discover plugins from .tmux.conf.local)
tmux:
    #!/usr/bin/env bash
    set -euo pipefail
    just --justfile "{{justfile()}}" _stow tmux
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
    @just --justfile "{{justfile()}}" _stow kitty

# LazyVIM neovim config
lz:
    @just --justfile "{{justfile()}}" _stow lz

# PWNVIM neovim config
pnv:
    @just --justfile "{{justfile()}}" _stow pnv

# TNVIM neovim config
tnv:
    @just --justfile "{{justfile()}}" _stow tnv

# Yazi file manager config
yazi:
    @just --justfile "{{justfile()}}" _stow yazi

# Todoist config
todoist:
    @just --justfile "{{justfile()}}" _stow todoist

# Nerd fonts
fonts:
    @just --justfile "{{justfile()}}" _stow fonts

# Hammerspoon system monitor (macOS only)
hammerspoon:
    @just --justfile "{{justfile()}}" _stow hammerspoon

# Hyprland config (Linux only)
hyperland:
    @just --justfile "{{justfile()}}" _stow hyperland

# Stow all packages
all: claude codex zsh tmux kitty lz pnv tnv yazi todoist fonts hammerspoon hyperland
    @echo "All packages stowed"

# Unstow a package: just remove <pkg>
remove pkg:
    stow -D -t ~ {{pkg}}
