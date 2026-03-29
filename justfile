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

# --- Status ---

# Show which packages are stowed, broken, or missing
status:
    #!/usr/bin/env bash
    dotfiles_dir="{{justfile_directory()}}"
    stowed=0; manual=0; missing=0; broken=0

    green='\033[32m'; yellow='\033[33m'; red='\033[31m'; dim='\033[2m'; reset='\033[0m'

    printf "\n  %-12s  %-8s  %s\n" "PACKAGE" "STATUS" "DETAILS"
    printf "  %-12s  %-8s  %s\n" "-------" "------" "-------"

    check_pkg() {
        local pkg="$1" target="$2"
        local full_path="$HOME/$target"

        if [ ! -d "$dotfiles_dir/$pkg" ]; then
            printf "  %-12s  ${dim}%-8s${reset}  %s\n" "$pkg" "n/a" "package dir not found"
            return
        fi

        if [ -L "$full_path" ]; then
            local link_target
            link_target=$(readlink "$full_path")
            case "$link_target" in
                *"$dotfiles_dir/$pkg/"*|*"/dotfiles/$pkg/"*)
                    if [ -e "$full_path" ]; then
                        printf "  %-12s  ${green}%-8s${reset}  %s\n" "$pkg" "stowed" "~/$target"
                        stowed=$((stowed + 1))
                    else
                        printf "  %-12s  ${red}%-8s${reset}  %s\n" "$pkg" "broken" "symlink target missing"
                        broken=$((broken + 1))
                    fi ;;
                *)
                    printf "  %-12s  ${yellow}%-8s${reset}  %s\n" "$pkg" "manual" "~/$target (not stow-managed, run 'just migrate')"
                    manual=$((manual + 1)) ;;
            esac
        elif [ -e "$full_path" ]; then
            printf "  %-12s  ${yellow}%-8s${reset}  %s\n" "$pkg" "exists" "~/$target is a regular file (run 'just migrate')"
            manual=$((manual + 1))
        else
            printf "  %-12s  ${dim}%-8s${reset}  %s\n" "$pkg" "missing" "run 'just $pkg' to stow"
            missing=$((missing + 1))
        fi
    }

    check_pkg claude  ".claude/settings.json"
    check_pkg zsh     ".zshrc"
    check_pkg tmux    ".tmux.conf"
    check_pkg kitty   ".config/kitty/kitty.conf"
    check_pkg lz      ".config/LazyVIM/init.lua"
    check_pkg pnv     ".config/PWNVIM/init.lua"
    check_pkg tnv     ".config/TNVIM/init.lua"
    check_pkg yazi    ".config/yazi/yazi.toml"
    check_pkg todoist ".config/todoist/config.json"
    check_pkg fonts   ".local/share/fonts/HackNerdFont-Regular.ttf"
    check_pkg hyperland ".run_hyprland"

    printf "\n  ${green}$stowed stowed${reset}"
    [ "$manual" -gt 0 ] && printf "  ${yellow}$manual manual/conflict${reset}"
    [ "$broken" -gt 0 ] && printf "  ${red}$broken broken${reset}"
    [ "$missing" -gt 0 ] && printf "  ${dim}$missing missing${reset}"
    printf "\n\n"

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
