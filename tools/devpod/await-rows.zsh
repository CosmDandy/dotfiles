#!/usr/bin/env zsh

# Waits for the background refresh to drop a fresh row table and prints it.
#
# fzf runs this as its reload-sync command: the picker is already on screen with
# the cached rows and stays usable, so this wait costs nothing anyone can feel —
# the list is simply replaced once the ssh round trips are done.
#
# A standalone script and not a shell function, for the same reason preview.zsh
# is one: fzf spawns bind commands in their own process, where the interactive
# shell's functions do not exist.
#
# Usage: await-rows.zsh <fresh-rows> <fallback-rows> [attempts]

emulate -L zsh

local fresh=$1 fallback=$2
local -i limit=${3:-400} n=0

# NOTE: the file is only ever moved into place whole, so its mere existence is
# the handshake — there is no half-written table to guard against here.
while (( n < limit )) && [[ ! -s $fresh ]]; do
  sleep 0.02
  (( n++ ))
done

# NOTE: never exit without printing a table. Whatever comes out of here BECOMES
# the list, so an empty answer blanks the picker — if the refresh died, or was
# swept away by another run, the rows already on screen are the right answer.
if [[ -s $fresh ]]; then
  cat -- $fresh
elif [[ -s $fallback ]]; then
  cat -- $fallback
fi
