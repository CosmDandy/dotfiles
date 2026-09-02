#!/bin/sh
# Land in the workspace's own tmux session: attach to it if it is there, build
# it from the template if it is not.
#
# Runs INSIDE the container, so it is POSIX sh — the shell a container is
# guaranteed to have, whatever else got installed.
#
# The template mirrors `tn` on the mac: three windows, nvim in the first, claude
# in the second, and the first one selected.
#
# Window two waits for a lock file rather than starting claude straight away.
# nvim registers itself as an IDE by dropping one into ~/.claude/ide, and a
# claude that starts before that file exists comes up with no editor attached.
# The count is taken BEFORE nvim is sent, so the loop waits for a NEW lock and
# not for one an earlier session left behind.
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

# Sent only here, never on the attach path above: keys go to whatever is running
# in those windows, and an attach to a session already in use would type them
# into it.
locks=$(find "$HOME/.claude/ide" -maxdepth 1 -name '*.lock' 2>/dev/null | wc -l)
tmux send-keys -t "$name:1" 'nvim' C-m
tmux send-keys -t "$name:2" "while [ \$(find \"\$HOME/.claude/ide\" -maxdepth 1 -name '*.lock' 2>/dev/null | wc -l) -le $locks ]; do sleep 0.3; done && cl" C-m

tmux select-window -t "$name:1"
exec tmux attach -t "$name"
