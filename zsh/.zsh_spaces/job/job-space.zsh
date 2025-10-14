# Job Space Loader
# This file is sourced by ~/.zshrc and is responsible for loading job-specific modules.

JOB_DIR="$HOME/dotfiles/zsh/.zsh_spaces/job"

# Helper to source a module if it exists
_source_job_module() {
    local module_path="$JOB_DIR/$1"
    if [ -f "$module_path" ]; then
        source "$module_path"
    fi
}

# Load modules (add more here as needed)
_source_job_module "aws-logs.zsh"
_source_job_module "git.zsh"
_source_job_module "tmux_manager.zsh"

# Optionally load all *.zsh files except this loader
# Uncomment if you want to auto-load everything
# for script in "$JOB_DIR"/*.zsh; do
#     [ "$(basename "$script")" = "job-space.zsh" ] && continue
#     [ -f "$script" ] && source "$script"
# done

# Ask for confirmation before running any job command
bb_confirm() {
    local cmd_str="$*"
    if [ -z "$cmd_str" ]; then
        echo "No command provided to job_confirm_run" >&2
        return 1
    fi
    echo "About to run:"
    echo "$cmd_str"
    printf "Are you sure? [Y/n] "
    local answer
    read -r answer
    case "$answer" in
        ""|Y|y|Yes|yes)
            eval "$cmd_str"
            ;;
        *)
            echo "Aborted."
            return 130
            ;;
    esac
}

# Fallback for fzf - use select if fzf not available
bb_fzf() {
    if command -v fzf >/dev/null 2>&1; then
        fzf "$@"
    else
        echo "fzf not found, using basic selection:"
        local items=()
        while IFS= read -r line; do
            items+=("$line")
        done
        
        local i=1
        for item in "${items[@]}"; do
            echo "$i) $item"
            ((i++))
        done
        
        printf "Select option (1-%d): " "${#items[@]}"
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
            echo "${items[$((choice-1))]}"
        else
            echo "Invalid selection"
            return 1
        fi
    fi
}
