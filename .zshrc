## This file must be run before other .zsh config

# instant prompt for powerlevel10k
# if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
# 	source "${XDG_CACHE_HOME:-$HOME/.cache}p10k-instant-prompt-${(%):-%n}.zsh"
# fi
#

DOTFILES=$HOME
ZPLUGRC=$DOTFILES/zsh_zplug
ZSHPlUGINS=$DOTFILES/.zsh_plug

source $ZPLUGRC

alias szsh='source ~/.zshrc'
alias nv='nvim'





