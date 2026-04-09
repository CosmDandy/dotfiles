# =============================================================================
# TERMINAL COMPATIBILITY
# =============================================================================

if ! infocmp "$TERM" &>/dev/null 2>&1; then
  export TERM='xterm-256color'
fi

# =============================================================================
# EXTERNAL ENVIRONMENT SETUP
# =============================================================================

if [[ -f "$HOME/.dotfiles/.env" ]]; then
    set -a
    source "$HOME/.dotfiles/.env"
    set +a
fi

if [[ -r "$HOME/.atuin/bin/env" ]]; then
    source "$HOME/.atuin/bin/env"
fi

# =============================================================================
# SSH AGENT FORWARDING FIX (for tmux reattach)
# =============================================================================

if [[ -n "$SSH_AUTH_SOCK" && "$SSH_AUTH_SOCK" != "$HOME/.ssh/ssh_auth_sock" ]]; then
    ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/ssh_auth_sock"
fi
export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"

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
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

# =============================================================================
# ALIASES - NAVIGATION
# =============================================================================

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias sz='source ~/.zshrc'

alias dl='cd ~/Downloads'
alias dt='cd ~/Desktop'
alias docs='cd ~/Documents'

alias v='nvim'
alias b='btop'
alias lg='lazygit'
alias lzd='lazydocker'

alias cl='claude --permission-mode bypassPermissions'
alias cly='claude --dangerously-skip-permissions'
alias claude-local='ANTHROPIC_BASE_URL=http://localhost:1234 ANTHROPIC_AUTH_TOKEN=lmstudio CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude --model qwen/qwen3-coder-next'

claude-memory-init() {
    local dotfiles_dir="${HOME}/.dotfiles"
    [[ ! -d "$dotfiles_dir" ]] && dotfiles_dir="${HOME}/dotfiles"
    "${dotfiles_dir}/tools/claude/custom/setup.sh" "${1:-$(basename "$PWD")}" "$PWD"
}

claude-memory-push() {
    local dotfiles_dir="${HOME}/.dotfiles"
    [[ ! -d "$dotfiles_dir" ]] && dotfiles_dir="${HOME}/dotfiles"
    local submodule_dir="${dotfiles_dir}/tools/claude/custom"

    local project="$1"
    if [[ -z "$project" ]]; then
        local encoded_path
        encoded_path="$(pwd | sed 's|[/.]|-|g')"
        local memory_link="$HOME/.claude/projects/${encoded_path}/memory"
        if [[ -L "$memory_link" ]]; then
            project="$(basename "$(dirname "$(readlink "$memory_link")")")"
        else
            project="$(basename "$PWD" | sed 's/^\.//')"
        fi
    fi

    local memory_path="knowledge/${project}/memory"

    if [[ ! -d "${submodule_dir}/${memory_path}" ]]; then
        echo "Memory not found: ${memory_path}" >&2
        return 1
    fi

    git -C "$submodule_dir" add "knowledge/${project}"
    git -C "$submodule_dir" diff --cached --quiet && {
        echo "No changes for ${project}"
        return 0
    }
    git -C "$submodule_dir" commit -m "docs(${project}): update knowledge"
    git -C "$submodule_dir" push
}

alias ds='devpod ssh'
alias dpd='devpod delete'
alias dps='devpod stop'
alias dpl='devpod up --dotfiles-script-env PROFILE=base --workspace-env-file ~/.dotfiles/.env'
alias dpf='devpod up --dotfiles-script-env PROFILE=full --workspace-env-file ~/.dotfiles/.env'

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
alias ta='tmux attach'
alias tl='tmux list-sessions'
alias tks='tmux kill-server'

# Tmux layouts
tw() {
    local count="${1:-3}"
    local name="${2:-$(basename "$PWD")}"
    name="${name#.}"
    tmux new-session -d -s "$name" -c "$PWD"
    for i in $(seq 2 "$count"); do
        tmux new-window -t "${name}:" -c "$PWD"
    done
    tmux select-window -t "${name}:1"
    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$name"
    else
        tmux attach -t "$name"
    fi
}

t3() { tw 3 "$1"; }
t6() { tw 6 "$1"; }

tn() {
    local name="${1:-$(basename "$PWD")}"
    name="${name#.}"  # strip leading dot (e.g. .dotfiles → dotfiles)
    tmux new-session -d -s "$name" -c "$PWD"
    tmux new-window -t "${name}:" -c "$PWD"
    tmux new-window -t "${name}:" -c "$PWD"
    tmux send-keys -t "${name}:1" 'nvim' C-m
    tmux send-keys -t "${name}:2" 'cl' C-m
    tmux select-window -t "${name}:1"
    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$name"
        tmux refresh-client -S
    else
        tmux attach -t "$name"
    fi
}

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

alias dc='docker compose'
alias dcl='docker compose logs -f'
alias dcu='docker compose up -d'
alias dcd='docker compose down'

alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kl='kubectl logs -f'
alias kctx='kubectl config use-context'
alias kns='kubectl config set-context --current --namespace'

alias psa='source .venv/bin/activate'
alias psd='deactivate'

alias jn='jupyter notebook'
alias jl='jupyter lab'
alias uvr='uv run'
alias uvs='uv sync'

alias updm='nix flake update --flake ~/.dotfiles/platform/nix && sudo darwin-rebuild switch --flake ~/.dotfiles/platform/nix#macbook-cosmdandy && zinit self-update && zinit update'
alias updl='nix flake update --flake ~/dotfiles/platform/nix && sudo apt-get update && sudo apt-get upgrade -y && zinit self-update && zinit update'

alias ttyh='ghostty +list-keybinds --default'

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

zinit ice wait lucid
zinit light zsh-users/zsh-completions

zinit ice wait lucid atload'_zsh_autosuggest_start'
zinit light zsh-users/zsh-autosuggestions

zinit ice wait lucid
zinit light zsh-users/zsh-history-substring-search

zinit ice wait lucid
zinit light zdharma-continuum/fast-syntax-highlighting

zinit ice wait lucid
zinit light hlissner/zsh-autopair

# =============================================================================
# PRIVATE EXTENSIONS
# =============================================================================

for f in "$HOME/.dotfiles/private/zsh/"*.sh(N); do source "$f"; done

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
