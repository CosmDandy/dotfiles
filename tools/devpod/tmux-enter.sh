#!/bin/sh
# Land in the workspace's own tmux session: attach to it if it is there, build
# it from the template if it is not.
#
# Runs INSIDE the container, so it is POSIX sh — the shell a container is
# guaranteed to have, whatever else got installed.
#
# The template mirrors `tn` on the mac (three windows, the first one selected)
# without starting anything in them: what belongs in window two differs between
# a work repository and a personal one, and guessing wrong costs more than the
# keystroke it saves.
#
# Usage: tmux-enter.sh <session-name>

name=${1:-dev}

# The terminal's own terminfo may not exist in here — xterm-ghostty is the one
# that bites, since the entry is not an interactive shell and .zshrc, which
# normally corrects this, never runs. tmux refuses to start at all on an unknown
# TERM ("missing or unsuitable terminal"), so fall back to a description every
# container has.
if ! infocmp "$TERM" >/dev/null 2>&1; then
  TERM=xterm-256color
  export TERM
fi

if ! command -v tmux >/dev/null 2>&1; then
  # Not a failure worth refusing over: the point of the flag is tmux when there
  # is tmux, and a plain shell is a perfectly good container to work in.
  echo "tmux-enter: no tmux in this container — plain shell" >&2
  exec "${SHELL:-/bin/sh}" -l
fi

if tmux has-session -t "$name" 2>/dev/null; then
  exec tmux attach -t "$name"
fi

tmux new-session -d -s "$name"
tmux new-window -t "$name:"
tmux new-window -t "$name:"
tmux select-window -t "$name:1"
exec tmux attach -t "$name"
