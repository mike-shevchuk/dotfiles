
# Use modern completion system
autoload -Uz compinit
compinit

# Default shell history
HISTSIZE=1000
HISTFILE=~/.histfile
SAVEHIST=1000
export EDITOR=vim


export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"


ZPLUGRC=$HOME/.zsh_zplug

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

alias stow="$HOME/.local/src/stow-2.4.0/bin/stow"

# alias ll='exa -l --color=always --group-directories-first --icons'
# alias ls='exa --color=always --group-directories-first --icons'
# alias cat='bat --style header --style snip --style changes --style header'

alias bwu="bw unlock | sed -n 4p | cut -d ' ' -f 2-3 | xargs -o echo | xclip -sel c"

alias bw_gpt_mike="bw_gpt_token 'mshevchukmofficial@gmail.com'"
alias bw_gpt_yuiriy="bw_gpt_token 'yuriy@znovyak.com'"
alias bw_gpt_lwi="bw_gpt_token 'wiai@sexeducation.com.ua'"

export GPT_TOKEN="$(bw_gpt_token 'wiai@sexeducation.com.ua' || echo '')"


alias bw_lb_gpt4="bw list items | jq -r '.[] | select(.login.username==\"wiai@sexeducation.com.ua\" and (.name | test(\"openai.com\"))) | .fields[] | select(.name==\"token\") | .value'"
alias bw_gpt3_token="bw list items | jq -r '.[] | select(.login.username==\"mshevchukmofficial@gmail.com\" and (.name | test(\"openai.com\"))) | .fields[] | select(.name==\"token\") | .value'"
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

bw_gpt_token() {
  local email="$1"
  bw list items | jq -r --arg email "$email" '.[] | select(.login.username==$email and (.name | test("openai.com"))) | .fields[] | select(.name=="token") | .value'
}


bindkey '^A' beginning-of-line
bindkey '^E' end-of-line
bindkey "^[[1;5D" backward-word
bindkey "^[[1;5C" forward-word

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

# [ ! -f "$HOME/.x-cmd.root/X" ] || . "$HOME/.x-cmd.root/X" # boot up x-cmd.
