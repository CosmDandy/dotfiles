#!/usr/bin/env zsh

# Waits until somebody drops a fresh row table, then prints it.
#
# fzf runs this as its reload-sync command, and the binding is NOT unbound
# afterwards: printing a table fires `load` again, which starts another wait.
# That loop is what keeps the picker live — a background refresh, a stop or a
# recreate all announce themselves by writing the table, and the row redraws
# without anyone touching a key.
#
# The picker stays on screen and usable throughout: reload-sync keeps the
# current rows until new ones arrive, so a wait here costs nothing anyone can
# feel.
#
# A standalone script and not a shell function, for the same reason preview.zsh
# is one: fzf spawns bind commands in their own process, where the interactive
# shell's functions do not exist.
#
# Usage: await-rows.zsh <fresh-rows> <fallback-rows> [seconds]

emulate -L zsh

local fresh=$1 fallback=$2
# Ten minutes, and the only thing a timeout costs is one redraw of rows that
# are already on screen. Short enough that a picker left open overnight is not
# holding a process forever, long enough that idle costs nothing.
local -F wait_s=${3:-600} step=0.1
local -F waited=0

# NOTE: the file is only ever moved into place whole, so its mere existence is
# the handshake — there is no half-written table to guard against here.
while (( waited < wait_s )) && [[ ! -s $fresh ]]; do
  sleep $step
  (( waited += step ))
done

# Taking the fresh table becomes the new fallback: the next wait starts from
# what is on screen right now, so a timeout redraws the current rows rather
# than rows from several refreshes ago.
if [[ -s $fresh ]]; then
  mv -f -- $fresh $fallback 2>/dev/null || cat -- $fresh
fi

# NOTE: never exit without printing a table. Whatever comes out of here BECOMES
# the list, so an empty answer blanks the picker — if the refresh died, or was
# swept away by another run, the rows already on screen are the right answer.
[[ -s $fallback ]] && cat -- $fallback
