
# =============================================================================
# ZSH CONFIGURATION
# =============================================================================

# =============================================================================
# HISTORY CONFIGURATION
# =============================================================================

HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.histfile
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_FIND_NO_DUPS
# Enable prompt substitution for themes using $(...) in PROMPT
setopt PROMPT_SUBST
# export EDITOR='NVIM_APPNAME=PWNVIM nvim'
# export EDITOR='NVIM_APPNAME=LazyVIM nvim'

# =============================================================================
# ENVIRONMENT VARIABLES
# =============================================================================

export EDITOR='nvim'
export PATH="$HOME/.local/bin:$PATH"

# mise — manages JS, Go, tools; activate BEFORE pyenv so pyenv shims win for python
if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi

# pyenv — manages Python + virtualenv; activate AFTER mise so its shims take priority
export PYENV_ROOT="$HOME/.pyenv"
[ -d "$PYENV_ROOT/bin" ] && export PATH="$PYENV_ROOT/bin:$PATH"
export PIPENV_PYTHON="$PYENV_ROOT/shims/python"

# ZPlug configuration
# ZPLUGRC=$HOME/.zsh_zplug

# ZInit configuration (replaces zplug for faster loading)
# Try stow symlink path first (~/.zsh_zinit), fall back to repo path for non-stow setups
ZINITRC="$HOME/.zsh_zinit"
[ ! -f "$ZINITRC" ] && ZINITRC="$HOME/dotfiles/zsh/.zsh_zinit"

# =============================================================================
# COMPLETION SYSTEM
# =============================================================================

# ASDF (if available)
[ -f "$HOME/.asdf/asdf.sh" ] && . "$HOME/.asdf/asdf.sh"
fpath=(${ASDF_DIR}/completions $fpath)

# Initialize completion system (once, after all fpath modifications)
autoload -Uz compinit
compinit

# =============================================================================
# PLUGIN MANAGEMENT
# =============================================================================

# Load ZPlug configuration
# source $ZPLUGRC

# Load ZInit configuration
source $ZINITRC

# Initialize pyenv (after zinit to avoid conflicts)
eval "$(pyenv init -)" 2>/dev/null
eval "$(pyenv virtualenv-init -)" 2>/dev/null

# =============================================================================
# CLIPBOARD UTILITIES
# =============================================================================

