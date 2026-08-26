#!/usr/bin/env zsh

# The full output of the last background action on one workspace.
#
# Bound to Ctrl-L in the picker through `execute`, which hands this script the
# whole terminal and puts the picker back when it exits — so a pager is exactly
# the right thing to run here.
#
# Usage: show-log.zsh <jobs-dir> <id>

emulate -L zsh

local dir=$1 id=$2
local log=$dir/$id.log

if [[ ! -s $log ]]; then
  # NOTE: printed rather than silently returning. A key that appears to do
  # nothing is indistinguishable from a broken binding.
  print -r -- "no background action has run on ${id:-this workspace} yet"
  print -r -- ""
  print -rn -- "press enter"
  read -r
  exit 0
fi

# +G: land at the end, which is where a finished job says how it went. -R keeps
# the colours the actions print.
# NOTE: LESS is emptied on purpose. The environment sets -F (quit if the text
# fits one screen) and most job logs are three lines — less printed them and
# exited before anyone could read, which from the picker looked exactly like a
# key that does nothing. -X is dropped with it, so the log is drawn on the
# alternate screen and the picker comes back clean.
if (( $+commands[less] )); then
  LESS= less -R -i +G -- $log
else
  cat -- $log
  print -rn -- "press enter"
  read -r
fi
