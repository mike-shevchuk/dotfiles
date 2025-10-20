# SSH Space Loader
# This file loads SSH-related functions and aliases

SSH_DIR="$HOME/dotfiles/zsh/.zsh_spaces/ssh"

# Load all .zsh files in this space (except this loader)
for file in "$SSH_DIR"/*.zsh; do
    if [ -f "$file" ] && [ "$file" != "$0" ]; then
        source "$file"
    fi
done

# If no other .zsh files found, this space is ready for future SSH-related configurations