# Universal clipboard — works on macOS (pbcopy), Wayland (wl-copy), X11 (xclip/xsel)
# Usage: clip <text>  OR  command | clip
clip() {
    local data
    if [ -p /dev/stdin ] || ! [ -t 0 ]; then
        data="$(cat)"
    elif [ $# -gt 0 ]; then
        data="$*"
    else
        echo "Usage: clip <text>  or  command | clip" >&2
        return 1
    fi
    if [[ "$OSTYPE" == "darwin"* ]]; then
        printf '%s' "$data" | pbcopy
    elif command -v wl-copy >/dev/null 2>&1; then
        printf '%s' "$data" | wl-copy
    elif command -v xclip >/dev/null 2>&1; then
        printf '%s' "$data" | xclip -selection clipboard
    elif command -v xsel >/dev/null 2>&1; then
        printf '%s' "$data" | xsel --clipboard --input
    else
        echo "clip: no clipboard tool found. Run 'clip-health' for options." >&2
        return 1
    fi
}

# Show clipboard tool availability and install hints
clip-health() {
    echo "Clipboard tools:"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  ✅ macOS: pbcopy/pbpaste (built-in)"; return 0
    fi
    command -v wl-copy >/dev/null 2>&1 \
        && echo "  ✅ wl-copy  (Wayland)" \
        || echo "  ❌ wl-copy  → sudo pacman -S wl-clipboard"
    command -v xclip >/dev/null 2>&1 \
        && echo "  ✅ xclip   (X11)" \
        || echo "  ❌ xclip   → sudo pacman -S xclip"
    command -v xsel >/dev/null 2>&1 \
        && echo "  ✅ xsel    (X11)" \
        || echo "  ❌ xsel    → sudo pacman -S xsel"
    echo ""
    local active
    active=$(command -v wl-copy >/dev/null 2>&1 && echo "wl-copy" || \
             command -v xclip   >/dev/null 2>&1 && echo "xclip"   || \
             command -v xsel    >/dev/null 2>&1 && echo "xsel"    || echo "none")
    echo "  Active: $active"
    [[ "$active" == "none" ]] && echo "  ⚠️  clip will fail — install one of the above"
}

# Copy current directory to clipboard
alias cwd="pwd | clip"

# Copy last command to clipboard
alias lc="fc -ln -1 | clip"

# =============================================================================
# ALIASES
# =============================================================================

# System management
alias syu='sudo pacman -Syu'
alias pau='sudo reboot now'
alias battery="watch upower -i /org/freedesktop/UPower/devices/battery_BAT0"
[[ "$OSTYPE" == linux* ]] && alias open="xdg-open"

# Shell management
alias szsh='source ~/.zshrc'
alias cl='clear'

# File operations
alias l='ls'
alias ls='ls --color=auto'
alias la='ls -ah'
alias ll='ls -lh'

# Development tools
alias nv='nvim'
alias stow="$HOME/.local/src/stow-2.4.1/bin/stow"

# Git
alias git_dog="git log --all --decorate --oneline --graph"

# Python
alias pip_freeze="pip list --not-required --format freeze"

# Job scripts management
alias job-dir="cd $HOME/dotfiles/zsh/.zsh_spaces/job"

# Function and alias selectors
alias a_sel="alias-select"
alias f_sel="func-select"

# =============================================================================
# INTERACTIVE SELECTORS
# =============================================================================

# Interactive alias selector
alias-select() {
    # Get all aliases and format them for fzf (name\tvalue)
    # Exclude the selector aliases to prevent recursion
    local aliases_output=$(alias | sed 's/^alias //' | sed 's/=/	/' | grep -v '^a_sel	' | grep -v '^f_sel	' | sort)
    
    if [ -z "$aliases_output" ]; then
        echo "No aliases found"
        return 1
    fi
    
    # Show aliases with fzf in two columns and execute selected one
    local selected=$(echo "$aliases_output" | fzf \
        --prompt="Select alias to run: " \
        --height=50% \
        --layout=reverse \
        --border \
        --with-nth=1,2 \
        --delimiter=$'\t' \
        --preview='echo "Alias: {1}" && echo "Command: {2}"' \
        --preview-window=right:30%:wrap \
        --bind='ctrl-/:toggle-preview')
    
    if [ -n "$selected" ]; then
        # Extract just the alias name (first column)
        local alias_name=$(echo "$selected" | cut -d$'\t' -f1)
        echo "Running: $alias_name"
        eval "$alias_name"
    else
        echo "No alias selected"
    fi
}

# Function selector - search functions by name and description
func-select() {
    # Get all functions and their descriptions
    local functions_output=""
    
    # Get functions from current shell
    local func_names=$(typeset -f | grep '^[a-zA-Z_][a-zA-Z0-9_]* ()' | sed 's/ ()//' | sort)
    
    for func in $func_names; do
        # Skip internal zsh functions and selector functions
        if [[ "$func" =~ ^__ ]] || [[ "$func" =~ ^VCS_INFO_ ]] || [[ "$func" =~ ^prompt_ ]] || [[ "$func" == "alias-select" ]] || [[ "$func" == "func-select" ]]; then
            continue
        fi
        
        # Get function description from comments
        local description=""
        local func_def=$(typeset -f "$func" | head -10)
        
        # Look for description in comments
        if echo "$func_def" | grep -q "#.*[Dd]escription\|#.*[Uu]sage\|#.*[Ff]unction"; then
            description=$(echo "$func_def" | grep "#" | head -1 | sed 's/^[[:space:]]*#//' | sed 's/^[[:space:]]*//')
        elif echo "$func_def" | grep -q "^[[:space:]]*#"; then
            description=$(echo "$func_def" | grep "^[[:space:]]*#" | head -1 | sed 's/^[[:space:]]*#//' | sed 's/^[[:space:]]*//')
        else
            description="No description"
        fi
        
        # Format: function_name\tdescription
        functions_output+="$func\t$description\n"
    done
    
    if [ -z "$functions_output" ]; then
        echo "No functions found"
        return 1
    fi
    
    # Show functions with fzf
    local selected=$(echo -e "$functions_output" | fzf \
        --prompt="Select function to run: " \
        --height=60% \
        --layout=reverse \
        --border \
        --with-nth=1,2 \
        --delimiter=$'\t' \
        --preview='echo "Function: {1}" && echo "Description: {2}" && echo "" && echo "Function definition:" && typeset -f {1} | head -20' \
        --preview-window=right:50%:wrap \
        --bind='ctrl-/:toggle-preview' \
        --bind='ctrl-e:execute(echo "Function: {1}" && typeset -f {1})')
    
    if [ -n "$selected" ]; then
        local func_name=$(echo "$selected" | cut -d$'\t' -f1)
        echo "Running function: $func_name"
        echo "About to execute: $func_name"
        printf "Are you sure? [Y/n] "
        local answer
        read -r answer
        case "$answer" in
            ""|Y|y|Yes|yes)
                eval "$func_name"
                ;;
            *)
                echo "Aborted."
                return 130
                ;;
        esac
    else
        echo "No function selected"
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Job management with fzf
fjob() {
    local selected
    selected=$(jobs -l | fzf --prompt="Select Job: " --height=20% --layout=reverse --border --no-hscroll)
    if [[ -n "$selected" ]]; then
        # Extract job number [%N] and bring to foreground
        local job_id=$(echo "$selected" | awk '{print $1}' | tr -d '[]%')
        fg %"$job_id"
    fi
}
alias jf='fjob'

