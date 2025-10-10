# SSH Space Loader
# This file loads SSH-related functions and aliases

SSH_DIR="$HOME/dotfiles/zsh/.zsh_spaces/ssh"

# Load all .zsh files in this space (except this loader)
for file in "$SSH_DIR"/*.zsh; do
    [ -f "$file" ] && [ "$file" != "$0" ] && source "$file"
done
