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
alias lg='lazygit'
alias lzd='lazydocker'

alias cl='claude --permission-mode bypassPermissions'
alias cly='claude --dangerously-skip-permissions'
alias claude-local='ANTHROPIC_BASE_URL=http://localhost:1234 ANTHROPIC_AUTH_TOKEN=lmstudio CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude --model qwen/qwen3-coder-next'

alias ds='devpod ssh'
alias dpd='devpod delete'
alias dps='devpod stop'

alias c='clear'
alias e='exit'

alias ls='eza'
alias la='eza -laghm --all --icons --git --color=always'
alias ll='eza -l --icons --git --color=always'             # Длинный формат без скрытых файлов
alias lt='eza --tree --level=2 --icons'                    # Древовидный вид (2 уровня)
alias lta='eza --tree --level=2 --icons --all'             # Древовидный вид с скрытыми файлами
alias ltr='eza -l --sort=modified --reverse'               # Сортировка по времени изменения
alias tree='eza --tree --level=2 --icons --color=always'
alias treed='eza --tree --level=3 --icons --color=always -d'

# Цветные алиасы для лучшего вывода
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias diff='diff --color=auto'
alias less='less -R'  # Показывать цвета в less

# Читаемый вывод для различных команд
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias ps='ps aux'

alias t='tmux'
alias tn='tmux new -s'
alias ta='tmux attach'
alias tl='tmux list-sessions'
alias tk='tmux kill-session -t'
alias tks='tmux kill-server'

alias gc='git clone'
alias gs='git status'
alias gss='git status --short'
alias gp='git pull'
alias gd='git diff'
alias gdiff='git diff --color-words'
alias glog='git log --oneline --graph --decorate --color=always'
alias gblame='git blame -w'
alias dfu='(cd "$HOME/dotfiles" && git fetch origin && git reset --hard @{u}) && echo "✓ Dotfiles updated" || echo "✗ Failed to update dotfiles"'  # Обновление дот-файлов (принудительно из облака)

# GitHub CLI - Actions / Workflows
alias gha='gh run list'                          # Список последних runs
alias ghaw='gh run watch'                        # Watch текущего run в реальном времени
alias ghav='gh run view'                         # Детали run (+ ID)
alias ghal='gh run view --log-failed'            # Логи только упавших jobs (+ ID)
alias ghar='gh run rerun'                        # Перезапуск run (+ ID)
alias gharf='gh run rerun --failed'              # Перезапуск только упавших jobs (+ ID)

# GitHub CLI - Repo
alias ghrv='gh repo view --web'                  # Открыть репо в браузере
alias ghrc='gh repo clone'

# GitLab CLI - CI/CD Pipelines
alias glci='glab ci status'                       # Статус текущего pipeline
alias glciv='glab ci view'                        # Интерактивный просмотр pipeline
alias glcit='glab ci trace'                       # Логи job в реальном времени (+ job ID)
alias glcir='glab ci retry'                       # Перезапуск pipeline
alias glcil='glab ci list'                        # Список pipelines

# GitLab CLI - Repo
alias glrv='glab repo view --web'                 # Открыть репо в браузере
alias glrc='glab repo clone'

alias psa='source .venv/bin/activate'
alias psd='deactivate'

alias updm='nix flake update --flake ~/.dotfiles/platform/nix && darwin-rebuild switch --flake ~/dotfiles/platform/nix#macbook-cosmdandy && zinit self-update && zinit update'
alias updl='nix flake update --flake ~/dotfiles/platform/nix && sudo apt-get update && sudo apt-get upgrade -y && zinit self-update && zinit update'

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

zinit light zsh-users/zsh-completions                   # Расширенные автодополнения
zinit light zsh-users/zsh-autosuggestions               # Автопредложения на основе истории
zinit light zsh-users/zsh-history-substring-search      # Поиск по подстроке в истории (стрелки вверх/вниз)
zinit light zdharma-continuum/fast-syntax-highlighting  # Быстрая подсветка синтаксиса
zinit light hlissner/zsh-autopair                       # Автоматическое закрытие скобок и кавычек

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
