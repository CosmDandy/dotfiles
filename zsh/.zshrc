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
alias v='nvim'
alias s='spf'
alias b='btop'
alias ks='k9s'
alias lg='lazygit'
alias lzd='lazydocker'
alias t='tmux'

alias c='clear'
alias e='exit'

# Git
alias gc='git clone'

# alias ls='ls --color=auto'
alias ls='eza'
# alias la='ls -lathr'
alias la='eza -laghm@ --all --icons --git --color=always'


# Plugins
plugins=(... zsh-autosuggestions)
plugins=(... fast-syntax-highlighting)
plugins=(... fzf-tab)
