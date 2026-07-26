# =============================================================================
# TERMINAL COMPATIBILITY
# =============================================================================

if ! infocmp "$TERM" &> /dev/null 2>&1; then
    export TERM='xterm-256color'
fi

# =============================================================================
# EXTERNAL ENVIRONMENT SETUP
# =============================================================================

# Корень репозитория: на маке ~/.dotfiles, на Linux ~/dotfiles. Раньше путь был
# захардкожен как ~/.dotfiles в трёх местах, из-за чего на Linux молча не
# грузились conf.d/*.zsh (k9s, kube, lg, tab-title, theme-detect) и .env —
# glob с (N) и проверка [[ -f ]] просто пропускали их без единого сообщения.
export DOTFILES_DIR="${HOME}/.dotfiles"
[[ ! -d "$DOTFILES_DIR" ]] && export DOTFILES_DIR="${HOME}/dotfiles"

if [[ -f "$DOTFILES_DIR/.env" ]]; then
    set -a
    source "$DOTFILES_DIR/.env"
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
HISTSIZE=100000 # Количество команд в памяти
SAVEHIST=100000 # Количество команд для сохранения на диск

setopt HIST_IGNORE_SPACE    # Не сохранять команды, начинающиеся с пробела
setopt HIST_IGNORE_DUPS     # Не сохранять дублирующиеся команды подряд
setopt HIST_IGNORE_ALL_DUPS # Удалять старые дубликаты при добавлении новых
setopt HIST_SAVE_NO_DUPS    # Не записывать дубликаты в файл истории
setopt HIST_FIND_NO_DUPS    # Не показывать дубликаты при поиске
setopt SHARE_HISTORY        # Делиться историей между сессиями (включает и инкрементальную запись)

# =============================================================================
# COMPLETION SYSTEM
# =============================================================================

# ~/.zsh/completions — рукописные из репо; кэш — автогенерируемые (не пачкают репо)
fpath=("$HOME/.zsh/completions" "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/completions" $fpath)

# --- автогенерация completion'ов CLI в кэш (если нет; переживает пересборку devcontainer) ---
() {
    local cdir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/completions"
    mkdir -p "$cdir"
    local tool
    for tool in kubectl helm talosctl k9s devpod docker; do
        (($+commands[$tool])) && [[ ! -f "$cdir/_$tool" ]] && "$tool" completion zsh > "$cdir/_$tool" 2> /dev/null
    done
    # cobra-CLI с флагом -s (gh, glab)
    for tool in gh glab; do
        (($+commands[$tool])) && [[ ! -f "$cdir/_$tool" ]] && "$tool" completion -s zsh > "$cdir/_$tool" 2> /dev/null
    done
    # atuin — свой синтаксис
    (($+commands[atuin])) && [[ ! -f "$cdir/_atuin" ]] && atuin gen-completions --shell zsh > "$cdir/_atuin" 2> /dev/null
}

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
alias lzd='lazydocker'

# Ежедневный: промптов нет, но поверх deny-правил и хуков работает классификатор
# auto-режима — он блокирует по смыслу (подмена remote/эндпоинта, снос чужих
# stateful-ресурсов, пуш секретов) и слушает границы, сказанные словами: «не пушь».
alias cl='claude --permission-mode auto'
# Всё разрешено, проверок по смыслу нет. По докам — только изолированные
# контейнеры и VM: «Isolated containers and VMs only».
alias cly='claude --permission-mode bypassPermissions'
# Исследования в песочнице: запись только в рабочий каталог, сеть по белому
# списку, ~/.ssh и токены закрыты. Строгий режим — фолбэка наружу нет.
alias cls='claude --settings ~/.dotfiles/tools/claude/settings.sandbox.json --permission-mode auto'
# Без CLAUDE.md, правил, скиллов, хуков и MCP — проверить, не конфиг ли виноват.
alias clx='claude --safe-mode'

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
alias dpl='devpod up --dotfiles-script-env PROFILE=core --workspace-env-file ~/.dotfiles/.env'
alias dpf='devpod up --dotfiles-script-env PROFILE=devops --workspace-env-file ~/.dotfiles/.env'

alias c='clear'
alias e='exit'

alias ls='eza'
alias la='eza -laghm --all --icons --git --color=always'
alias lt='eza --tree --level=2 --icons' # Древовидный вид (2 уровня)

# Цветные алиасы для лучшего вывода
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias diff='diff --color=auto'
alias less='less -R' # Показывать цвета в less

# Читаемый вывод для различных команд
alias df='df -h'
alias du='du -h'

alias t='tmux'
alias ta='tmux attach'
alias tl='tmux list-sessions'
alias tks='tmux kill-server'

