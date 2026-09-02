#!/usr/bin/env zsh
# Deliver one or more secrets, then refresh what the picker knows.
#
# Run through fzf's `execute`, which hands over the whole terminal — so a
# delivery that needs to ask something (the age key's vault entry) can ask.
#
# The snapshot refresh is the point of the second half: the row's state comes
# from there, and without it a delivered secret keeps showing as missing.
#
# Usage: put-secret.zsh <workspace-id> <name>...
emulate -L zsh
local id=$1; shift
[[ -n $id ]] && (( $# )) || exit 0
zsh +m -ic "_dp_secrets ${(q)id} ${(j: :)${(q)@}}"
local rc=$?
zsh +m -ic '_dp_snapshot_refresh' < /dev/null >/dev/null 2>&1
exit $rc
