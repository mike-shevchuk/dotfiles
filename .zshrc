## This file must be run before other .zsh config

# instant prompt for powerlevel10k
# if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
# 	source "${XDG_CACHE_HOME:-$HOME/.cache}p10k-instant-prompt-${(%):-%n}.zsh"
# fi
#

DOTFILES=$HOME
ZPLUGRC=$DOTFILES/.zsh_zplug

source $ZPLUGRC

alias szsh='source ~/.zshrc'
alias nv='nvim'
alias l='ls'
alias la='ls -ah'
alias ll='ls -lh'





