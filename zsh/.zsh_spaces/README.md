# ZSH Spaces

This directory contains organized zsh configuration spaces.

## Structure

```
.zsh_spaces/
├── loader.zsh              # Main loader for all spaces
├── job/                    # Job-related functions and aliases
│   ├── job-space.zsh       # Job space loader
│   ├── aws-logs.zsh        # AWS logs functions
│   └── git.zsh             # Git functions
└── [other-spaces]/         # Additional spaces
    └── [space]-space.zsh   # Space loader
```

## How to add a new space

1. Create a new directory: `mkdir .zsh_spaces/my-space`
2. Create a loader: `touch .zsh_spaces/my-space/my-space-space.zsh`
3. Add your zsh files to the space directory
4. Update the space loader to source your files

## Example space loader

```zsh
# my-space-space.zsh
MY_SPACE_DIR="$HOME/dotfiles/zsh/.zsh_spaces/my-space"

# Load all .zsh files in this space
for file in "$MY_SPACE_DIR"/*.zsh; do
    [ -f "$file" ] && source "$file"
done
```

## Current spaces

- **job**: Work-related functions and aliases (bb_ prefix)
  - `bb_aws_logs` - AWS logs with fzf
  - `bb_git_push_origin` - Git push with branch selection
  - `bb_confirm` - Confirmation helper
