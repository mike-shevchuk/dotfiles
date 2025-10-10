
# Use modern completion system
autoload -Uz compinit
compinit

# Default shell history
HISTSIZE=1000
SAVEHIST=1000
HISTFILE=~/.histfile
setopt SHARE_HISTORY
# export EDITOR='NVIM_APPNAME=PWNVIM nvim'
# export EDITOR='NVIM_APPNAME=LazyVIM nvim'
export EDITOR='nvim'


export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
export PIPENV_PYTHON="$PYENV_ROOT/shims/python"

# export PATH="$HOME/.pyenv/bin:$PATH"
# export PATH=$PATH:$(npm bin -g)
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"


ZPLUGRC=$HOME/.zsh_zplug

############# ASDF
# . "$HOME/.asdf/asdf.sh"
[ -f "$HOME/.asdf/asdf.sh" ] && . "$HOME/.asdf/asdf.sh"
# append completions to fpath
fpath=(${ASDF_DIR}/completions $fpath)
# initialise completions with ZSH's compinit
autoload -Uz compinit && compinit

############ INFO: ZPLUG
source $ZPLUGRC

############# ARCH
alias syu='sudo pacman -Syu'
#
#
#
#
###############

alias szsh='source ~/.zshrc'
alias nv='nvim'
alias ftmx='tmux new -s 0; tmux a -t 0'
alias l='ls'
alias ls='ls --color=auto'
alias la='ls -ah'
alias ll='ls -lh'
alias pau='sudo reboot now'
alias battery="watch upower -i /org/freedesktop/UPower/devices/battery_BAT0"
alias open="xdg-open"
alias git_dog="git log --all --decorate --oneline --graph"
alias pip_freeze="pip list --not-required --format freeze"

alias stow="$HOME/.local/src/stow-2.4.1/bin/stow"

# Job scripts management
alias job-dir="cd $HOME/dotfiles/zsh/.zsh_spaces/job"

# Function and alias selectors
alias a_sel="alias-select"
alias f_sel="func-select"

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
    
    echo "Debug: Found functions: $(echo $func_names | wc -w)"
    echo "Debug: First 5 functions: $(echo $func_names | head -5)"
    
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



# alias td="todoist-cli --collor --indent"
# alias td="todoist-cli --color"
# --namespace

alias td="todoist-cli --color --namespace --indent --project-namespace"
alias cl="clear"

# alias ll='exa -l --color=always --group-directories-first --icons'
# alias ls='exa --color=always --group-directories-first --icons'
# alias cat='bat --style header --style snip --style changes --style header'


# Bitwarden and GPT token functions moved to ~/.zshrc.private


alias lz="NVIM_APPNAME=LazyVIM nvim"
alias kck="NVIM_APPNAME=kickstart nvim"
alias nvim-chad="NVIM_APPNAME=NvChad nvim"
alias nv="NVIM_APPNAME=AstroNvim nvim"
alias tnv="NVIM_APPNAME=TNVIM nvim"
alias pnv="NVIM_APPNAME=PWNVIM nvim"
alias nvim-oyi="NVIM_APPNAME=Oyinbra_nvim nvim"
alias nvim-oyinbra="NVIM_APPNAME=Oyinbra nvim"

function nvims() {
  items=("default" "Oyinbra" "Oyinbra_nvim" "LazyVim" "NvChad" "AstroNvim", "TNVIM", "PWNVIM")
  config=$(printf "%s\n" "${items[@]}" | fzf --prompt=" Neovim Config  " --height=~50% --layout=reverse --border --exit-0)
  if [[ -z $config ]]; then
    echo "Nothing selected"
    return 0
  elif [[ $config == "default" ]]; then
    config=""
  fi
  NVIM_APPNAME=$config nvim $@
}


# FOR agnoster
prompt_time() {
  prompt_segment '' 'green' ' %D{%H:%M:%S} '
}

# Store the start time of the command
preexec() {
  cmd_start_time=$SECONDS
}

# Calculate the duration of the command and display it if it's longer than 1 second
precmd() {
  if (( SECONDS - cmd_start_time > 1 )); then
    cmd_duration=$(( SECONDS - cmd_start_time ))
    #duration_segment=" ($cmd_duration s)"
    #
    minutes=$(( cmd_duration / 60 ))
    seconds=$(( cmd_duration % 60 ))

    if (( minutes > 0 )); then
      duration_segment=" ($minutes min $seconds s)"
    else
      duration_segment=" ($seconds s)"
    fi

  else
    duration_segment=""
  fi
}

prompt_duration() {
  prompt_segment 'red' '' "$duration_segment"
}


#AGNOSTER_PROMPT_SEGMENTS+=("prompt_segment '' 'red' ' ($cmd_duration s) '")

AGNOSTER_PROMPT_SEGMENTS+=("prompt_duration")
AGNOSTER_PROMPT_SEGMENTS+=("prompt_time")

bindkey '^A' beginning-of-line
bindkey '^E' end-of-line
bindkey "^[[1;5D" backward-word
bindkey "^[[1;5C" forward-word



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
  # local output_dir="${gpg_file%.gpg}"
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


function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		builtin cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}



######################### TMATE Functions

TMATE_PAIR_NAME="$(whoami)-pair"
TMATE_SOCKET_LOCATION="/tmp/tmate-pair.sock"

# Get current tmate connection url
tmate-url() {
  url="$(tmate -S $TMATE_SOCKET_LOCATION display -p '#{tmate_ssh}')"
  echo "$url" | tr -d '\n' | pbcopy
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



######################### TAMTE END



# Load private credentials if file exists
[ -f ~/.zshrc.private ] && source ~/.zshrc.private

# Load all zsh spaces
[ -f "$HOME/dotfiles/zsh/.zsh_spaces/loader.zsh" ] && source "$HOME/dotfiles/zsh/.zsh_spaces/loader.zsh"

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

export PATH="$HOME/.local/bin:$PATH"

# Auto-change to last Yazi directory
if [ -f ~/.yazi_last_dir ]; then
    cd "$(cat ~/.yazi_last_dir)" 2>/dev/null && rm ~/.yazi_last_dir
fi
