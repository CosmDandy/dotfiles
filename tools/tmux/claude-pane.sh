#!/bin/sh
# Moves the pane already running Claude Code between its own session window and a split
# beside nvim. The session is NOT restarted — the same pane moves, and the ws connection to
# claudecode.nvim holds through ~/.claude/ide/<pid>.lock, which does not depend on where
# the pane sits.
#
#   claude-pane.sh <toggle|focus|focus_toggle|show|hide|find> [origin-pane]
#
# origin is the pane whose WINDOW we work relative to (the active one by default).
# NOTE: nvim passes $TMUX_PANE explicitly, because there the active pane may already be the
# claude pane itself.
#
# Entry points: prefix+j in .tmux.conf and the tmux provider in claudecode.lua.

set -eu

action=${1:-toggle}
origin=${2:-$(tmux display-message -p '#{pane_id}')}
size=${CLAUDE_PANE_SIZE:-40%}

# NOTE: found by what runs on the pane's tty, never by pane_current_command — that name is
# whatever launched the process and differs per machine: the version number ("2.1.259") on
# the Mac, "claude" in a devcontainer, "node" back when the wrapper was one. Filtering on it
# is what silently broke this script: "claude" matched none of the names it accepted.
# The pattern is anchored so the script cannot find itself — nvim starts it on the nvim
# pane's tty, and a bare "claude" matches "claude-pane.sh" too.
find_claude_pane() {
    session=$(tmux display-message -p -t "$origin" '#{session_name}')
    tmux list-panes -s -t "$session" -F '#{pane_id} #{pane_tty}' |
        while read -r id tty; do
            if ps -t "${tty#/dev/}" -o args= 2>/dev/null |
                grep -qE '(^|/)claude([[:space:]]|$)'; then
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

# NOTE: `-a -t <nvim window>` puts claude back immediately AFTER the window it came from,
# so with renumber-windows on it keeps its previous index. -d keeps the focus here.
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
# ClaudeCodeFocus semantics: not focused — go there; focused — put it away.
# NOTE: the active pane is read from the ORIGIN WINDOW, not from the client — the call
# comes from nvim, outside the active-pane context, where `display-message` without -t lies.
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
