#!/usr/bin/env zsh

# The pickers' header: one line, and only when something is wrong with what the
# rows say. Empty output is the normal case — a line that always says "fine"
# stops being read, and the one day it says otherwise goes unseen with it.
#
# Two things are worth a line:
#   - a host that did not answer the last collection. Its rows already say
#     "host silent"; this names the host once, with the likely cause.
#   - a refresh in flight on top of rows older than a minute, so stale states
#     on screen are known to be about to change.
#
# A script and not a function: fzf's transform-header runs a command, and the
# picker re-asks it every time fresh rows land.
#
# Usage: status.zsh <snapshot>

emulate -L zsh
zmodload -F zsh/stat b:zstat
zmodload zsh/datetime

local snap=$1
[[ -s $snap ]] || exit 0

local Y=$'\e[38;2;181;137;0m' M=$'\e[38;2;88;110;117m' O=$'\e[0m'

local -a m
zstat -A m +mtime -- $snap 2>/dev/null || exit 0
local -i s=$(( EPOCHSECONDS - m[1] ))
local age
if (( s >= 3600 )); then age="$(( s / 3600 ))h$(( s % 3600 / 60 ))m"
elif (( s >= 60 )); then age="$(( s / 60 ))m"
else age="${s}s"; fi

# Column 2 is the state, column 4 the provider host ("-" is the local docker).
local -aU silent
local line
local -a c
for line in ${(f)"$(< $snap)"}; do
  c=(${(ps:\t:)line})
  [[ $c[2] == unknown ]] && silent+=(${${c[4]}/#-/local docker})
done

# NOTE: the refresh's half-written table is the in-flight marker. It exists
# exactly while a collection runs and is renamed over the snapshot when it
# ends, so there is no flag to set or forget to clear.
local -a busy=( $snap.*(N) )

if (( $#silent )); then
  print -r -- "${Y}⚠ ${(j:, :)silent} not answering — VPN down?${O}"
elif (( $#busy && s >= 60 )); then
  print -r -- "${M}↻ refreshing — states are ${age} old${O}"
fi
