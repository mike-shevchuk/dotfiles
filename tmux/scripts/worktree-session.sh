#!/usr/bin/env bash
# worktree-session.sh — list the git worktrees of the current repo, pick one
# with fzf, and create-or-attach a tmux session rooted in it.
# Bound to: prefix W (tmux display-popup -E -d #{pane_current_path}).
#
# Session naming mirrors the `ts` convention: basename of the worktree path
# with dots → underscores (tmux forbids '.' in session names).
#
# Portable to bash 3.2 (macOS).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

[ -n "${TMUX:-}" ] || die "not inside tmux"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"
need fzf "brew install fzf"

# ─── Preview mode: branch + short status of the worktree at path $2 ──────────
if [ "${1:-}" = "--preview" ]; then
    path="${2:-}"
    [ -z "$path" ] && exit 0
    [ -d "$path" ] || exit 0
    printf '\033[1;36m%s\033[0m\n\n' "$path"
    branch=$(git -C "$path" branch --show-current 2>/dev/null)
    printf '\033[1mbranch:\033[0m %s\n\n' "${branch:-(detached)}"
    printf '\033[1mstatus:\033[0m\n'
    git -C "$path" --no-optional-locks status -sb 2>/dev/null | head -20
    exit 0
fi

# git worktree list --porcelain → "worktree <path>" lines. Keep paths only.
sel=$(git worktree list --porcelain 2>/dev/null \
        | awk '/^worktree /{print substr($0,10)}' \
        | fzf --prompt='worktree → session > ' \
              --height=100% --border --reverse \
              --preview "bash '${BASH_SOURCE[0]}' --preview {}" \
              --preview-window='right:55%')

[ -z "$sel" ] && exit 0
[ -d "$sel" ] || die "not a directory: $sel"

name=$(basename "$sel" | tr '. ' '__')
if tmux has-session -t "=$name" 2>/dev/null; then
    tmux switch-client -t "=$name"
else
    tmux new-session -d -s "$name" -c "$sel"
    tmux switch-client -t "=$name"
fi
