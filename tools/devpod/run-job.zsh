#!/usr/bin/env zsh

# One dp action, run detached so the picker stays open while it happens.
#
# fzf binds spawn their own process, where the interactive shell's functions do
# not exist — so this re-enters a full interactive shell to get them back,
# private layer and catalog included. That costs ~150ms and buys `_dp_recreate`
# with its secret delivery, which no standalone script could reproduce.
#
# Each action writes two files under the jobs directory:
#   <id>.status   verb TAB state   — what the row shows while it runs
#   <id>.log      everything the action printed — Ctrl-L opens it
#
# Every part of this detaches from the terminal — `+m` and `< /dev/null` on
# each shell, and `< /dev/null` on the job block as a whole. An interactive
# shell brings job control with it, and job control reaches for the terminal
# regardless of where stdin points; in the background that earns a SIGTTIN and
# the whole thing stops with "suspended (tty input)" while fzf, which owns that
# terminal, exits. `+m` turns the monitor option off at startup, which is the
# only moment early enough to matter.
#
# Usage: run-job.zsh <verb> <jobs-dir> <rows-signal> <id>...

emulate -L zsh
setopt local_options no_monitor
zmodload zsh/datetime 2>/dev/null

# The same five-column line conf.d/devpod.zsh writes; a job that ran from the
# picker has to appear in the same file as one run by hand, or the timings are
# measured over whichever half happened to be typed.
_job_log() {
  [[ -n $DP_LOG ]] || return 0
  local d=${DP_LOG:h}
  [[ -d $d ]] || mkdir -p -- $d 2>/dev/null || return 0
  local ts
  strftime -s ts '%Y-%m-%dT%H:%M:%S' $EPOCHSECONDS
  printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$1" "$2" "$3" "${(j: :)@[4,-1]}" >> $DP_LOG
}

local verb=$1 dir=$2 signal=$3
shift 3
(( $# )) || exit 0
[[ -n $verb && -n $dir ]] || exit 1

mkdir -p -- $dir || exit 1

# The picker is watching this path: writing it is how a row redraws. Rows are
# rendered by a shell function, so the regenerating shell is the same one that
# ran the action.
_signal_rows() {
  [[ -n $signal ]] || return 0
  zsh +m -ic "_dp_rows \"\$DP_SNAPSHOT\"" < /dev/null > $signal.part 2>/dev/null
  [[ -s $signal.part ]] && mv -f -- $signal.part $signal
}

local id
for id in "$@"; do
  [[ -n $id ]] || continue
  {
    local t_start=$EPOCHREALTIME
    printf '%s\t%s\n' "$verb" running > $dir/$id.status
    _signal_rows
    # NOTE: DP_JOB tells the action nobody is watching a terminal — the age key
    # picker would otherwise sit here waiting for a choice that cannot be made.
    # NOTE: deliberately WITHOUT ZSH_NO_DEFER — the deferred queue (zinit,
    # atuin, direnv) is worthless to a job that runs one function and exits,
    # and it never fires here anyway: no line editor ever goes idle.
    DP_JOB=1 zsh +m -ic "_dp_${verb} ${(q)id}" \
      < /dev/null > $dir/$id.log 2>&1
    local rc=$?
    local -i ms; (( ms = (EPOCHREALTIME - t_start) * 1000 ))
    # Detached, so nobody was watching the clock: this row is the only record of
    # how long a backgrounded stop or recreate actually took.
    _job_log job $ms $(( rc == 0 ? 0 : 1 )) "verb=$verb" "id=$id" "rc=$rc" detached=1
    # A clean run leaves NO mark — the row goes back to plain running/stopped,
    # which is the whole report. There is deliberately no "done" state: it
    # would be written and removed a second apart, and for that second the row
    # would show a finished job nobody needs to be told about.
    # Anything else stays on screen until the next attempt clears it.
    case $rc in
      0) rm -f -- $dir/$id.status ;;
      2) printf '%s\t%s\n' "$verb" partial > $dir/$id.status ;;
      *) printf '%s\t%s\n' "$verb" failed  > $dir/$id.status ;;
    esac
    # The container's state changed, so the cached snapshot is now a lie —
    # refresh it before the row is redrawn from it.
    zsh +m -ic '_dp_snapshot_refresh' < /dev/null >/dev/null 2>&1
    _signal_rows
  } < /dev/null > /dev/null 2>&1 &!
done
