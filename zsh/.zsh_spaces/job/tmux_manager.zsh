# TMUX Project Manager — pick a project dir with fzf, create/attach a tmux session
ts() {
    # Directories to scan for projects
    local project_dirs=(
        "$HOME/projects"
        "$HOME/dotfiles"
        "$HOME/work"
    )

    # Build list: "." (current dir) + top-level subdirs of each project_dir
    local project_list
    project_list=$(
        echo "."
        for dir in "${project_dirs[@]}"; do
             [ -d "$dir" ] && find "$dir" -mindepth 1 -maxdepth 1 -type d
        done
    )

    if [[ -z "$project_list" ]]; then
        echo "ts: no project directories found" >&2
        return 1
    fi

    # Pick a directory with fzf
    local target_dir
    target_dir=$(echo "$project_list" | fzf --prompt="Select project: " --border --height=40%)
    [[ -z "$target_dir" ]] && return 0  # user cancelled

    [[ "$target_dir" == "." ]] && target_dir="$PWD"

    # Session name = directory basename (dots replaced with underscores)
    local session_name
    session_name=$(basename "$target_dir" | tr . _)

    # If session already exists, just attach to it
    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo "ts: attaching to existing session '$session_name'"
        tmux switch-client -t "$session_name" 2>/dev/null || tmux attach-session -t "$session_name"
        return 0
    fi

    # Create a new detached session in the target directory
    tmux new-session -ds "$session_name" -c "$target_dir" -n 'Shell'

    # If a .tmux_setup.sh exists, run it inside the session
    local setup_script="$target_dir/.tmux_setup.sh"
    if [ -f "$setup_script" ]; then
        echo "ts: running setup script for '$session_name'"
        tmux send-keys -t "$session_name:0" "zsh $setup_script" C-m
    else
        echo "ts: created basic session '$session_name' (no .tmux_setup.sh found)"
    fi

    # Attach to the new session
    tmux switch-client -t "$session_name" 2>/dev/null || tmux attach-session -t "$session_name"
}



fjob() {
    local selected
    selected=$(jobs -l | fzf --prompt="Select Job: " --height=20% --layout=reverse --border --no-hscroll)
    if [[ -n "$selected" ]]; then
        local job_id=$(echo "$selected" | awk '{print $1}' | tr -d '[]%')
        fg %"$job_id"
    fi
}
alias jf='fjob'