# alias td="todoist-cli --collor --indent"
# alias td="todoist-cli --color"
# --namespace

alias td="todoist-cli --color --namespace --indent --project-namespace"

# Tmux management
alias tma='tmux attach -t $(tmux ls | fzf --prompt="Attach to session: " --border --height=30% | cut -d: -f1)'


# =============================================================================
# NEOVIM CONFIGURATIONS
# =============================================================================

# Neovim with different configurations
alias lz="NVIM_APPNAME=LazyVIM nvim"
alias kck="NVIM_APPNAME=kickstart nvim"
alias nvim-chad="NVIM_APPNAME=NvChad nvim"
alias nv="NVIM_APPNAME=AstroNvim nvim"
alias tnv="NVIM_APPNAME=TNVIM nvim"
alias pnv="NVIM_APPNAME=PWNVIM nvim"
alias nvim-oyi="NVIM_APPNAME=Oyinbra_nvim nvim"
alias nvim-oyinbra="NVIM_APPNAME=Oyinbra nvim"

function nvims() {
  items=("default" "Oyinbra" "Oyinbra_nvim" "LazyVim" "NvChad" "AstroNvim" "TNVIM" "PWNVIM")
  config=$(printf "%s\n" "${items[@]}" | fzf --prompt=" Neovim Config  " --height=~50% --layout=reverse --border --exit-0)
  if [[ -z $config ]]; then
    echo "Nothing selected"
    return 0
  elif [[ $config == "default" ]]; then
    config=""
  fi
  NVIM_APPNAME=$config nvim $@
}


# =============================================================================
# PROMPT CUSTOMIZATION (AGNOSTER THEME)
# =============================================================================

# Time display in prompt
prompt_time() {
    prompt_segment '' 'green' ' %D{%H:%M:%S} '
}

# Command timing functions
preexec() {
    # High-resolution start time for the last command (global var needed in precmd)
    typeset -gF 6 cmd_start_time_rt
    cmd_start_time_rt=$EPOCHREALTIME
}

precmd() {
    # Skip if we don't have a start time yet
    if [[ -z ${cmd_start_time_rt:-} ]]; then
        duration_segment=""
        return
    fi

    # Compute duration in seconds with 2 decimals
    local -F 6 dur
    dur=$(( EPOCHREALTIME - cmd_start_time_rt ))

    if (( dur > 1 )); then
        # Minutes displayed only if strictly greater than 1
        local -i mins
        mins=$(( dur / 60 ))
        local secs
        # Fractional seconds with 2 decimals
        secs=$(printf '%.2f' $(( dur - mins * 60 )))

        if (( mins > 1 )); then
            duration_segment=" (${mins} min ${secs} s)"
        else
            duration_segment=" (${secs} s)"
        fi
    else
        duration_segment=""
    fi
}

prompt_duration() {
    prompt_segment 'red' '' "$duration_segment"
}

