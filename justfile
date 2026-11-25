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
setup: install-deps
    @just --justfile "{{justfile()}}" _steps mise claude codex zsh tmux kitty lz yazi claudes-link hooks-install install-global

# Run recipes one by one: a ✓/✗ line each, only notes shown, full output in a log
[private]
_steps +steps:
    #!/usr/bin/env bash
    set -uo pipefail
    tty=; [ -t 1 ] && tty=1
    g= r= y= d= b= x= tilde='~'
    if [ -n "$tty" ] && [ -z "${NO_COLOR:-}" ]; then
        g=$'\033[32m' r=$'\033[31m' y=$'\033[33m' d=$'\033[2m' b=$'\033[1m' x=$'\033[0m'
    fi
    log=$(mktemp "${TMPDIR:-/tmp}/dotfiles-setup.XXXXXX")
    out="$log.step"
    spin=
    clear_spin() {
        [ -n "$spin" ] && { kill "$spin"; wait "$spin"; } 2>/dev/null
        spin=
        [ -n "$tty" ] && printf '\r\033[K\033[?25h'
        return 0
    }
    trap 'clear_spin; rm -f "$out"' EXIT
    trap 'exit 130' INT TERM
    list=({{steps}}); n=0; notes=0; SECONDS=0
    printf '\n%sdotfiles%s %s%s steps%s\n\n' "$b" "$x" "$d" "${#list[@]}" "$x"
    for step in "${list[@]}"; do
        n=$((n + 1)); t0=$SECONDS
        if [ -n "$tty" ]; then
            printf '\033[?25l'
            ( while :; do for c in ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏; do
                printf '\r  %s%s%s %s %s%s/%s%s' "$y" "$c" "$x" "$step" "$d" "$n" "${#list[@]}" "$x"; sleep 0.1
            done; done ) &
            spin=$!
        fi
        rc=0; just --justfile "{{justfile()}}" "$step" >"$out" 2>&1 || rc=$?
        clear_spin
        { echo "=== $step (exit $rc)"; cat "$out"; } >>"$log"
        if [ "$rc" -ne 0 ]; then
            printf '  %s✗ %s%s  exit %s\n\n' "$r$b" "$step" "$x" "$rc"
            tail -15 "$out" | sed "s/^/    ${r}│${x} /"
            printf '\n  fix it and run the same command again   %slog: %s%s\n' "$d" "$log" "$x"
            exit "$rc"
        fi
        took=$((SECONDS - t0)); [ "$took" -gt 0 ] && took="${took}s" || took=
        printf '  %s✓%s %-16s %s%s%s\n' "$g" "$x" "$step" "$d" "$took" "$x"
        while IFS= read -r line; do
            notes=$((notes + 1)); line="${line#"${line%%[! ]*}"}"
            printf '    %s!%s %s%s%s\n' "$y" "$x" "$d" "${line//$HOME/$tilde}" "$x"
        done < <(grep -E '^ *(WARN:|SKIP |backed up |kept |mise (WARN|ERROR))' "$out")
    done
    printf '\n%s✓ done%s  %s steps, notes: %s, %ss   %slog: %s%s\n' "$g$b" "$x" "$n" "$notes" "$SECONDS" "$d" "$log" "$x"
    printf '  open a new terminal or run: %sexec zsh%s\n\n' "$b" "$x"

# Install stow if missing
install-deps:
    @command -v stow >/dev/null 2>&1 || just _install-stow

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
    r= y= b= x=
    if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then r=$'\033[31m' y=$'\033[33m' b=$'\033[1m' x=$'\033[0m'; fi
    if command -v brew >/dev/null 2>&1; then sys="brew install stow"
    elif command -v apt >/dev/null 2>&1; then sys="sudo apt install -y stow"
    elif command -v pacman >/dev/null 2>&1; then sys="sudo pacman -S --noconfirm stow"
    else sys=""; fi
    via="${VIA:-}"
    case "$sys" in "brew "*) via="${via:-system}" ;; esac
    if [ -z "$via" ] && [ -n "$sys" ] && [ -t 0 ]; then
        printf '%s\n' "${b}stow is missing${x} (it links the configs into ~). Install it via:" \
            "  ${y}1${x}) $sys  (default)" "  ${y}2${x}) mise (no password, into ~/.local)" >&2
        while [ -z "$via" ]; do
            read -rp "1 or 2 [1]: " c || { echo "${r}✗${x} nothing chosen" >&2; exit 1; }
            case "$c" in ""|1) via=system ;; 2) via=mise ;; esac
        done
    fi
    case "${via:-system}" in
        mise) cmd="just --justfile {{justfile()}} _stow-via-mise" ;;
        system) cmd="$sys" ;;
        *) echo "${r}✗${x} VIA must be mise or system, got: $via" >&2; exit 1 ;;
    esac
    [ -n "$cmd" ] || { echo "${r}✗${x} no brew/apt/pacman found — try: VIA=mise just setup" >&2; exit 1; }
    # show the command BEFORE a sudo password prompt, so it is clear what asks and why
    echo "${y}→${x} installing stow: ${b}$cmd${x}" >&2
    $cmd || {
        echo "${r}✗${x} could not install stow: '$cmd' failed (see the error above)." >&2
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