# Tmux layouts
tw() {
    local count="${1:-3}"
    local name="${2:-$(basename "$PWD")}"
    name="${name#.}"
    name="${name//./-}"
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
    name="${name#.}"
    name="${name//./-}"
    tmux new-session -d -s "$name" -c "$PWD"
    tmux new-window -t "${name}:" -c "$PWD"
    tmux new-window -t "${name}:" -c "$PWD"
    local lock_count
    lock_count=$(find ~/.claude/ide -maxdepth 1 -name '*.lock' 2> /dev/null | wc -l)
    tmux send-keys -t "${name}:1" 'nvim' C-m
    tmux send-keys -t "${name}:2" "while [ \$(find ~/.claude/ide -maxdepth 1 -name '*.lock' 2>/dev/null | wc -l) -le $lock_count ]; do sleep 0.3; done && cl" C-m
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
# DOTFILES_DIR, а не хардкод: на macOS репозиторий лежит в ~/.dotfiles, и алиас
# с "$HOME/dotfiles" молча падал в "✗ Failed to update" на каждом запуске.
# ВНИМАНИЕ: reset --hard стирает незакоммиченное — это и есть смысл алиаса
# («принудительно из облака»), но перед запуском стоит глянуть git status.
alias dfu='(cd "$DOTFILES_DIR" && git fetch origin && git reset --hard @{u}) && echo "✓ Dotfiles updated" || echo "✗ Failed to update dotfiles"' # Обновление дот-файлов (принудительно из облака)

# GitHub CLI - Actions / Workflows
alias gha='gh run list'               # Список последних runs
alias ghaw='gh run watch'             # Watch текущего run в реальном времени
alias ghav='gh run view'              # Детали run (+ ID)
alias ghal='gh run view --log-failed' # Логи только упавших jobs (+ ID)
alias ghar='gh run rerun'             # Перезапуск run (+ ID)
alias gharf='gh run rerun --failed'   # Перезапуск только упавших jobs (+ ID)

# GitHub CLI - Repo
alias ghrv='gh repo view --web' # Открыть репо в браузере
alias ghrc='gh repo clone'

# GitLab CLI - CI/CD Pipelines
alias glci='glab ci status' # Статус текущего pipeline
alias glciv='glab ci view'  # Интерактивный просмотр pipeline
alias glcit='glab ci trace' # Логи job в реальном времени (+ job ID)
alias glcir='glab ci retry' # Перезапуск pipeline
alias glcil='glab ci list'  # Список pipelines

# GitLab CLI - Repo
alias glrv='glab repo view --web' # Открыть репо в браузере
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

alias uvr='uv run'
alias uvs='uv sync'

# determinate-nixd первым: сам nix живёт вне nix-darwin (nix.enable = false,
# демоном владеет Determinate) и иначе не обновляется вообще — отставал на шесть
# минорных версий, пока не заметили.
# Гашение ворнинга о грязном дереве (flake.lock правится тут же, шагом выше):
# у nix это --no-warn-dirty, а darwin-rebuild своих флагов не знает и такой
# отвергает — ему то же самое передаём как --option warn-dirty false.
# sudo -H для GC: без него root наследует $HOME=/Users/cosmdandy и ругается
# «$HOME не принадлежит вам, откат на /var/root» дважды за прогон.
# flake check между update и switch: ловит сломанный на свежем nixpkgs пакет до
# активации (так укусил blueutil). --all-systems — иначе тихо пропускаются Linux-конфиги.
# GC: --delete-older-than вместо -d. `-d` сносит все старые генерации всех профилей
# ("makes rollbacks impossible") — после него откатываться некуда.
# Command Line Tools живут вне nix и brew — обновляются только через softwareupdate,
# а потому отстают молча: на машине стояла 26.2, когда доступны были 26.5 и 26.6.
# Ставим ТОЧЕЧНО по метке: `-i --all` затянул бы и macOS Tahoe с перезагрузкой прямо
# посреди updm. Побочный эффект — система сама выносит скачанные .pkg из
# /Library/Updates, которые заперты флагом SIP restricted и не удаляются даже под root.
clt-update() {
  local label
  label=$(softwareupdate --list 2>/dev/null \
    | grep -o 'Command Line Tools for Xcode [0-9.]*-[0-9.]*' \
    | tail -1)
  if [[ -z $label ]]; then
    echo "Command Line Tools: обновлений нет"
    return 0
  fi
  echo "Command Line Tools: ставлю $label"
  sudo softwareupdate -i "$label"
}

# Сабмодули к пину из основного репо, но только безопасные для перемотки:
# грязные (незакоммиченные правки) и ушедшие вперёд пина (локальные коммиты,
# ещё не влитые в dotfiles) пропускаются с warn — иначе submodule update увёз
# бы локальную работу в detached HEAD, откуда её искать только по reflog.
# Пин может указывать на ещё не скачанный коммит (pull привёз новый gitlink) —
# тогда сперва fetch, иначе merge-base ложно посчитает сабмодуль «впереди».
upds() {
  git -C ~/.dotfiles submodule foreach --quiet '
    expected=$(git -C "$toplevel" rev-parse "HEAD:$sm_path")
    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "warn: $sm_path грязный — пропущен, обнови руками"
    else
      git cat-file -e "$expected^{commit}" 2>/dev/null || git fetch --quiet origin
      if ! git merge-base --is-ancestor HEAD "$expected" 2>/dev/null; then
        echo "warn: $sm_path впереди пина (локальные коммиты) — пропущен"
      elif [ "$(git rev-parse HEAD)" != "$expected" ]; then
        git -C "$toplevel" submodule update --init -- "$sm_path" \
          && echo "$sm_path → $(git rev-parse --short "$expected")"
      fi
    fi'
}

alias updm='git -C ~/.dotfiles pull --ff-only --no-recurse-submodules && upds && sudo determinate-nixd upgrade && nix flake update --no-warn-dirty --flake ~/.dotfiles/platform/nix && nix flake check --no-build --all-systems --no-warn-dirty ~/.dotfiles/platform/nix && sudo darwin-rebuild switch --option warn-dirty false --flake ~/.dotfiles/platform/nix#macbook-cosmdandy && zinit self-update && zinit update && zinit cclear && sudo nix-env -p /nix/var/nix/profiles/system --delete-generations +3 && sudo -H nix-collect-garbage --delete-older-than 3d && clt-update'
alias clean='bash ~/.dotfiles/automation/launchd/scripts/cleanup-mac.sh'
# Обновиться и сразу прибраться. Отдельной связкой, а НЕ чисткой внутри updm:
# всё, что порождает само обновление (brew, Caskroom, поколения nix), уже чистится
# в onActivation/postActivation и хвосте updm. cleanup-mac.sh сносит кэши от
# повседневной работы — кэш сборки Go, pip, прогретый код VS Code, — и терять их
# в начале рабочей сессии незачем. Так решение остаётся за тем, кто запускает.
alias updmc='updm && clean'
# Arc теряет привязку Space → Chrome-профиль после переустановки .app: рабочий
# Space открывается на личном профиле, без расширений и паролей. Кнопки сменить
# профиль у Space в интерфейсе нет — правим состояние. `arcs status` покажет
# расхождение, `arcs apply` починит (Arc должен быть закрыт).
alias arcs='python3 ~/.dotfiles/automation/arc/arc-profiles.py'
# Linux: версии следуют за flake.lock репо (bump — на маке через updm + commit),
# поэтому git pull + home-manager switch, а не flake update в контейнере
alias updl='git -C ~/dotfiles pull --ff-only --no-recurse-submodules && home-manager switch --flake ~/dotfiles/platform/nix#"$(whoami)-$(cat ~/.dotfiles-profile 2>/dev/null || echo devops)-$(uname -m)-linux" -b hm-backup && sudo apt-get update && sudo apt-get upgrade -y && zinit self-update && zinit update && zinit cclear && home-manager expire-generations "-7 days" && nix-collect-garbage --delete-older-than 3d'

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

export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#586e75" # Цвет предложений (solarized base01)

# =============================================================================
# PLUGIN LOADING
# =============================================================================

zinit ice wait lucid
zinit light zsh-users/zsh-completions

zinit ice wait lucid atload'_zsh_autosuggest_start'
zinit light zsh-users/zsh-autosuggestions

zinit ice wait lucid
zinit light zdharma-continuum/fast-syntax-highlighting

zinit ice wait lucid
zinit light hlissner/zsh-autopair

# =============================================================================
# TOOL FUNCTION MODULES
# =============================================================================

# Пер-тул шелл-функции (k9s и пр.). Только определения — на старте лишь парсятся.
for f in "$DOTFILES_DIR/tools/zsh/conf.d/"*.zsh(N); do source "$f"; done

# =============================================================================
# PRIVATE EXTENSIONS
# =============================================================================

for f in "$DOTFILES_DIR/private/zsh/"*.sh(N); do source "$f"; done

# =============================================================================
# COMPLETION ENHANCEMENTS
# =============================================================================

autoload -Uz _zinit
((${+_comps})) && _comps[zinit]=_zinit

# =============================================================================
# EXTERNAL TOOL INTEGRATIONS
# =============================================================================

# Starship - современная настраиваемая строка приглашения
eval "$(starship init zsh)"

# Atuin - улучшенная история команд с синхронизацией
eval "$(atuin init zsh)"

# Direnv - автозагрузка окружения из .envrc при входе в каталог
(($+commands[direnv])) && eval "$(direnv hook zsh)"

autoload -U +X bashcompinit && bashcompinit
# terraform: динамический путь (переживает обновление через nix)
(($+commands[terraform])) && complete -o nospace -C "$(command -v terraform)" terraform

# ansible: автодополнение через argcomplete (кэшируем в файл, чтобы не дёргать python на каждый старт)
if (($+commands[register-python-argcomplete])); then
    _af="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/completions/ansible-argcomplete.zsh"
    if [[ ! -f "$_af" ]]; then
        for _acmd in ansible ansible-playbook ansible-vault ansible-galaxy ansible-config ansible-doc ansible-inventory; do
            (($+commands[$_acmd])) && register-python-argcomplete "$_acmd"
        done > "$_af" 2> /dev/null
    fi
    [[ -s "$_af" ]] && source "$_af"
    unset _af _acmd
fi