# Git arrows showing commits to pull/push
prompt_git_arrows() {
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        return
    fi

    # Get current branch
    local branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [[ -z "$branch" ]]; then
        return
    fi

    # Get remote tracking branch
    local remote=$(git config branch.$branch.remote 2>/dev/null)
    local merge=$(git config branch.$branch.merge 2>/dev/null | sed 's|refs/heads/||')
    
    if [[ -z "$remote" ]] || [[ -z "$merge" ]]; then
        return
    fi

    local remote_branch="$remote/$merge"

    # Check if remote branch exists
    if ! git rev-parse --verify $remote_branch > /dev/null 2>&1; then
        return
    fi

    # Count commits ahead and behind
    local ahead=$(git rev-list --count ${remote_branch}..HEAD 2>/dev/null)
    local behind=$(git rev-list --count HEAD..${remote_branch} 2>/dev/null)

    local arrows=""
    
    if [[ $ahead -gt 0 ]]; then
        arrows+="↑$ahead"
    fi
    
    if [[ $behind -gt 0 ]]; then
        if [[ -n "$arrows" ]]; then
            arrows+=" "
        fi
        arrows+="↓$behind"
    fi

    if [[ -n "$arrows" ]]; then
        prompt_segment 'cyan' 'black' " $arrows "
    fi
}


# ── mise prompt segment ────────────────────────────────────────
# Shows active tools from local .mise.toml / .tool-versions
# Skips python (pyenv-virtualenv handles that). Cached per directory.
_MISE_PROMPT_INFO=""
_MISE_PROMPT_PWD=""

_mise_prompt_refresh() {
    [[ "$PWD" == "$_MISE_PROMPT_PWD" ]] && return
    _MISE_PROMPT_PWD="$PWD"
    _MISE_PROMPT_INFO=""

    # Walk up to find a local config (avoids running mise in every dir)
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.mise.toml" || -f "$dir/.tool-versions" ]]; then
            _MISE_PROMPT_INFO=$(mise current 2>/dev/null \
                | grep -v 'python\|^\s*$' \
                | awk '{print $1"@"$2}' \
                | tr '\n' ' ' \
                | sed 's/ $//')
            break
        fi
        dir="${dir:h}"
    done
}
add-zsh-hook precmd _mise_prompt_refresh

prompt_mise() {
    [[ -z "$_MISE_PROMPT_INFO" ]] && return
    prompt_segment cyan black " ⚡ $_MISE_PROMPT_INFO "
}

# Configure prompt segments
AGNOSTER_PROMPT_SEGMENTS+=("prompt_mise")
AGNOSTER_PROMPT_SEGMENTS+=("prompt_git_arrows")
AGNOSTER_PROMPT_SEGMENTS+=("prompt_duration")
AGNOSTER_PROMPT_SEGMENTS+=("prompt_time")

ZSH_THEME_AGNOSTER_DEFAULT_PROMPT_SEGMENT_FG=244 # сірий текст
ZSH_THEME_AGNOSTER_DEFAULT_PROMPT_SEGMENT_BG=0   # чорний фон (або прозорий)

# =============================================================================
# KEY BINDINGS
# =============================================================================

bindkey '^A' beginning-of-line
bindkey '^E' end-of-line
bindkey "^[[1;5D" backward-word
bindkey "^[[1;5C" forward-word



# =============================================================================
# ENCRYPTION UTILITIES
# =============================================================================

