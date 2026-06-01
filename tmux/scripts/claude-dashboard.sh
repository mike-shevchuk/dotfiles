#!/usr/bin/env bash
# claude-dashboard.sh — one view of every pane running `claude`, across all
# sessions. Shows: sess:win.pane  state  uptime  path  branch.
# Bound to: prefix A (tmux display-popup -E). Enter → jump to that pane.
#
# Preview = live tail of the selected claude pane.
# Portable to bash 3.2 (macOS).
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
STATUS="$HOME/.tmux-status.sh"

[ -n "${TMUX:-}" ] || die "not inside tmux"
need fzf "brew install fzf"

# ─── Preview mode: tail the pane whose id is passed as $2 ────────────────────
if [ "${1:-}" = "--preview" ]; then
    pid="${2:-}"
    [ -z "$pid" ] && exit 0
    tmux capture-pane -p -t "$pid" -S -25 -E -1 2>/dev/null
    exit 0
fi

# ─── Build rows: <pane_id>\t<display columns…> ───────────────────────────────
# Column 1 (pane_id) is the action key, hidden from the list via --with-nth.
rows=""
while IFS="$(printf '\t')" read -r sess win pane pid cmd path; do
    [ "$cmd" = "claude" ] || continue
    state=$("$STATUS" claude-state "$pid" 2>/dev/null)
    up=$("$STATUS" claude-uptime "$pid" 2>/dev/null)
    git=$("$STATUS" pane-git "$path" 2>/dev/null)
    # short path: ~ for $HOME
    short=${path/#$HOME/\~}
    rows="$rows$(printf '%s\t%-14s  %-8s %-7s %-32s %s\n' \
        "$pid" "$sess:$win.$pane" "${state:-?}" "${up:-—}" "$short" "${git:-}")
"
done <<EOF
$(tmux list-panes -a -F '#{session_name}	#{window_index}	#{pane_index}	#{pane_id}	#{pane_current_command}	#{pane_current_path}' 2>/dev/null)
EOF

# strip leading/trailing blank lines
rows=$(printf '%s' "$rows" | sed '/^[[:space:]]*$/d')
[ -z "$rows" ] && die "no panes are running claude right now"

sel=$(printf '%s\n' "$rows" | fzf \
    --prompt='claude panes > ' \
    --height=100% --border --reverse \
    --delimiter='\t' --with-nth=2 \
    --header='  sess:win.pane   state    uptime  path                              branch' \
    --preview "bash '${BASH_SOURCE[0]}' --preview {1}" \
    --preview-window='down:55%:wrap')

[ -z "$sel" ] && exit 0
pid=$(printf '%s' "$sel" | cut -f1)
[ -z "$pid" ] && exit 0
sess=$(tmux display-message -t "$pid" -p '#S' 2>/dev/null)
tmux switch-client -t "$sess" \; select-window -t "$pid" \; select-pane -t "$pid"
