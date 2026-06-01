#!/usr/bin/env bash
# just-menu.sh — fzf picker for `just` recipes from the global dotfiles
# justfile and (if different) the project justfile discovered from the cwd.
# Bound to: prefix R (tmux display-popup -E -d #{pane_current_path}).
#
# Preview shows the recipe body (`just --show`). Enter runs the recipe in the
# popup and waits for a keypress so you can read the output.
#
#   just-menu.sh --list   → print "<justfile>\t<recipe>" lines (for testing)
#
# Portable to bash 3.2 (macOS).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

GLOBAL_JF="$HOME/dotfiles/justfile"

need just "brew install just"

# ─── Locate the project justfile by walking up from the cwd ──────────────────
find_project_justfile() {
    d="$PWD"
    while [ -n "$d" ] && [ "$d" != "/" ]; do
        for f in justfile Justfile .justfile; do
            if [ -f "$d/$f" ]; then printf '%s\n' "$d/$f"; return 0; fi
        done
        d=$(dirname "$d")
    done
    return 1
}

# ─── Emit "<justfile_path>\t<recipe>\t<label>  <list line>" rows ─────────────
emit_recipes() {
    jf="$1"; label="$2"
    [ -f "$jf" ] || return 0
    # `just --list` → skip the "Available recipes:" header, take the first token
    # of each line as the recipe name, keep the whole (trimmed) line for display.
    just -f "$jf" --list 2>/dev/null | tail -n +2 | while IFS= read -r line; do
        trimmed=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//')
        [ -z "$trimmed" ] && continue
        name=$(printf '%s' "$trimmed" | awk '{print $1}')
        # Keep only valid recipe names. `just --list` also prints group headers
        # ([group]) and attribute lines for grouped justfiles — those contain
        # chars outside [A-Za-z0-9_-], so this skips them.
        case "$name" in
            ''|*[!A-Za-z0-9_-]*) continue ;;
        esac
        printf '%s\t%s\t%-7s %s\n' "$jf" "$name" "[$label]" "$trimmed"
    done
}

proj_jf=$(find_project_justfile || true)
rows=""
[ -f "$GLOBAL_JF" ] && rows="$rows$(emit_recipes "$GLOBAL_JF" global)
"
if [ -n "$proj_jf" ] && [ "$proj_jf" != "$GLOBAL_JF" ]; then
    rows="$rows$(emit_recipes "$proj_jf" project)
"
fi
rows=$(printf '%s' "$rows" | sed '/^[[:space:]]*$/d')
[ -z "$rows" ] && die "no recipes found (global: $GLOBAL_JF, project: ${proj_jf:-none})"

# ─── Non-interactive listing for tests ──────────────────────────────────────
if [ "${1:-}" = "--list" ]; then
    printf '%s\n' "$rows" | cut -f1,2
    exit 0
fi

need fzf "brew install fzf"

sel=$(printf '%s\n' "$rows" | fzf \
    --prompt='just recipe > ' \
    --height=100% --border --reverse \
    --delimiter='\t' --with-nth=3 \
    --preview 'just -f {1} --show {2} 2>/dev/null || echo "(no body)"' \
    --preview-window='right:55%:wrap')

[ -z "$sel" ] && exit 0
jf=$(printf '%s' "$sel" | cut -f1)
recipe=$(printf '%s' "$sel" | cut -f2)
[ -z "$recipe" ] && exit 0

printf '\033[1;32m→ just -f %s %s\033[0m\n\n' "$jf" "$recipe"
( cd "$(dirname "$jf")" && just -f "$jf" "$recipe" )
status=$?
printf '\n\033[2m── exit %s — press any key ──\033[0m' "$status"
read -rsn1 _ 2>/dev/null || true
