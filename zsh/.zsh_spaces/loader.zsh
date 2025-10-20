# ZSH Spaces Loader
# This file loads all spaces from .zsh_spaces directory

ZSH_SPACES_DIR="$HOME/dotfiles/zsh/.zsh_spaces"

# Check if .zsh_spaces directory exists
if [ ! -d "$ZSH_SPACES_DIR" ]; then
    echo "Warning: .zsh_spaces directory not found at $ZSH_SPACES_DIR" >&2
    return 1
fi

# Load all space loaders
for space_dir in "$ZSH_SPACES_DIR"/*; do
    if [ -d "$space_dir" ]; then
        space_name=$(basename "$space_dir")
        loader_file="$space_dir/${space_name}-space.zsh"
        
        # Skip the loader.zsh file itself
        if [ "$space_name" = "loader" ]; then
            continue
        fi
        
        if [ -f "$loader_file" ]; then
            # Source the loader file with error handling
            if ! source "$loader_file" 2>/dev/null; then
                echo "Warning: Failed to load space '$space_name' from $loader_file" >&2
            fi
        fi
    fi
done
