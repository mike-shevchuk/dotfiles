
# Use modern completion system
autoload -Uz compinit
compinit

# Default shell history
HISTSIZE=1000
SAVEHIST=1000
HISTFILE=~/.histfile
setopt SHARE_HISTORY
export EDITOR='NVIM_APPNAME=PWNVIM nvim'


export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"


ZPLUGRC=$HOME/.zsh_zplug

############# ASDF
. "$HOME/.asdf/asdf.sh"
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


# alias td="todoist-cli --collor --indent"
# alias td="todoist-cli --color"
# --namespace

alias td="todoist-cli --color --namespace --indent --project-namespace"
alias cl="clear"

# alias ll='exa -l --color=always --group-directories-first --icons'
# alias ls='exa --color=always --group-directories-first --icons'
# alias cat='bat --style header --style snip --style changes --style header'


# function bw_gpt_token() {
#   local email="$1"
#   bw list items | jq -r --arg email "$email" '.[] | select(.login.username==$email and (.name | test("openai.com"))) | .fields[] | select(.name=="token") | .value'
# }

# alias bwu="bw unlock | sed -n 4p | cut -d ' ' -f 2-3 | xargs -o echo | xclip -sel c"
#
# alias bw_gpt_mike="bw_gpt_token 'mshevchukmofficial@gmail.com'"
# alias bw_gpt_yuiriy="bw_gpt_token 'yuriy@znovyak.com'"
# alias bw_gpt_lwi="bw_gpt_token 'wiai@sexeducation.com.ua'"

# export GPT_TOKEN="$(bw_gpt_token 'wiai@sexeducation.com.ua' || echo '')"


# alias bw_lb_gpt4="bw list items | jq -r '.[] | select(.login.username==\"wiai@sexeducation.com.ua\" and (.name | test(\"openai.com\"))) | .fields[] | select(.name==\"token\") | .value'"
# alias bw_gpt3_token="bw list items | jq -r '.[] | select(.login.username==\"mshevchukmofficial@gmail.com\" and (.name | test(\"openai.com\"))) | .fields[] | select(.name==\"token\") | .value'"


# alias bw_gpt4_token="bw list items | jq -r '.[] | select(.login.username==\"yuriy@znovyak.com\" and (.name | test(\"openai.com\"))) | .fields[] | select(.name==\"token\") | .value'"
# alias bw_gpt4_token = 
# alias btuith="bluetuith"
# export GPT4_TOKEN=$(bw list items | jq -r '.[] | select(.login.username==\"wiai@sexeducation.com.ua\" and (.name | test("openai.com"))) | .fields[] | select(.name=="token") | .value')


alias lz="NVIM_APPNAME=LazyVim nvim"
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

