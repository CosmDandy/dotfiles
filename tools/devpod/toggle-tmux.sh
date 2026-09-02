#!/bin/sh
# Cycle the tmux landing flag: off → on → exit → off.
#
# A script and not a shell function because fzf runs key bindings in their own
# process, where the interactive shell's functions do not exist. The state is a
# file for the same reason — it has to be visible to the picker, to `ds` in
# another window, and to the next shell entirely.
#
# Usage: toggle-tmux.sh <flag-file>

flag=$1
[ -n "$flag" ] || exit 1
mkdir -p "$(dirname "$flag")" 2>/dev/null || exit 1

mode=off
[ -r "$flag" ] && mode=$(cat "$flag")

case "$mode" in
  off)  next=on ;;
  on)   next=exit ;;
  *)    next=off ;;
esac

printf '%s\n' "$next" > "$flag"
