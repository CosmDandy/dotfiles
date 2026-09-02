#!/usr/bin/env zsh

# Confirmation for the destructive keys, run inside the picker.
#
# fzf cannot ask a question on its own, but it can be TOLD what to become: this
# script prints a list of fzf actions and fzf carries them out. Arming replaces
# the workspace list with a plain yes/no, rewrites the prompt and turns the
# footer into a warning naming what is about to happen. The next Enter comes
# back here and either runs the thing or puts everything back.
#
# The word has to be TYPED. Selecting a row is not enough — the whole point is
# that nothing destructive happens by reflex, and a cursor sitting on the right
# row is exactly that reflex. So the answer is read from the search line and
# must be exactly "yes".
#
# The list still holds a single "yes" row, and that is a workaround, not a
# choice: fzf does not fire Enter when the list is empty, so typing "yes" has
# to leave something matching or the confirmation becomes unanswerable. Pressing
# Enter on that row without typing still cancels — the query, not the cursor,
# is what is checked.
#
# NOTE: this is a script and not a chain of actions inside --bind, because fzf
# balances parentheses when it parses a binding: a `change-prompt(workspace> )`
# nested inside a `transform(...)` ends the transform at the wrong bracket and
# the rest of the expression lands in the prompt. Printing the actions from
# here keeps the nesting one level deep.
#
# Usage: confirm.zsh arm <verb> <state> <targets> <id...>
#        confirm.zsh run <state> <targets> <selected> <base> <jobs> <signal> <runner> <flag>

emulate -L zsh

local cmd=$1; shift

case $cmd in
arm)
  local verb=$1 state=$2 targets=$3; shift 3
  local -a ids=("$@")
  ids=(${ids:#})
  (( $#ids )) || { print -rn -- ''; exit 0 }
  print -r -- "$verb" > $state
  print -rl -- $ids > $targets

  local what
  case $verb in
    recreate) what='rebuild the container from scratch — its home, and every secret in it, is replaced' ;;
    delete)   what='delete the workspace and its container for good' ;;
    *)        what="run $verb" ;;
  esac

  local names="${(j:, :)ids}"
  (( $#ids > 3 )) && names="${(j:, :)ids[1,3]} and $(( $#ids - 3 )) more"
  local R=$'\e[38;2;220;50;47m' O=$'\e[0m'

  # NOTE: clear-query first. Whatever was typed to find the workspace is still
  # in the search line, and it filters the yes/no list to nothing — leaving a
  # confirmation that cannot be answered, because fzf does not fire Enter on an
  # empty list.
  # NOTE: one row, and it is only there to keep Enter alive. A stray Enter with
  # an empty query cancels. This cost a real workspace before it was written.
  print -rn -- "clear-query+reload(printf 'yes\\n')"
  print -rn -- "+change-prompt($verb $names — type yes> )"
  print -rn -- "+change-footer(${R}about to $what${O})"
  # The preview describes a workspace, and the rows are now yes and no — it
  # would sit there reporting "no data for yes", which reads like a fault.
  print -rn -- '+change-preview-window(hidden)'
  ;;

run)
  # $typed is the search line, not the highlighted row: the answer must be
  # written out, every time, by hand.
  local state=$1 targets=$2 typed=$3 base=$4 jobs=$5 signal=$6 runner=$7 flag=$8
  local verb=
  [[ -r $state ]] && verb=$(< $state)

  # Nothing armed: Enter means what it always meant.
  if [[ -z $verb ]]; then
    print -rn -- 'accept'
    exit 0
  fi

  local dot=${DOTFILES_DIR:-$HOME/.dotfiles}
  local -a restore=(
    'clear-query'
    "+reload(cat $base)"
    "+change-prompt(workspace> )"
    "+transform-footer($dot/tools/devpod/footer.zsh $flag)"
    '+change-preview-window(right,46%,border-left)'
  )

  if [[ $typed == yes ]]; then
    local -a ids=(${(f)"$(< $targets)"})
    ids=(${ids:#})
    rm -f -- $state $targets
    if (( $#ids )); then
      print -rn -- "execute-silent($runner $verb $jobs $signal ${ids})+"
    fi
    print -rn -- "${(j::)restore}"
  else
    # Anything else is a no: an empty line, a half-typed "ye", a stray Enter.
    rm -f -- $state $targets
    print -rn -- "${(j::)restore}"
  fi
  ;;
esac
