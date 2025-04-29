# Prompt
eval "$(starship init zsh)"

# Editing mode
set -o vi
export VISUAL='nvim'
export EDITOR='nvim'
export TERM='tmux-256color'

# History
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000

setopt HIST_IGNORE_SPACE # Don't save when prefixed with space
setopt HIST_IGNORE_DUPS # Don't save duplicate lines
setopt SHARE_HISTORY # Share history between sessions


# Aliases
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."

alias v='nvim'
alias s='spf'
alias b='btop'
alias ks='k9s'
alias lg='lazygit'
alias lzd='lazydocker'
alias t='tmux'
alias ds='devpod ssh'
alias dv='devpod'

alias c='clear'
alias e='exit'

alias gc='git clone'
alias gp='git pull'

alias ls='eza'
alias la='eza -laghm@ --all --icons --git --color=always'

alias update='sudo softwareupdate -i -a; brew update; brew upgrade; brew cleanup; npm install npm -g; npm update -g; zinit self-update; zinit update --parallel'
alias ip="dig +short myip.opendns.com @resolver1.opendns.com"
alias localip="ipconfig getifaddr en0"

# Plugin manager
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[ ! -d $ZINIT_HOME ] && mkdir -p "$(dirname $ZINIT_HOME)"
[ ! -d $ZINIT_HOME/.git ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "${ZINIT_HOME}/zinit.zsh"

autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# Plugins
zinit light zsh-users/zsh-autosuggestions
zinit light zdharma-continuum/fast-syntax-highlighting
