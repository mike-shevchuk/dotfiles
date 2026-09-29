#!/usr/bin/env bash
# wt-agent.sh — pick a git worktree with fzf, open a NEW tmux window in it split
# into two panes: [ nvim │ claude ]. For quickly spinning up a Claude agent next
# to the editor on any branch.
#
# Sibling of worktree-session.sh (prefix W = whole session per worktree); this
# one (prefix w) is a lightweight two-pane WINDOW in the current session.
# Bound to: prefix w (tmux display-popup -E).
# Portable to bash 3.2 (macOS).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# ─── Preview mode (called by fzf; needs no tmux/repo guards) ─────────────────
# branch + short status of the worktree at path $2
if [ "${1:-}" = "--preview" ]; then
    path="${2:-}"
    [ -d "$path" ] || exit 0
    printf '\033[1;36m%s\033[0m\n\n' "$path"
    branch=$(git -C "$path" branch --show-current 2>/dev/null)
    printf '\033[1mbranch:\033[0m %s\n\n' "${branch:-(detached)}"
    printf '\033[1mstatus:\033[0m\n'
    git -C "$path" --no-optional-locks status -sb 2>/dev/null | head -20
    exit 0
fi

[ -n "${TMUX:-}" ] || die "not inside tmux"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"
need fzf "brew install fzf"

# Resolve the MAIN repo (git-common-dir) so the list is complete from a worktree.
common=$(git rev-parse --git-common-dir 2>/dev/null || true)
case "$common" in
    /*) repo=$(cd "$(dirname "$common")" && pwd) ;;
    ?*) repo=$(cd "$(dirname "$common")" && pwd) ;;
    *)  repo=$(git rev-parse --show-toplevel) ;;
esac

# One row per worktree: "branch<TAB>path"; fzf shows only the branch, previews path.
sel=$(git -C "$repo" worktree list --porcelain 2>/dev/null \
        | awk '/^worktree /{p=substr($0,10)} /^branch /{b=$0;sub("branch refs/heads/","",b);print b"\t"p}' \
        | fzf --with-nth=1 -d '\t' --prompt='worktree → agent window > ' \
              --height=100% --border --reverse \
              --preview "bash '${BASH_SOURCE[0]}' --preview {2}" \
              --preview-window='right:55%')
[ -z "$sel" ] && exit 0

branch=${sel%%$'\t'*}
path=${sel#*$'\t'}
[ -d "$path" ] || die "not a directory: $path"
name=$(printf '%s' "$branch" | sed 's/^worktree-//' | cut -c1-18)

# New window in the worktree dir: left = nvim, right = claude (40%).
win=$(tmux new-window -P -c "$path" -n "$name" -F '#{window_id}')
tmux send-keys -t "$win" 'nvim' Enter
tmux split-window -h -t "$win" -c "$path" -l 40%
tmux send-keys -t "$win" 'claude' Enter
tmux select-pane -t "$win" -L
