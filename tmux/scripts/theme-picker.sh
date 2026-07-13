#!/usr/bin/env bash
# theme-picker.sh — fzf picker for the tmux mode-color palette (@mode_color_*).
#
# Picks a preset (or opens the HTML picker for a fully custom one), applies it
# to the LIVE tmux server immediately, and persists it into .tmux.conf.local
# (through the ~/.tmux.conf.local symlink, resolved to the real repo file so
# BSD sed doesn't replace the link with a plain file).
#
# Usage:
#   theme-picker.sh            interactive fzf picker (bind: prefix + C-t)
#   theme-picker.sh preview N  render the fzf preview pane for theme N (internal)
#
# bash 3.2 compatible (macOS /bin/bash) — no assoc arrays, no ${var^^}.
set -euo pipefail

CONFIG="${THEME_PICKER_CONFIG:-$HOME/.tmux.conf.local}"
HTML_PICKER="$HOME/dotfiles/tmux/mode-theme-picker.html"
SLOTS="prefix copy zoom claude rest"

# name|prefix|copy|zoom|claude|rest  (slot order matches SLOTS)
themes() {
cat <<'EOF'
catppuccin (default)|#f38ba8|#f9e2af|#fab387|#cba6f7|#89b4fa
kanagawa|#957fb8|#e6c384|#7aa89f|#d27e99|#7e9cd8
gruvbox|#fb4934|#fabd2f|#fe8019|#d3869b|#83a598
nord|#bf616a|#ebcb8b|#d08770|#b48ead|#81a1c1
tokyonight|#f7768e|#e0af68|#ff9e64|#bb9af7|#7aa2f7
dracula|#ff5555|#f1fa8c|#ffb86c|#bd93f9|#8be9fd
rose-pine|#eb6f92|#f6c177|#ea9a97|#c4a7e7|#9ccfd8
everforest|#e67e80|#dbbc7f|#e69875|#d699b6|#7fbbb3
EOF
}

# ANSI truecolor block for one hex color: "  " on that background.
block() {
    local hex="${1#\#}"
    printf '\033[48;2;%d;%d;%dm  \033[0m' "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))"
}

theme_line() {  # $1=theme name → its full "name|c1|...|c5" line
    themes | grep -F "$1|" | head -1
}

current_prefix_color() {
    tmux show -gv @mode_color_prefix 2>/dev/null || true
}

# fzf list: "name<TAB>swatches name (← current)"
list() {
    local cur name c1 c2 c3 c4 c5 mark
    cur=$(current_prefix_color)
    while IFS='|' read -r name c1 c2 c3 c4 c5; do
        mark=""
        [ "$c1" = "$cur" ] && mark=" \033[2m← current\033[0m"
        printf '%s\t' "$name"
        printf '%b%b%b%b%b %s%b\n' "$(block "$c1")" "$(block "$c2")" "$(block "$c3")" "$(block "$c4")" "$(block "$c5")" "$name" "$mark"
    done < <(themes)
    printf 'custom\t🎨 custom — open the HTML picker in the browser\n'
}

preview() {  # $1=theme name
    if [ "$1" = "custom" ]; then
        printf 'Opens %s\n\nPick any colors visually, copy the 5 generated\nlines over the @mode_color_* block in .tmux.conf.local.\n' "$HTML_PICKER"
        return 0
    fi
    local line name c1 c2 c3 c4 c5 slot hex
    line=$(theme_line "$1") || return 0
    IFS='|' read -r name c1 c2 c3 c4 c5 <<< "$line"
    printf '%s\n\n' "$name"
    set -- "$c1" "$c2" "$c3" "$c4" "$c5"
    for slot in $SLOTS; do
        hex="$1"; shift
        printf '  %b%b  %-7s %s\n' "$(block "$hex")" "$(block "$hex")" "$slot" "$hex"
    done
    printf '\n  reacts: active-pane border + status-left badge\n  (prefix > copy > zoom > claude > rest)\n'
}

apply() {  # $1=theme name
    local line name c1 c2 c3 c4 c5
    line=$(theme_line "$1") || true
    [ -n "$line" ] || { echo "unknown theme: $1" >&2; exit 1; }
    IFS='|' read -r name c1 c2 c3 c4 c5 <<< "$line"

    # resolve the symlink so BSD `sed -i` edits the repo file, not the link
    local cfg="$CONFIG"
    [ -L "$cfg" ] && cfg=$(readlink -f "$cfg")
    [ -f "$cfg" ] || { echo "config not found: $cfg" >&2; exit 1; }

    echo "→ applying '$name' (live + $cfg)..." >&2
    local slot hex changed
    set -- "$c1" "$c2" "$c3" "$c4" "$c5"
    for slot in $SLOTS; do
        hex="$1"; shift
        tmux set -g "@mode_color_$slot" "$hex"
        sed -i '' -E "s|^(set -g @mode_color_$slot +)'[^']*'|\1'$hex'|" "$cfg"
        changed=$(grep -c "^set -g @mode_color_$slot *'$hex'" "$cfg" || true)
        [ "$changed" -eq 1 ] || { echo "  FAIL — @mode_color_$slot not persisted in $cfg" >&2; exit 1; }
    done
    echo "  OK — live server updated, config persisted" >&2
}

case "${1:-}" in
    preview) shift; preview "$1"; exit 0 ;;
    apply)   shift; apply "$1";   exit 0 ;;
esac

command -v fzf >/dev/null || { echo "fzf not installed" >&2; exit 1; }

choice=$(list | fzf --ansi --delimiter='\t' --with-nth=2 \
        --prompt='mode theme ❯ ' --height=100% --layout=reverse \
        --preview="\"$0\" preview {1}" --preview-window=right,45% \
        | cut -f1) || exit 0
[ -n "$choice" ] || exit 0

if [ "$choice" = "custom" ]; then
    open "$HTML_PICKER"
    echo "→ opened HTML picker; paste its 5 lines into .tmux.conf.local" >&2
    sleep 1
    exit 0
fi
apply "$choice"
sleep 1
