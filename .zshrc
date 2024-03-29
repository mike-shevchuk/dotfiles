
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


DOTFILES=$HOME/dotfiles
ZPLUGRC=$DOTFILES/.zsh_zplug

############ INFO: ZPLUG
source $ZPLUGRC

alias szsh='source ~/.zshrc'
alias nv='nvim'
alias l='ls'
alias la='ls -ah'
alias ll='ls -lh'
alias pau='sudo reboot now'
alias battery="watch upower -i /org/freedesktop/UPower/devices/battery_BAT0"

# alias ll='exa -l --color=always --group-directories-first --icons'
# alias ls='exa --color=always --group-directories-first --icons'
# alias cat='bat --style header --style snip --style changes --style header'

alias bwu="bw unlock | sed -n 4p | cut -d ' ' -f 2-3 | xargs -o echo | xclip -sel c"
alias bw_gpt4_token="bw list items | jq -r '.[] | select(.login.username==\"yuriy@znovyak.com\" and (.name | test(\"openai.com\"))) | .fields[] | select(.name==\"Token\") | .value'"

alias nvim-lazy="NVIM_APPNAME=LazyVim nvim"
alias nvim-kick="NVIM_APPNAME=kickstart nvim"
alias nvim-chad="NVIM_APPNAME=NvChad nvim"
alias nv="NVIM_APPNAME=AstroNvim nvim"
alias nvim-oyi="NVIM_APPNAME=Oyinbra_nvim nvim"
alias nvim-oyinbra="NVIM_APPNAME=Oyinbra nvim"

function nvims() {
  items=("default" "Oyinbra" "Oyinbra_nvim" "LazyVim" "NvChad" "AstroNvim")
  config=$(printf "%s\n" "${items[@]}" | fzf --prompt=" Neovim Config  " --height=~50% --layout=reverse --border --exit-0)
  if [[ -z $config ]]; then
    echo "Nothing selected"
    return 0
  elif [[ $config == "default" ]]; then
    config=""
  fi
  NVIM_APPNAME=$config nvim $@
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
