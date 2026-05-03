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
    prefix="⬢ $session"
else
    prefix="$session"
fi

case "$cmd" in
zsh | bash | fish)
    echo "$prefix"
    exit 0
    ;;
esac

label="$cmd"

if [ "$cmd" = "node" ]; then
    child=$(pgrep -P "$pane_pid" 2>/dev/null | head -1)
    if [ -n "$child" ]; then
        args=$(ps -o args= -p "$child" 2>/dev/null)
    else
        args=$(ps -o args= -p "$pane_pid" 2>/dev/null)
    fi
    case "$args" in
    *claude*) label="claude" ;;
    esac
fi

echo "$prefix | $label"
