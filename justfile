import '.justdir/stow.just'
import '.justdir/health.just'
import '.justdir/mise.just'
import '.justdir/claude.just'
import '.justdir/codex.just'
import '.justdir/sync.just'
import '.justdir/verkada.just'

# mise, stow and mise's tools (bun…) land here before .zshrc puts them on PATH
export PATH := env('PATH') + ':' + env('HOME') + '/.local/bin:' + env('HOME') + '/.local/share/mise/shims'

# Default recipe: launch the fzf-powered recipe picker (`just help`)
default:
    @just help

# Setup core packages on a new system
setup: install-deps mise claude codex zsh tmux kitty lz yazi claudes-link hooks-install install-global
    @echo "Core packages stowed successfully"

# Install stow if missing
install-deps:
    @command -v stow >/dev/null 2>&1 || just _install-stow
    @echo "Dependencies ready"

# Symlink .justdir/global.just → ~/.config/just/justfile so `just -g` works everywhere
install-global:
    #!/usr/bin/env bash
    set -euo pipefail
    src="$HOME/dotfiles/.justdir/global.just"
    dst="$HOME/.config/just/justfile"
    echo "→ linking $dst → $src" >&2
    mkdir -p "$(dirname "$dst")"
    if [ -L "$dst" ]; then
        echo "  removing existing symlink" >&2
        rm "$dst"
    elif [ -f "$dst" ]; then
        echo "  backing up existing file to $dst.bak" >&2
        mv "$dst" "$dst.bak"
    fi
    ln -s "$src" "$dst"
    echo "  OK — try: jj   (or: just -g --list)" >&2

# --- Migration ---

# Remove existing manual symlinks so stow can take over (one-time migration)
migrate:
    #!/usr/bin/env bash
    set -euo pipefail
    dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    # destructive (mass rm of symlinks) — gum confirm when available
    if command -v gum >/dev/null 2>&1; then
        gum confirm "Видалити ВСІ ручні symlinks у \$HOME, що вказують у dotfiles?" || { echo "скасовано"; exit 0; }
    fi
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
    if command -v brew >/dev/null 2>&1; then sys="brew install stow"
    elif command -v apt >/dev/null 2>&1; then sys="sudo apt install -y stow"
    elif command -v pacman >/dev/null 2>&1; then sys="sudo pacman -S --noconfirm stow"
    else sys=""; fi
    via="${VIA:-}"
    case "$sys" in "brew "*) via="${via:-system}" ;; esac
    if [ -z "$via" ] && [ -n "$sys" ] && [ -t 0 ]; then
        printf '%s\n' "stow is missing (it links the configs into ~). Install it via:" \
            "  1) $sys  (default)" "  2) mise (no password, into ~/.local)" >&2
        while [ -z "$via" ]; do
            read -rp "1 or 2 [1]: " c || { echo "✗ nothing chosen" >&2; exit 1; }
            case "$c" in ""|1) via=system ;; 2) via=mise ;; esac
        done
    fi
    case "${via:-system}" in
        mise) cmd="just --justfile {{justfile()}} _stow-via-mise" ;;
        system) cmd="$sys" ;;
        *) echo "✗ VIA must be mise or system, got: $via" >&2; exit 1 ;;
    esac
    [ -n "$cmd" ] || { echo "✗ no brew/apt/pacman found — try: VIA=mise just setup" >&2; exit 1; }
    # show the command BEFORE a sudo password prompt, so it is clear what asks and why
    echo "→ installing stow: $cmd" >&2
    $cmd || {
        echo "✗ could not install stow: '$cmd' failed (see the error above)." >&2
        echo "  Nothing was linked yet. Retry with: VIA=mise just setup  or  VIA=system just setup" >&2
        exit 1
    }

# conda-forge has stow only for x86_64 (its perl comes along); not `mise use -g`,
# which would write into the stowed config.toml
[private]
_stow-via-mise: mise-install
    #!/usr/bin/env bash
    set -euo pipefail
    export MISE_EXPERIMENTAL=1
    if ! mise backends ls | grep -x conda >/dev/null; then
        echo "→ this mise is too old for conda packages: mise self-update" >&2
        mise self-update -y --no-plugins
    fi
    mise install conda:stow
    mkdir -p ~/.local/bin
    ln -sf "$(mise where conda:stow)/bin/stow" ~/.local/bin/stow
    ~/.local/bin/stow --version
