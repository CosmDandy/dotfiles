#!/bin/sh
pane_pid=$1
cmd=$2
session=$3

case "$cmd" in
    zsh|bash|fish) echo "$session"; exit 0 ;;
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

echo "$session | $label"
