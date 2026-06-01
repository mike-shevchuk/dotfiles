#!/usr/bin/env bash
# session-switch.sh — fzf tmux session switcher with a live preview.
# Bound to: prefix j (tmux display-popup -E). Enter → switch-client.
#
# Preview (per highlighted session): attached state, windows + pane counts,
# number of panes running claude, and the active pane's cwd.
#
# Portable to bash 3.2 (macOS): no mapfile / no ${var,,}.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

[ -n "${TMUX:-}" ] || die "not inside tmux"
need fzf "brew install fzf"

# ─── Preview mode (fzf re-invokes this script with --preview <session>) ──────
if [ "${1:-}" = "--preview" ]; then
    sess="${2:-}"
    [ -z "$sess" ] && exit 0
    attached=$(tmux display-message -t "$sess" -p '#{?session_attached,● attached,○ detached}' 2>/dev/null)
    printf '\033[1;36m%s\033[0m  %s\n\n' "$sess" "$attached"
    printf '\033[1mwindows\033[0m\n'
    tmux list-windows -t "$sess" \
        -F '  #I: #W  (#{window_panes}p)#{?window_active,  \033[33m← active\033[0m,}' 2>/dev/null
    cl=$(tmux list-panes -s -t "$sess" -F '#{pane_current_command}' 2>/dev/null | grep -c '^claude$')
    path=$(tmux display-message -t "$sess" -p '#{pane_current_path}' 2>/dev/null)
    printf '\n\033[1mclaude panes:\033[0m %s\n' "${cl:-0}"
    printf '\033[1mpath:\033[0m %s\n' "$path"
    exit 0
fi

current=$(tmux display-message -p '#S' 2>/dev/null)
others=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -v "^${current}\$")
[ -z "$others" ] && die "only one session open ($current)"

self="${BASH_SOURCE[0]}"
sess=$(printf '%s\n' "$others" | fzf \
    --prompt="session (current: $current) > " \
    --height=100% --border --reverse \
    --preview "bash '$self' --preview {}" \
    --preview-window='right:55%')

[ -z "$sess" ] && exit 0
tmux switch-client -t "$sess"