function encrypt_dir() {
    # Display help message
    if [[ "$1" == "--help" ]]; then
        echo "Usage: encrypt_directory <directory> <passphrase>"
        echo "Encrypts the specified directory and deletes the original if encryption is successful."
        echo
        echo "Example:"
        echo "  encrypt_directory comb-notes 'my_secret_text_anigma'"
        return 0
    fi

    # Check if proper arguments are provided
    if [[ $# -ne 2 ]]; then
        echo "Error: Invalid arguments."
        echo "Use '--help' for usage information."
        return 1
    fi

    local dir=$1
    local passphrase=$2
    local output_file="${dir}.gpg"

    # Encrypt the directory using gpgtar with the given passphrase
    gpgtar -c -o "$output_file" --gpg-args "--batch --yes --passphrase=$passphrase" "$dir"

    # Check if encryption was successful
    if [[ $? -eq 0 ]]; then
        echo "Encryption successful. Deleting original directory..."
        rm -rf "$dir"  # Delete the original directory
    else
        echo "Encryption failed."
    fi
}


function decrypt_dir() {
    # Display help message
    if [[ "$1" == "--help" ]]; then
        echo "Usage: decrypt_directory <gpg_file> <passphrase>"
        echo "Decrypts the specified .gpg file and deletes the encrypted file if decryption is successful."
        echo
        echo "Example:"
        echo "  decrypt_directory comb-notes.gpg 'my_secret_text_anigma'"
        return 0
    fi

    # Check if proper arguments are provided
    if [[ $# -ne 2 ]]; then
        echo "Error: Invalid arguments."
        echo "Use '--help' for usage information."
        return 1
    fi

    local gpg_file=$1
    local passphrase=$2
    local output_dir="."

    # Decrypt the gpg file using gpgtar with the given passphrase
    gpgtar --decrypt --directory "$output_dir" --gpg-args "--batch --yes --passphrase=$passphrase" "$gpg_file"

    # Check if decryption was successful
    if [[ $? -eq 0 ]]; then
        echo "Decryption successful. Deleting encrypted file..."
        rm -f "$gpg_file"  # Delete the encrypted .gpg file
    else
        echo "Decryption failed."
    fi
}


# =============================================================================
# FILE MANAGER INTEGRATION
# =============================================================================

# Yazi file manager with directory change support
function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}

# =============================================================================
# SYSTEM MANAGEMENT
# =============================================================================

alias sstat='systemctl list-units --type=service --state=running | less'
alias sfailed='systemctl --failed'

# =============================================================================
# TMATE PAIR PROGRAMMING
# =============================================================================

TMATE_PAIR_NAME="$(whoami)-pair"
TMATE_SOCKET_LOCATION="/tmp/tmate-pair.sock"

# Get current tmate connection url
tmate-url() {
    url="$(tmate -S $TMATE_SOCKET_LOCATION display -p '#{tmate_ssh}')"
    echo -n "$url" | clip
    echo "Copied tmate url for $TMATE_PAIR_NAME:"
    echo "$url"
}

# Start a new tmate pair session if one doesn't already exist
# If creating a new session, the first argument can be an existing TMUX session to connect to automatically
tmate-pair() {
    if [ ! -e "$TMATE_SOCKET_LOCATION" ]; then
        tmate -S "$TMATE_SOCKET_LOCATION" -f "$HOME/.tmate.conf" new-session -d -s "$TMATE_PAIR_NAME"
        sleep 0.3
        tmate-url
        sleep 1

        if [ -n "$1" ]; then
            tmate -S "$TMATE_SOCKET_LOCATION" send -t "$TMATE_PAIR_NAME" "TMUX='' tmux attach-session -t $1" ENTER
        fi
    fi
    tmate -S "$TMATE_SOCKET_LOCATION" attach-session -t "$TMATE_PAIR_NAME"
}

# Close the pair because security
tmate-unpair() {
    if [ -e "$TMATE_SOCKET_LOCATION" ]; then
        tmate -S "$TMATE_SOCKET_LOCATION" kill-session -t "$TMATE_PAIR_NAME"
        echo "Killed session $TMATE_PAIR_NAME"
    else
        echo "Session already killed"
    fi
}



# =============================================================================
# FINAL LOADING
# =============================================================================

# Load private credentials if file exists
[ -f ~/.zshrc.private ] && source ~/.zshrc.private

# Load all zsh spaces
# Try stow symlink path first (~/.zsh_spaces/), fall back to repo path for non-stow setups
_ZSH_SPACES_LOADER="$HOME/.zsh_spaces/loader.zsh"
[ ! -f "$_ZSH_SPACES_LOADER" ] && _ZSH_SPACES_LOADER="$HOME/dotfiles/zsh/.zsh_spaces/loader.zsh"
[ -f "$_ZSH_SPACES_LOADER" ] && source "$_ZSH_SPACES_LOADER"

# # >>> conda initialize >>>
# # !! Contents within this block are managed by 'conda init' !!
# __conda_setup="$('/home/mike/miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
# if [ $? -eq 0 ]; then
#     eval "$__conda_setup"
# else
#     if [ -f "/home/mike/miniconda3/etc/profile.d/conda.sh" ]; then
#         . "/home/mike/miniconda3/etc/profile.d/conda.sh"
#     else
#         export PATH="/home/mike/miniconda3/bin:$PATH"
#     fi
# fi
# unset __conda_setup
# # <<< conda initialize <<<
#


# Auto-change to last Yazi directory
if [ -f ~/.yazi_last_dir ]; then
    cd "$(cat ~/.yazi_last_dir)" 2>/dev/null && rm ~/.yazi_last_dir
fi

# Mise PATH
# eval "$($HOME/.local/bin/mise activate zsh)"


# Added by Antigravity
export PATH="$HOME/.antigravity/antigravity/bin:$PATH"

# bun
if [ -d "$HOME/.bun" ]; then
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"
  [ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"
fi
