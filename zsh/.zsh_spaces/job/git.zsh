# Git helpers for job space

# Push selected branch to origin with upstream (-u)
# Usage:
#   bb_git_push_origin        # pick branch via fzf (latest 10 by commit time)
#   bb_git_push_origin <br>   # push provided branch directly
bb_git_push_origin() {
    local branch="$1"

    # Ensure we're inside a git repository
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
        echo "Not a git repository" >&2
        return 1
    }

    if [ -z "$branch" ]; then
        # List latest 10 local branches by last commit time (descending)
        # Format: branch_name\tcommit_time
        local selection
        selection=$(git for-each-ref \
            --sort=-committerdate \
            --format='%(refname:short)\t%(committerdate:relative) | %(committerdate:iso8601)' \
            refs/heads \
            | head -n 10 \
            | fzf --prompt="Select branch to push: " \
                  --height=50% --layout=reverse --border \
                  --with-nth=1,2 \
                  --ansi \
                  --no-multi)

        [ -z "$selection" ] && {
            echo "No branch selected" >&2
            return 1
        }

        # Extract branch name (first field before tab)
        branch="${selection%%\t*}"
    fi

    # Safety check the branch exists locally
    git show-ref --verify --quiet "refs/heads/$branch" || {
        echo "Branch '$branch' does not exist locally" >&2
        return 1
    }

    local cmd="git push -u origin '$branch'"
    bb_confirm "$cmd"
}
