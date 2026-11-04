#!/bin/sh
# Land in a workspace's own tmux session: attach to it if it is there, build it
# from the template if it is not. The one template for both entries — `tn` on
# the mac and `ds` into a devcontainer.
#
# POSIX sh, because `ds` runs it INSIDE the container — the shell a container is
# guaranteed to have, whatever else got installed.
#
# The template: three windows, nvim in the first, the coding agent in the
# second, and the first one selected.
#
# Usage: tmux-enter.sh <session-name> [dir] [agent]
#   agent: claude | opencode | pi — defaults to $WORKSPACE_AGENT, then claude.
#   `ds` passes the mac's $WORKSPACE_AGENT explicitly: no env var survives the
#   ssh hop into the container.

name=${1:-dev}
dir=${2:-}
agent=${3:-${WORKSPACE_AGENT:-claude}}

case $agent in
  claude | opencode | pi) ;;
  *)
    echo "tmux-enter: unknown agent '$agent' (claude, opencode, pi)" >&2
    exit 2
    ;;
esac

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

enter() {
  if [ -n "$TMUX" ]; then
    tmux switch-client -t "$name"
    exec tmux refresh-client -S
  fi
  exec tmux attach -t "$name"
}

tmux has-session -t "$name" 2>/dev/null && enter

# NOTE: new windows inherit the session's directory, so one cd covers all three.
if [ -n "$dir" ]; then
  cd "$dir" || exit 1
fi

tmux new-session -d -s "$name"
tmux new-window -t "$name:"
tmux new-window -t "$name:"

# Sent only here, never on the attach path above: keys go to whatever is running
# in those windows, and an attach to a session already in use would type them
# into it.
if [ "$agent" = claude ]; then
  # NOTE: nvim registers itself as an IDE by dropping a lock into ~/.claude/ide,
  # and a claude started before that file exists comes up with no editor
  # attached. The count is taken BEFORE nvim is sent, so the loop waits for a
  # NEW lock and not for one an earlier session left behind.
  locks=$(find "$HOME/.claude/ide" -maxdepth 1 -name '*.lock' 2>/dev/null | wc -l)
  tmux send-keys -t "$name:1" 'nvim' C-m
  tmux send-keys -t "$name:2" "while [ \$(find \"\$HOME/.claude/ide\" -maxdepth 1 -name '*.lock' 2>/dev/null | wc -l) -le $locks ]; do sleep 0.3; done && cl" C-m
else
  tmux send-keys -t "$name:1" 'nvim' C-m
  tmux send-keys -t "$name:2" "$agent" C-m
fi

tmux select-window -t "$name:1"
enter
