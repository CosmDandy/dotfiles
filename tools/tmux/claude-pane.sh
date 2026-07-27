#!/bin/sh
# Пейн с уже запущенным Claude Code переезжает между собственным окном сессии и
# сплитом рядом с nvim. Сессия НЕ перезапускается — двигается тот же пейн, а
# ws-соединение с claudecode.nvim держится на ~/.claude/ide/<pid>.lock и от
# расположения пейна не зависит.
#
#   claude-pane.sh <toggle|focus|focus_toggle|show|hide|find> [origin-pane]
#
# origin — пейн, относительно ОКНА которого работаем (по умолчанию активный).
# Из nvim передаётся $TMUX_PANE: там активным может быть уже сам claude-пейн.
#
# Входы: prefix+j в .tmux.conf и tmux-провайдер claudecode.nvim
# (tools/nvim/lua/plugins/tools/claudecode.lua).

set -eu

action=${1:-toggle}
origin=${2:-$(tmux display-message -p '#{pane_id}')}
size=${CLAUDE_PANE_SIZE:-40%}

# Claude Code на tty панели: нативный бинарь даёт comm = версию (2.1.220),
# devcontainer-обёртка — node. Дальше как в pane-title.sh: ищем "claude" в args
# любого процесса на этом tty, чтобы не зависеть от глубины дерева процессов.
find_claude_pane() {
    session=$(tmux display-message -p -t "$origin" '#{session_name}')
    tmux list-panes -s -t "$session" -F '#{pane_id} #{pane_tty} #{pane_current_command}' |
        while read -r id tty cmd; do
            case "$cmd" in
            node | [0-9]*) ;;
            *) continue ;;
            esac
            if ps -t "${tty#/dev/}" -o args= 2>/dev/null | grep -q '[c]laude'; then
                printf '%s\n' "$id"
                break
            fi
        done
}

claude=$(find_claude_pane)
if [ -z "$claude" ]; then
    [ "$action" = "find" ] || tmux display-message "claude: нет запущенной сессии в этом окне tmux"
    exit 1
fi

origin_window=$(tmux display-message -p -t "$origin" '#{window_id}')
claude_window=$(tmux display-message -p -t "$claude" '#{window_id}')

show() {
    [ "$claude_window" = "$origin_window" ] && return 0
    tmux join-pane -d -h -l "$size" -s "$claude" -t "$origin"
}

# -a -t <окно nvim>: claude возвращается СРАЗУ ЗА окном, из которого пришёл, и с
# renumber-windows on занимает прежний индекс. -d — фокус остаётся здесь.
hide() {
    [ "$claude_window" = "$origin_window" ] || return 0
    if [ "$(tmux display-message -p -t "$origin_window" '#{window_panes}')" -lt 2 ]; then
        tmux display-message "claude: пейн один в окне, отделять нечего"
        return 0
    fi
    tmux break-pane -d -a -s "$claude" -t "$origin_window"
}

case "$action" in
find)
    printf '%s\n' "$claude"
    ;;
show)
    show
    ;;
hide)
    hide
    ;;
toggle)
    if [ "$claude_window" = "$origin_window" ]; then hide; else show; fi
    ;;
focus)
    show
    tmux select-pane -t "$claude"
    ;;
# Семантика ClaudeCodeFocus: не сфокусирован — перейти, сфокусирован — убрать.
# Активный пейн берём у ОКНА origin, а не у клиента: вызов приходит из nvim
# (вне контекста активного пейна), где `display-message` без -t врёт.
focus_toggle)
    if [ "$claude" = "$(tmux display-message -p -t "$origin_window" '#{pane_id}')" ]; then
        hide
    else
        show
        tmux select-pane -t "$claude"
    fi
    ;;
*)
    echo "usage: ${0##*/} <toggle|focus|focus_toggle|show|hide|find> [origin-pane]" >&2
    exit 2
    ;;
esac
