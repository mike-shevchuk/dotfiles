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
    stow --no-folding --adopt --restow -t ~ claude

# Zsh config, plugins, spaces
zsh:
    stow --no-folding --adopt --restow -t ~ zsh

# Tmux config
tmux:
    stow --no-folding --adopt --restow -t ~ tmux

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

# --- Bulk operations ---

# Stow all packages
all: claude zsh tmux kitty lz pnv tnv yazi todoist fonts hammerspoon hyperland
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
    check_pkg hammerspoon ".hammerspoon/init.lua"
    check_pkg hyperland ".run_hyprland"

    printf "\n  ${green}$stowed stowed${reset}"
    [ "$manual" -gt 0 ] && printf "  ${yellow}$manual manual/conflict${reset}"
    [ "$broken" -gt 0 ] && printf "  ${red}$broken broken${reset}"
    [ "$missing" -gt 0 ] && printf "  ${dim}$missing missing${reset}"
    printf "\n\n"

# Check all dependencies are installed
health:
    #!/usr/bin/env bash
    green='\033[32m'; yellow='\033[33m'; red='\033[31m'; dim='\033[2m'; reset='\033[0m'

    # Pull latest dotfiles
    printf "\n  ${dim}Pulling latest dotfiles...${reset}\n"
    git -C "{{justfile_directory()}}" pull || printf "  ${yellow}pull failed (offline?)${reset}\n"
    printf "\n  ${dim}Applying claude config...${reset}\n"
    just claude || printf "  ${yellow}claude stow failed${reset}\n"
    printf "\n"

    ok=0; warn=0; fail=0

    printf "\n  %-18s  %-10s  %s\n" "DEPENDENCY" "STATUS" "DETAILS"
    printf "  %-18s  %-10s  %s\n" "----------" "------" "-------"

    check() {
        local name="$1" cmd="$2" required="$3" purpose="$4" install_hint="$5"
        if command -v "$cmd" >/dev/null 2>&1; then
            local ver
            ver=$( ("$cmd" --version 2>/dev/null || "$cmd" -V 2>/dev/null) | head -1 | grep -oE '[0-9]+\.[0-9]+[0-9.]*' | head -1 )
            printf "  %-18s  ${green}%-10s${reset}  %s\n" "$name" "ok" "$ver"
            ok=$((ok + 1))
        elif [ "$required" = "required" ]; then
            printf "  %-18s  ${red}%-10s${reset}  %s\n" "$name" "MISSING" "$purpose — $install_hint"
            fail=$((fail + 1))
        else
            printf "  %-18s  ${yellow}%-10s${reset}  %s\n" "$name" "optional" "$purpose — $install_hint"
            warn=$((warn + 1))
        fi
    }

    # Core tools
    check "stow"              stow         required  "symlink manager"            "just install-deps"
    check "git"               git          required  "version control"            "install git"
    check "just"              just         required  "task runner"                "brew/cargo install just"

    # Shell
    check "zsh"               zsh          required  "shell"                      "install zsh"
    check "tmux"              tmux         optional  "terminal multiplexer"       "brew/apt/pacman install tmux"

    # Claude Code deps
    check "node"              node         required  "hooks runtime (tsx)"        "install node"
    check "npx"               npx          required  "runs hook scripts"          "comes with node"
    check "jq"                jq           required  "statusline JSON parsing"    "brew/apt/pacman install jq"
    check "gh"                gh           optional  "statusline PR info"         "brew/apt/pacman install gh"
    check "curl"              curl         required  "statusline usage API"       "brew/apt/pacman install curl"

    # Editors
    check "nvim"              nvim         optional  "neovim (LazyVIM)"           "brew/apt/pacman install neovim"

    # Terminal / file manager
    check "kitty"             kitty        optional  "kitty terminal"             "brew/apt/pacman install kitty"
    check "yazi"              yazi         optional  "file manager"               "cargo install yazi-fm"

    # macOS tools
    if [ "$(uname)" = "Darwin" ]; then
        check "hammerspoon"       hs           optional  "system monitor menubar"     "brew install hammerspoon"
    fi

    # Linux notifications
    if [ "$(uname)" != "Darwin" ]; then
        check "notify-send"   notify-send  required  "hook notifications"         "apt/pacman install libnotify"
        check "paplay"        paplay       optional  "hook sounds (PulseAudio)"   "apt/pacman install pulseaudio-utils"
        check "aplay"         aplay        optional  "hook sounds (ALSA)"         "apt/pacman install alsa-utils"
    fi

    printf "\n  ${green}$ok ok${reset}"
    [ "$warn" -gt 0 ] && printf "  ${yellow}$warn optional${reset}"
    [ "$fail" -gt 0 ] && printf "  ${red}$fail MISSING${reset}"
    printf "\n"

    if [ "$fail" -gt 0 ]; then
        printf "\n  ${red}Fix required dependencies before running 'just setup'${reset}\n\n"
        exit 1
    else
        printf "\n"
    fi

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
