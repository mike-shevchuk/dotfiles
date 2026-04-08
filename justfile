import '.justdir/stow.just'
import '.justdir/health.just'
import '.justdir/mise.just'

default:
    @just --list

# Setup core packages on a new system
setup: install-deps claude zsh tmux kitty lz yazi
    @echo "Core packages stowed successfully"

# Install stow if missing
install-deps:
    @command -v stow >/dev/null 2>&1 || just _install-stow
    @echo "Dependencies ready"

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
