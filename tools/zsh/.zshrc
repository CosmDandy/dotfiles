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

# Раньше здесь стоял `set -a; source .env; set +a` — он экспортировал ВСЕ переменные
# файла, включая токены Jira/GitLab/Nomad и пароль OpenSearch, в окружение каждого
# дочернего процесса: любой npm, uv или docker получал их просто по факту запуска.
# Теперь наружу уходит только то, чему это нужно по устройству: MCP-серверы Claude
# Code наследуют переменные из окружения (tools/claude/custom/install.sh:151), glab
# читает GITLAB_TOKEN. Остальные остаются переменными шелла — доступны здесь, но
# дальше не текут. Список именно whitelist: то, чего в нём нет, не экспортируется,
# поэтому новая переменная в .env по умолчанию наружу не попадёт.
# Следующий шаг (не сделан): раздавать JIRA_*/TIMING_MCP_URL самим MCP-серверам через
# `claude mcp add -e KEY=...`, а GITLAB_TOKEN — через direnv в рабочих каталогах;
# тогда глобальный экспорт исчезнет совсем. См. use_sops в tools/direnv/direnvrc.
if [[ -f "$DOTFILES_DIR/.env" ]]; then
    source "$DOTFILES_DIR/.env"
    () {
        local -a keep=(JIRA_URL JIRA_USERNAME JIRA_API_TOKEN TIMING_MCP_URL GITLAB_TOKEN)
        local -a found=()
        local line v
        # Разбор своими средствами, без sed: BSD и GNU расходятся в BRE (\? у BSD нет),
        # а имена переменных нужны одинаково на маке и в контейнере.
        while IFS= read -r line || [[ -n $line ]]; do
            [[ $line =~ '^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=' ]] \
                && found+=("$match[2]")
        done < "$DOTFILES_DIR/.env"
        for v in $found; do
            (( ${keep[(Ie)$v]} )) || typeset +x "$v" 2> /dev/null
        done
        for v in $keep; do
            [[ -n ${(P)v} ]] && export "$v"
        done
    }
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
# Экспорт только при живом сокете. Безусловный оставлял переменную указывающей на
# симлинк с прошлой сессии, и вместо честного «агента нет» ssh выдавал
# «Error connecting to agent: No such file or directory».
[[ -S "$HOME/.ssh/ssh_auth_sock" ]] && export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"

# =============================================================================
# ZSH OPTIONS
# =============================================================================

set -o vi
# Дефолт — 40 (0.4с): столько zsh ждёт продолжения escape-последовательности после
# Esc, и ровно столько ощущается залипанием на каждом выходе в командный режим.
KEYTIMEOUT=1

# Форма курсора как индикатор режима: блок — normal, вертикальная черта — insert.
# Без этого в голом `set -o vi` режим определяется только на ощупь.
_cursor_shape() { case $KEYMAP in vicmd) print -n '\e[2 q';; *) print -n '\e[6 q';; esac }
zle -N zle-keymap-select _cursor_shape
zle -N zle-line-init     _cursor_shape

HISTFILE=~/.zsh_history
HISTSIZE=100000 # Количество команд в памяти
SAVEHIST=100000 # Количество команд для сохранения на диск

setopt EXTENDED_HISTORY     # Таймстемп и длительность у каждой команды
setopt HIST_IGNORE_SPACE    # Не сохранять команды, начинающиеся с пробела
setopt HIST_IGNORE_DUPS     # Не сохранять дублирующиеся команды подряд
setopt HIST_IGNORE_ALL_DUPS # Удалять старые дубликаты при добавлении новых
setopt HIST_SAVE_NO_DUPS    # Не записывать дубликаты в файл истории
setopt HIST_FIND_NO_DUPS    # Не показывать дубликаты при поиске
setopt HIST_VERIFY          # !! и !$ сначала показать в строке, а не выполнить сразу
setopt SHARE_HISTORY        # Делиться историей между сессиями (включает и инкрементальную запись)

# =============================================================================
# COMPLETION SYSTEM
# =============================================================================

