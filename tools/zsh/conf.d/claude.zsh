# Claude Code — алиасы запуска и функции памяти. Одинаковы на маке и в контейнере.

# Порог автокомпакта. Он ЕСТЬ в env-блоке settings.json, но этого мало: оттуда
# переменные раздаются дочерним процессам (Bash-туллы, хуки), а сам Claude Code
# читает порог из своего process.env — то есть видит только то, что было в
# окружении на момент запуска. Сессию, рождённую демоном, окружением снабжает
# демон; `claude`, запущенный руками из оболочки, остаётся без него и откатывается
# на дефолт «окно−13000» (≈987К вместо 650К на окне 1М).
# Измерено в одном контейнере: сессия демона — 4 компакта, 258К; сессия из
# оболочки при том же settings.json — 819К и ни одного автокомпакта.
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=65

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
