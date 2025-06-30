# =============================================================================
# EXTERNAL ENVIRONMENT SETUP
# =============================================================================

# if [[ -r "$HOME/.local/bin/env" ]]; then
#     source "$HOME/.local/bin/env"
# fi

if [[ -r "$HOME/.atuin/bin/env" ]]; then
    source "$HOME/.atuin/bin/env"
fi

# =============================================================================
# ZSH OPTIONS
# =============================================================================

set -o vi

HISTFILE=~/.zsh_history
HISTSIZE=100000              # Количество команд в памяти
SAVEHIST=100000              # Количество команд для сохранения на диск

setopt HIST_IGNORE_SPACE     # Не сохранять команды, начинающиеся с пробела
setopt HIST_IGNORE_DUPS      # Не сохранять дублирующиеся команды подряд
setopt HIST_IGNORE_ALL_DUPS  # Удалять старые дубликаты при добавлении новых
setopt HIST_SAVE_NO_DUPS     # Не записывать дубликаты в файл истории
setopt HIST_FIND_NO_DUPS     # Не показывать дубликаты при поиске
setopt SHARE_HISTORY         # Делиться историей между сессиями
setopt APPEND_HISTORY        # Добавлять к истории, а не перезаписывать
setopt INC_APPEND_HISTORY    # Добавлять команды в историю сразу после выполнения

# =============================================================================
# COMPLETION SYSTEM
# =============================================================================

fpath=("$HOME/.zsh/completions" $fpath)

autoload -Uz compinit
compinit

# =============================================================================
# ALIASES - NAVIGATION
# =============================================================================

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

alias dl='cd ~/Downloads'
alias dt='cd ~/Desktop'
alias docs='cd ~/Documents'

alias v='nvim'
alias s='spf'
alias b='btop'
alias t='tmux'
alias lg='lazygit'
alias lzd='lazydocker'
alias ds='devpod ssh'

alias c='clear'
alias e='exit'

alias ls='eza'
alias la='eza -laghm@ --all --icons --git --color=always'
alias ll='eza -l --icons --git --color=always'             # Длинный формат без скрытых файлов
alias lt='eza --tree --level=2 --icons'                    # Древовидный вид (2 уровня)
alias lta='eza --tree --level=2 --icons --all'             # Древовидный вид с скрытыми файлами
alias ltr='eza -l --sort=modified --reverse'               # Сортировка по времени изменения

alias t='tmux'
alias ta='tmux attach'
alias tl='tmux list-sessions'
alias tk='tmux kill-session -t'
alias tks='tmux kill-server'

alias gc='git clone'

alias gs='git status'
alias gss='git status --short'

alias gl='git pull'

alias gd='git diff'

alias ip="dig +short myip.opendns.com @resolver1.opendns.com"  # Внешний IP
alias localip="ipconfig getifaddr en0"                         # Локальный IP (macOS)

alias pss='source .venv/bin/activate'
alias psd='deactivate'

alias update='sudo softwareupdate -i -a; brew update; brew upgrade; brew cleanup; npm install npm -g; npm update -g; zinit self-update; zinit update'

alias ports='netstat -tulanp'

# =============================================================================
# PLUGIN MANAGER SETUP
# =============================================================================

# Путь к zinit
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Автоматическая установка zinit при первом запуске
if [[ ! -d $ZINIT_HOME ]]; then
    mkdir -p "$(dirname $ZINIT_HOME)"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

source "${ZINIT_HOME}/zinit.zsh"

# =============================================================================
# PLUGIN CONFIGURATIONS
# =============================================================================

HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND='bg=green,fg=white,bold'
HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND='bg=red,fg=white,bold'
HISTORY_SUBSTRING_SEARCH_GLOBBING_FLAGS='i'
HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE=true    # Показывать только уникальные результаты
HISTORY_SUBSTRING_SEARCH_FUZZY=true            # Нечеткий поиск

export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#586e75"  # Цвет предложений (solarized base01)

# =============================================================================
# PLUGIN LOADING
# =============================================================================

zinit light zsh-users/zsh-autosuggestions               # Автопредложения на основе истории
zinit light zsh-users/zsh-history-substring-search      # Поиск по подстроке в истории (стрелки вверх/вниз)
zinit light zdharma-continuum/fast-syntax-highlighting  # Быстрая подсветка синтаксиса

# =============================================================================
# KEY BINDINGS
# =============================================================================

bindkey '^[[A' history-beginning-search-backward
bindkey '^[[B' history-beginning-search-forward

bindkey '^[OA' history-substring-search-up
bindkey '^[OB' history-substring-search-down

# =============================================================================
# COMPLETION ENHANCEMENTS
# =============================================================================

autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# =============================================================================
# EXTERNAL TOOL INTEGRATIONS
# =============================================================================

# Starship - современная настраиваемая строка приглашения
eval "$(starship init zsh)"

# Atuin - улучшенная история команд с синхронизацией
eval "$(atuin init zsh)"

# Mise - менеджер версий языков программирования
eval "$($HOME/.local/bin/mise activate zsh)"
