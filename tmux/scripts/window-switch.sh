#!/usr/bin/env bash
# window-switch.sh — fzf tmux window switcher (current or all sessions), live preview.
# Bound to (tmux display-popup -E), Enter → switch-client to window:
#   prefix n → windows of the CURRENT session   (no arg)
#   prefix N → windows of ALL sessions          (--all)
# Sibling of session-switch.sh (prefix j).
#
# Rows: "session:index  name  [cmd]  (Np)  path". In --all mode the current
# session's windows come first; the current window itself is always excluded.
# Preview: the window's panes + a snapshot of its active pane.
#
# Portable to bash 3.2 (macOS): no mapfile / no ${var,,}.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

[ -n "${TMUX:-}" ] || die "not inside tmux"
need fzf "brew install fzf"

# ─── Preview mode (fzf re-invokes this script with --preview <sess:idx>) ─────
if [ "${1:-}" = "--preview" ]; then
    target="${2:-}"
    [ -z "$target" ] && exit 0
    printf '\033[1;36m%s\033[0m  %s\n\n' "$target" \
        "$(tmux display-message -t "$target" -p '#W' 2>/dev/null)"
    # Fleet card (PR / Linear / progress / steps / next / 🙋) when fleet.json knows this window.
    card=$("$(dirname "$0")/fleet-board.sh" "$(tmux display-message -t "$target" -p '#W' 2>/dev/null)" 2>/dev/null)
    [ -n "$card" ] && printf '%s\n\n' "$card"
    printf '\033[1mpanes\033[0m\n'
    tmux list-panes -t "$target" \
        -F '  #P: #{pane_current_command}  #{pane_current_path}#{?pane_active,  <<A>>,}' 2>/dev/null \
        | sed -e "s|$HOME|~|g" -e $'s/<<A>>/\033[33m← active\033[0m/'
    printf '\n\033[1msnapshot\033[0m\n'
    # -e keeps colours; tail trims blank rows below the prompt.
    tmux capture-pane -e -p -t "$target" 2>/dev/null | sed '/^[[:space:]]*$/d' | tail -n 40
    exit 0
fi

current_sess=$(tmux display-message -p '#S' 2>/dev/null)
scope=""; label="$current_sess"   # no flag = current session
[ "${1:-}" = "--all" ] && { scope="-a"; label="all sessions"; }
current_win=$(tmux display-message -p '#S:#I' 2>/dev/null)

fmt='#S:#I'$'\t''#{?#{@need_mike},🙋 ,}#W  [#{pane_current_command}]  (#{window_panes}p)  #{pane_current_path}'
rows=$(tmux list-windows ${scope:+"$scope"} -F "$fmt" 2>/dev/null \
    | awk -F'\t' -v cur="$current_win" '$1 != cur' \
    | sed "s|$HOME|~|g")
[ -z "$rows" ] && die "only one window open ($current_win)"

# Current session first (closest jumps), then the rest in tmux order.
rows=$(printf '%s\n' "$rows" | awk -F'\t' -v s="$current_sess" \
    '{ split($1, a, ":"); if (a[1] == s) print; else rest = rest $0 "\n" }
     END { printf "%s", rest }')

self="${BASH_SOURCE[0]}"
pick=$(printf '%s\n' "$rows" | fzf \
    --prompt="window ($label) · current $current_win > " \
    --delimiter=$'\t' --with-nth=1,2 --tabstop=2 \
    --height=100% --border --reverse --ansi \
    --preview "bash '$self' --preview {1}" \
    --preview-window='right:55%')

[ -z "$pick" ] && exit 0
target=$(printf '%s' "$pick" | cut -f1)
tmux switch-client -t "$target"   # session:index → switches session AND window