# Дедупликация до любых манипуляций с fpath. /etc/zshenv от nix-darwin переисполняет
# set-environment на каждый zsh-процесс, и fpath приезжает сюда уже с 62 записями при
# 25 уникальных — по 4 копии каждого каталога плюс функции сразу двух поколений zsh.
# Каждый дубль compinit обходит заново: отсюда 1062 вызова compdef и два прохода
# compaudit. PATH nix-darwin собирает сам, поэтому там дублей нет — проблема только в fpath.
typeset -U path fpath

# Только кэш: рукописных completion'ов в репозитории больше нет. Последним там
# лежал _uvx (11 КБ) — при том что uvx умеет отдавать его сам, и хранимая копия
# со временем расходилась бы с установленной версией.
fpath=("${XDG_CACHE_HOME:-$HOME/.cache}/zsh/completions" $fpath)

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
    # uv/uvx — clap-стиль. Раньше _uvx хранился готовым файлом в репозитории;
    # генерация надёжнее: копия в git не знает, какая версия uv стоит на машине.
    for tool in uv uvx; do
        (($+commands[$tool])) && [[ ! -f "$cdir/_$tool" ]] && "$tool" --generate-shell-completion zsh > "$cdir/_$tool" 2> /dev/null
    done
}

autoload -Uz compinit
# Обёртка в анонимную функцию — не косметика. Квалификатор (#q...) требует
# EXTENDED_GLOB, а его включает zinit тремя сотнями строк ниже. Без него условие
# оставалось литеральной строкой, всегда непустой, и ветка кэша была недостижима:
# полный compinit на каждый старт, 1.45s против 0.13s. local_options возвращает
# extended_glob обратно на выходе, чтобы не менять поведение остального файла.
() {
    setopt local_options extended_glob
    local dump="${ZDOTDIR:-$HOME}/.zcompdump"
    if [[ -n $dump(#qN.mh+24) ]]; then
        compinit -d "$dump"     # дамп старше суток — полная проверка с compaudit
    else
        compinit -C -d "$dump"  # свежий дамп — читаем как есть
    fi
}

# =============================================================================
# NAVIGATION & CORE
# =============================================================================

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias sz='source ~/.zshrc'

alias v='nvim'
alias b='btop'

alias c='clear'
alias e='exit'

alias ls='eza'
alias la='eza -laghm --all --icons --git --color=always' # Подробный список со скрытыми и git-статусом
alias lt='eza --tree --level=2 --icons' # Древовидный вид (2 уровня)

# Цветные алиасы для лучшего вывода
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias less='less -R' # Показывать цвета в less
# Алиас действует только на less, набранный руками. Всё, что запускает пейджер само
# — git, man, kubectl — алиаса не видит, поэтому те же флаги нужны переменной:
# -R цвета, -F не открывать пейджер ради одного экрана, -X не чистить экран на выходе,
# -i регистронезависимый поиск.
export LESS='-R -F -X -i'
# Без этого less пишет ~/.lesshst в домашний каталог. История поисков внутри
# less сама по себе почти не имеет ценности, поэтому проще выключить, чем
# заводить каталог в XDG_STATE_HOME и следить, что он существует.
export LESSHISTFILE=/dev/null

# df и du НЕ переопределяются: подмена стандартной команды флагом сбивает, когда
# нужен машинночитаемый вывод или другие единицы, а `-h` дописать быстрее, чем
# вспоминать, что именно спрятано в алиасе.

alias psa='source .venv/bin/activate'

# =============================================================================
# GIT / GITHUB / GITLAB
# =============================================================================

alias gc='git clone'
alias gs='git status'
alias gp='git pull'
# DOTFILES_DIR, а не хардкод: на macOS репозиторий лежит в ~/.dotfiles, и алиас
# с "$HOME/dotfiles" молча падал в "✗ Failed to update" на каждом запуске.
# ВНИМАНИЕ: reset --hard стирает незакоммиченное — это и есть смысл алиаса
# («принудительно из облака»), но перед запуском стоит глянуть git status.
alias dfu='(cd "$DOTFILES_DIR" && git fetch origin && git reset --hard @{u}) && echo "✓ Dotfiles updated" || echo "✗ Failed to update dotfiles"' # Обновление дот-файлов (принудительно из облака)

# GitHub CLI - Actions / Workflows
alias gha='gh run list'               # Список последних runs
alias ghaw='gh run watch'             # Watch текущего run в реальном времени
alias ghav='gh run view'              # Детали run (+ ID)
alias ghar='gh run rerun'             # Перезапуск run (+ ID)
alias gharf='gh run rerun --failed'   # Перезапуск только упавших jobs (+ ID)

# GitHub CLI - Repo
alias ghrv='gh repo view --web' # Открыть репо в браузере

# GitLab CLI - CI/CD Pipelines

# GitLab CLI - Repo

# =============================================================================
# DOCKER
# =============================================================================

alias dc='docker compose'
alias lzd='lazydocker'

# =============================================================================
# KUBERNETES
# =============================================================================

alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kl='kubectl logs -f'
alias kctx='kubectl config use-context'
alias kns='kubectl config set-context --current --namespace'

# =============================================================================
# TMUX
# =============================================================================

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
# CONF.D MODULES
# =============================================================================

# Алиасы, функции обновления, claude-функции и пер-тул шелл-функции (k9s и пр.) —
# всё вынесено в conf.d/*.zsh. Только определения, на старте лишь парсятся.
#
# Один проход, а не два, хотя это и после zinit/плагинов. Единственная реальная
# зависимость от порядка — alias'ы dpl/dpf (conf.d/devpod.zsh) внутри
# private/zsh/work-stack.sh:kvt-up(): alias-подстановка в теле функции происходит
# при ПАРСИНГЕ функции, а не при вызове, так что алиас должен существовать раньше.
# Она соблюдена: private/ грузится отдельным циклом сразу ПОСЛЕ этого. Обращения
# функция-из-функции (updm → upds/clt-update/_upd_zinit и т.п., conf.d/updates*.zsh)
# от порядка не зависят вовсе — это не алиасы, а имена функций, резолвятся в
# момент ВЫЗОВА, когда все conf.d-файлы уже прогружены. Платформенные файлы
# (updates-darwin.zsh, updates-linux.zsh, aliases-darwin.zsh) сами решают,
# грузиться ли, через `[[ $OSTYPE == darwin* ]]` в начале файла.
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

# fzf — строго ДО atuin. Оба вешают виджет на Ctrl-R; в этом порядке atuin
# перебивает его на свой поиск (так и нужно), а Ctrl-T (файл под курсор) и
# Alt-C (cd в подкаталог) остаются от fzf. В обратном порядке fzf отобрал бы
# историю у atuin. Источник списка — fd, чтобы уважался .gitignore.
if (($+commands[fzf])); then
    (($+commands[fd])) && export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git' \
        && export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND" \
        && export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
    export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
    # Гард на tty — у fzf --zsh своего нет: он безусловно трогает zle-опции и в
    # `zsh -i -c ...` (хуки, скрипты, headless-прогоны) сыплет в stderr
    # «can't change option: zle». Проверять надо именно -t 0, а не `-o zle`:
    # флаг -i включает опцию zle и без терминала, так что она тут ничего не отсекает.
    # Переменные выше нужны и в headless, биндинги — только здесь.
    [[ -t 0 ]] && eval "$(fzf --zsh)"
fi

# Atuin - улучшенная история команд с синхронизацией
eval "$(atuin init zsh)"

# atuin вешает на «?» виджет self-atuin-ai-question-mark: на пустом промпте символ
# перестаёт печататься, а вместо него уходит блокирующий сетевой запрос к LLM.
# Снимаем — вопросительный знак должен оставаться вопросительным знаком.
bindkey -r '?' 2> /dev/null
bindkey -M viins '?' self-insert 2> /dev/null

# То же самое для vicmd (normal-mode при set -o vi): atuin занимает k и /
# под atuin-up-search-vicmd/atuin-search, из-за чего пропадает штатная
# vi-навигация — «вверх по истории» и обратный инкрементальный поиск.
# Имена штатных виджетов проверены через `bindkey -M vicmd` до правки
# (up-line-or-history, а не vi-up-line-or-history, как можно было ожидать).
# Ctrl-R за atuin оставляем — это осознанный выбор.
bindkey -M vicmd 'k' up-line-or-history 2> /dev/null
bindkey -M vicmd '/' vi-history-search-backward 2> /dev/null

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
