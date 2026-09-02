#!/bin/sh
pane_pid=$1
cmd=$2
session=$3

in_container() {
    [ "$(uname -s)" = "Linux" ] || return 1
    [ -e /proc/vz ] && [ ! -e /proc/bc ] && return 0
    [ -e /run/host/container-manager ] && return 0
    [ -e /dev/incus/sock ] && return 0
    [ -e /run/.containerenv ] && return 0
    [ -e /.dockerenv ] && return 0
    if [ -r /run/systemd/container ]; then
        read -r _c </run/systemd/container
        [ "$_c" != "wsl" ] && return 0
    fi
    return 1
}

if in_container; then
    prefix="󰆧  $session"
else
    prefix="$session"
fi

# The window title is drawn by the system font, not by the terminal font: the dotted
# circle that reads fine in tmux turns into a tiny speck in SF Pro. Hence its own
# glyphs here, overriding the script's defaults.
# Same glyphs as everywhere else. They used to differ here — the system font draws
# the title, and the dotted circle came out as a speck — but two different circles
# for one state read as two states, which is worse than a small glyph.
badge=$("$(dirname "$0")/../claude/claude-sessions.py" 2>/dev/null)

case "$cmd" in
zsh | bash | fish)
    if [ -n "$badge" ]; then
        echo "$prefix · $badge"
    else
        echo "$prefix"
    fi
    exit 0
    ;;
esac

label="$cmd"

# NOTE: Claude Code is either a node wrapper (devcontainers) or the native binary, whose
# comm is its version number — so "claude" is looked for in the args of any process on the
# pane's tty, which does not depend on the depth of the process tree.
case "$cmd" in
node | [0-9]*)
    tty=$(ps -o tty= -p "$pane_pid" 2>/dev/null | tr -d ' ')
    if [ -n "$tty" ]; then
        case "$(ps -t "$tty" -o args= 2>/dev/null)" in
        *claude*) label="claude" ;;
        esac
    fi
    ;;
esac

if [ -n "$badge" ]; then
    echo "$prefix · $label · $badge"
else
    echo "$prefix · $label"
fi
