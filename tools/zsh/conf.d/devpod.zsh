# DevPod: workspace aliases plus delivery of the zone's age key into a
# container.
#
# The key belongs to the ZONE (the remote docker host), not to a person: root
# there is not only mine, so the mac's personal key never goes in and zone
# secrets are encrypted with a separate pair.
#
# The entry name is kept neutral because this file is public — the real one is
# overridden in private/zsh/, which is sourced later.
alias dpd='devpod delete'

# Every call this tool makes, with what it cost. The point is not debugging a
# single run — it is having enough runs to answer "what timeout is right here",
# which no single observation can.
#
# TSV, five columns: when, what, how long in ms, how it went, then free
# key=value pairs. Appended one short line at a time, so several shells and the
# detached job runner can all write to it without a lock: writes under the pipe
# buffer are atomic with O_APPEND.
: ${DP_LOG:=${XDG_STATE_HOME:-$HOME/.local/state}/dp/events.tsv}
# Exported: the detached job runner is a separate process and has to land in the
# same file, or a recreate started from the picker would be missing from exactly
# the statistics it matters most to.
typeset -gx DP_LOG
# Rolled at a size, not a date: this is measurement data, and what matters is
# keeping the recent stretch complete rather than aligning it to days.
: ${DP_LOG_MAX_KB:=2048}

# How `ds` lands in a container, remembered between shells so the answer does
# not have to be retyped every session. Three states, cycled with Ctrl-T in the
# picker: off — a plain login shell, as before; on — attach to the workspace's
# own tmux session (built from a template the first time); exit — the same, and
# the local shell exits when you detach, which closes the terminal tab with it.
: ${DP_TMUX_FLAG:=${XDG_STATE_HOME:-$HOME/.local/state}/dp/tmux-mode}

_dp_tmux_mode() {
  emulate -L zsh
  local m=off
  [[ -r $DP_TMUX_FLAG ]] && m=$(< $DP_TMUX_FLAG)
  case $m in on|exit) print -r -- $m ;; *) print -r -- off ;; esac
}

_dp_tmux_set() {
  emulate -L zsh
  local dir=${DP_TMUX_FLAG:h}
  [[ -d $dir ]] || mkdir -p -- $dir 2>/dev/null || return 1
  print -r -- "$1" > $DP_TMUX_FLAG
}

# off → on → exit → off. One key, and the footer says which of the three it is.
_dp_tmux_cycle() {
  emulate -L zsh
  case $(_dp_tmux_mode) in
    off) _dp_tmux_set on ;;
    on)  _dp_tmux_set exit ;;
    *)   _dp_tmux_set off ;;
  esac
}

zmodload zsh/datetime 2>/dev/null

# NOTE: no external commands anywhere in here — no date(1), no stat(1). This
# runs on the path being measured, and a fork would be a large share of what it
# is trying to measure.
_dp_log() {
  emulate -L zsh
  [[ -n $DP_LOG ]] || return 0
  # NOTE: not `status` — zsh keeps that name for $? and the assignment fails
  # with "read-only variable", which in a logging function means every single
  # call dies silently on the path it was meant to measure.
  local event=$1 ms=$2 st=$3
  shift 3
  local dir=${DP_LOG:h}
  [[ -d $dir ]] || mkdir -p -- $dir 2>/dev/null || return 0
  # NOTE: strftime, not prompt expansion. `${(%):-%D{...}}` reads the first `}`
  # of the format as the end of the substitution and leaves a stray brace in the
  # timestamp. NOTE: printf, not `print -r` — the latter does not turn \t into a
  # tab, and the columns arrive as one literal string.
  local ts
  strftime -s ts '%Y-%m-%dT%H:%M:%S' $EPOCHSECONDS
  printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$event" "$ms" "$st" "${(j: :)@}" >> $DP_LOG
}

# Called where a run begins, not on every line: one stat per picker opening is
# free, one per logged event would not be.
_dp_log_roll() {
  emulate -L zsh
  [[ -n $DP_LOG ]] || return 0
  local -a big=( $DP_LOG(N.Lk+$DP_LOG_MAX_KB) )
  (( $#big )) && mv -f -- $DP_LOG $DP_LOG.1 2>/dev/null
  return 0
}

# Was the multiplexed connection to this workspace already up? The whole
# fast-path story turns on it, and the answer is one stat of the control socket
# — asking ssh itself would cost a fork of the thing being measured.
_dp_master_state() {
  emulate -L zsh
  local -a sock=( $HOME/.ssh/sockets/*@${1}.devpod:22(N=) )
  (( $#sock )) && print -r -- up || print -r -- down
}

# Where new workspaces come from. The registry is public; the provider is left
# empty here so devpod's own default applies, and the private layer overrides it
# with the work host.
: ${DP_IMAGE:=ghcr.io/cosmdandy/devcontainer}
: ${DP_PROVIDER:=}
# Who to be inside a container. The image bakes this user in, but a repository
# carrying its own devcontainer.json without remoteUser drops it, and devpod
# then falls back to root.
: ${DP_USER:=$USER}
# NOTE: `dp` used to be an alias for `devpod up --workspace-env-file …`. It is a
# function now (bottom of this file) and the alias had to go: an alias is
# substituted while the FUNCTION DEFINITION is parsed, so `dp() {` would have
# expanded into the alias body and never defined anything.
# The env-file lives on inside `_dp_up_one`, and so does the reasoning that put
# it there: the profile comes from the image tag, and --dotfiles was dropped in
# favour of an onCreateCommand baked into the image label.

: ${DPKEY_ITEM:=host-age-key}   # starting fzf query, not a fixed choice
: ${DPKEY_FIELD:=}              # non-empty → read a custom field (rbw get -f)
: ${DPKEY_FILTER:=age}          # how rbw entries are filtered; empty → show all

# Entering a container. NOTE: `devpod ssh` rebuilds its tunnel every call —
# 5.8s. The <id>.devpod entry devpod writes into the ssh config uses the same
# ProxyCommand but falls under ControlMaster from the `Host *` block: 0.15s once
# the master socket is up, with agent forwarding intact. The fallback covers a
# workspace whose entry does not exist yet.
# NOTE: checked with `ssh -G`, which answers with the resolved configuration,
# rather than by reading ~/.ssh by hand.
ds() {
  emulate -L zsh
  local id
  if (( $# )); then id=$1; shift; else id=$(_dp_pick) || return 1; fi
  [[ -z $id ]] && { print -u2 "ds: no workspace selected"; return 1 }

  local _t0=$EPOCHREALTIME
  local _master=$(_dp_master_state "$id")
  local -i ms rc
  # NOTE: only when no command was given. `ds id "some command"` is somebody
  # asking for that command, not for a session to live in.
  local _mode=$(_dp_tmux_mode) _enter=
  if [[ $_mode != off ]] && (( ! $# )); then
    # NOTE: `[ -x … ]` and not `script || fallback`. A clone that predates the
    # script made the shell print "no such file or directory" before falling
    # back — an error message for a situation that is handled.
    # NOTE: the agent symlink is refreshed HERE, before anything attaches. The
    # panes of an existing tmux session hold that stable path, and only an
    # interactive shell re-points it (.zshrc) — which never runs here, since ssh
    # is handed a command. Without this, every re-entry that forwards an agent
    # lands in panes whose agent is the previous session's socket: the file
    # survives in /tmp, so the `-S` test still passes and nothing looks wrong
    # until a key is actually needed and ssh answers "Connection refused".
    # NOTE: ask the old link whether it still answers before overwriting it —
    # a second tab entering the same workspace would otherwise pull the panes
    # of the session already working there onto its own socket. Only a clear
    # "it answered" (0, or 1 for an empty agent) buys the link a reprieve;
    # anything else, ssh-add missing included, means re-point.
    _enter='S=$HOME/.ssh/ssh_auth_sock; if [ -n "$SSH_AUTH_SOCK" ] && [ "$SSH_AUTH_SOCK" != "$S" ]; then '
    _enter+='SSH_AUTH_SOCK=$S ssh-add -l >/dev/null 2>&1; case $? in 0|1) : ;; '
    _enter+='*) mkdir -p -m 700 "$HOME/.ssh" && ln -sf "$SSH_AUTH_SOCK" "$S";; esac; fi; '
    # NOTE: TERM is normalised BEFORE the script is exec'd, not after. This runs
    # as a non-interactive shell, so .zshrc never corrects an unknown
    # xterm-ghostty and tmux refuses to start on one — and the container's own
    # copy of the script cannot be relied on to do it, because a clone that
    # predates the fix still gets exec'd. Seen exactly that: five
    # "missing or unsuitable terminal: xterm-ghostty" from a stale clone, while
    # the correction sat in the fallback branch that an existing script skips.
    _enter+='infocmp "$TERM" >/dev/null 2>&1 || export TERM=xterm-256color; '
    local _script='$HOME/dotfiles/tools/devpod/tmux-enter.sh'
    _enter+="if [ -x $_script ]; then exec $_script $id; fi; "
    # NOTE: a container without tmux is not an error — the flag means "tmux
    # when there is tmux". Without this the entry died with "command not found:
    # tmux" and dropped the user back on the mac, which is a worse outcome than
    # the plain shell they would have got with the flag off.
    _enter+='command -v tmux >/dev/null 2>&1 || exec "${SHELL:-/bin/sh}" -l; '
    _enter+="exec tmux new-session -A -s $id"
  fi
  if ssh -G "${id}.devpod" 2>/dev/null | grep -qi '^proxycommand.*devpod'; then
    # How long it takes to GET there, measured separately from how long the
    # session then lasts — the wall clock of an interactive shell says how long
    # somebody worked, which is not a number any timeout is set from.
    # One extra round trip: milliseconds when the multiplexed connection is up,
    # and when it is not, this is the handshake the login would have paid
    # anyway — it just pays it here and leaves the master warm.
    # NOTE: only for a container that is already up. On a stopped one the
    # ProxyCommand has to start it first, which takes far longer than any
    # connect timeout worth setting — measured: 5s spent, rc=255, and those
    # five seconds were added to the wait before the real login even began.
    # A start is not what this row is supposed to measure anyway.
    if [[ $(_dp_snap_state "$id") == running ]]; then
      local _tc=$EPOCHREALTIME
      ssh -o BatchMode=yes -o ConnectTimeout=5 -T "${id}.devpod" true 2>/dev/null
      rc=$?
      (( ms = (EPOCHREALTIME - _tc) * 1000 ))
      _dp_log connect $ms $(( rc == 0 ? 0 : 1 )) "id=$id" path=fast "master=$_master" "rc=$rc"
    fi
    if [[ -n $_enter ]]; then
      ssh -t "${id}.devpod" "$_enter"
    else
      ssh "${id}.devpod" "$@"
    fi
    rc=$?
    (( ms = (EPOCHREALTIME - _t0) * 1000 ))
    _dp_log session $ms $(( rc == 0 ? 0 : 1 )) "id=$id" path=fast "master=$_master" "rc=$rc" "tmux=$_mode"
    # Detaching from tmux leaves the work running on the other side, so there is
    # nothing left for this shell to do — and closing it closes the tab.
    # NOTE: only after a SUCCESSFUL session. A failed entry that closes the tab
    # takes the error message with it, and the next thing anybody sees is a
    # terminal that shut itself — which is exactly how this looked from outside.
    [[ $_mode == exit && -n $_enter ]] && (( rc == 0 )) && exit $rc
    return $rc
  else
    # NOTE: --user for OUR image only. devpod takes the user from the image
    # label, and a repository whose own devcontainer.json omits remoteUser
    # overrides it with nothing — which is how `git status` in a work repo
    # answers "detected dubious ownership" instead of listing files. But a
    # workspace built from somebody else's devcontainer.json has no such user
    # at all, and there the flag turns a working login into a hang on `su`.
    local -a u=()
    [[ $(_dp_ws_field "$id" .devContainerImage) == ${DP_IMAGE}:* ]] \
      && u=(--user "$DP_USER")
    if [[ -n $_enter ]]; then
      devpod ssh "$id" $u --command "$_enter"
    else
      devpod ssh "$id" $u "$@"
    fi
    rc=$?
    (( ms = (EPOCHREALTIME - _t0) * 1000 ))
    # NOTE: no separate connect row on this path. `devpod ssh` builds its tunnel
    # from scratch every call — measuring it would mean paying those ~6s twice,
    # which is precisely the cost this whole fast/slow distinction is about.
    _dp_log session $ms $(( rc == 0 ? 0 : 1 )) "id=$id" path=devpod "master=$_master" "rc=$rc" "tmux=$_mode"
    [[ $_mode == exit && -n $_enter ]] && (( rc == 0 )) && exit $rc
    return $rc
  fi
}

# Stopping one, the short way. A function and not an alias so that a bare `dps`
# can open the picker, the way `ds` does.
dps() {
  emulate -L zsh
  local -a ids
  if (( $# )); then
    ids=("$@")
  else
    # -m: stopping several at once is the normal case at the end of a day.
    local out
    out=$(_dp_pick -m) || return 1
    ids=(${(f)out})
  fi
  ids=(${ids:#})
  (( $#ids )) || { print -u2 "dps: no workspace selected"; return 1 }
  _dp_stop $ids
}

# Row colours, carried by the data itself: fzf paints the whole line and cannot
# tell one column from another. Solarized accents, so they hold on both the
# light and the dark background — the same values the editor uses.
typeset -g _DP_MUTED=$'\e[38;2;88;110;117m'
typeset -g _DP_GREEN=$'\e[38;2;133;153;0m'
typeset -g _DP_BLUE=$'\e[38;2;38;139;210m'
typeset -g _DP_CYAN=$'\e[38;2;42;161;152m'
typeset -g _DP_YELLOW=$'\e[38;2;181;137;0m'
typeset -g _DP_RED=$'\e[38;2;220;50;47m'
# NOTE: SGR 2 is the closest a terminal has to a lighter weight — ghostty draws
# it as reduced intensity rather than a thinner face, which is what is wanted
# for a column that should recede without disappearing.
typeset -g _DP_FAINT=$'\e[2m'
typeset -g _DP_OFF=$'\e[0m'

# The catalog is contributed, not owned: this file only declares the array, the
# private layer appends the work repositories, and a personal entry can be added
# anywhere. One line per repository: profile|repo|id|set
typeset -ga DP_CATALOG

# ── the prepared snapshot ─────────────────────────────────────────────────────
#
# Everything the picker shows costs network: one ssh per provider host, and a
# ControlMaster that has expired puts a 313 ms handshake in front of that. So
# `dp` never collects on demand — it draws the snapshot it already has and
# refreshes it behind the picker, which is also what makes the next run instant.
typeset -g DP_CACHE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/devpod
typeset -g DP_SNAPSHOT=$DP_CACHE_DIR/snapshot.tsv
# How stale a snapshot may be for a caller that cannot redraw itself — `dp ls`
# and the plain pickers. The interactive picker ignores this: it shows whatever
# is on disk and swaps in the fresh table when it lands.
: ${DP_CACHE_TTL:=15}

# NOTE: the real pid, not $$. A forked subshell in zsh keeps the PARENT's $$, so
# two background refreshes started from one terminal would write to the same
# temp file and one of them would move a half-written table into place.
zmodload -F zsh/system p:sysparams 2>/dev/null

# NOTE: and the pid is not enough for the row files either. Those names are
# built by the interactive shell BEFORE it forks, so every `dp` in one terminal
# would reuse them — and a picker aborted with Esc leaves its refresh running,
# which then writes into the next picker's file while that one is reading it.
# One counter per run keeps them apart.
typeset -gi _DP_RUN=0

_dp_cache_dir() {
  [[ -d $DP_CACHE_DIR ]] && return 0
  mkdir -p -- $DP_CACHE_DIR
}

# id, uid, provider and provider host for every workspace devpod knows about —
# straight out of the local state, no network.
# NOTE: the HOST comes from the stored provider options, NOT from `devpod
# provider options`: that call takes ~1.6s per provider and a picker cannot
# afford it.
# NOTE: read from the files, NOT from `devpod list`. Measured: the CLI takes
# 934 ms to answer, the same jq over the same files takes 16 ms, and every field
# `devpod list` returns is right here — id, provider, lastUsed, source. That one
# substitution is most of what made the picker feel slow.
_dp_meta() {
  emulate -L zsh
  local -a files=(${HOME}/.devpod/contexts/*/workspaces/*/workspace.json(N))
  (( $#files )) || return 0
  jq -r '[.id, (.uid // "-"), (.provider.name // "-"),
          (.provider.options.HOST.value // "-"),
          (.lastUsed // "-"),
          (.source.gitRepository // .source.localFolder // "-"),
          (.devContainerImage // "-")] | @tsv' $files 2>/dev/null \
    | sort -t$'\t' -k5,5r
}

# uid<TAB>state<TAB>image for every container, one docker call per HOST rather
# than one per workspace: the label carries the workspace uid, and the uid is
# already known locally, so the join costs nothing.
# One host asked, and the round trip recorded. A function rather than two lines
# inline because the measurement belongs next to the call: this ssh is the
# single slowest thing the tool does, and every timeout question — is 5s enough
# to connect, does a host ever answer after 2s — is answered from this row.
_dp_probe_one() {
  emulate -L zsh
  local host=$1 t=$2 probe=$3
  local t0=$EPOCHREALTIME
  if [[ $host == LOCAL ]]; then
    sh "$probe" > "$t" 2>/dev/null
  else
    ssh -o BatchMode=yes -o ConnectTimeout=5 -T "$host" 'sh -s' \
      < "$probe" > "$t" 2>/dev/null
  fi
  local -i rc=$? ms
  (( ms = (EPOCHREALTIME - t0) * 1000 ))
  # The sentinel, not the exit status, is what says the answer is usable — the
  # same distinction the collection below draws between "no containers" and
  # "nobody answered".
  local -i ok=1
  grep -q '^#ok$' "$t" 2>/dev/null && ok=0
  _dp_log probe $ms $ok "host=$host" "rc=$rc"
}

_dp_state() {
  emulate -L zsh
  # NOTE: no_monitor, or every backgrounded host prints its job number over the
  # picker that is about to open.
  setopt local_options no_monitor
  local -A hosts
  local id uid prov host rest
  while IFS=$'\t' read -r id uid prov host rest; do
    # NOTE: "-" IS the local provider. _dp_meta writes a dash for every missing
    # field (empty columns shift the whole row), so testing for an empty string
    # here stopped querying the local docker entirely and every local workspace
    # was reported as "no container" while its container sat there stopped.
    [[ $host == - ]] && host=
    hosts[${host:-LOCAL}]=1
  done < <(_dp_meta)
  # NOTE: --filter is not cosmetic. Listing every container costs 464 ms on a
  # machine with a normal amount of docker on it; asking the daemon to filter by
  # the label we are going to read anyway costs 34 ms. Containers without the
  # label are not devpod's and were never wanted here.
  # NOTE: a script piped to the host, not a command string. It also asks each
  # RUNNING container whether its secrets are in place — that needs quotes
  # inside quotes inside ssh, which is exactly where inline commands break.
  # Costs ~170 ms more per host (one `docker exec` per running container), and
  # that is affordable only because collection happens behind the picker.
  local probe=${DOTFILES_DIR:-$HOME/.dotfiles}/tools/devpod/probe-host.sh
  [[ -r $probe ]] || return 1
  # NOTE: hosts are asked in PARALLEL. Sequentially the wall clock is the sum of
  # every provider — 261 ms for the local docker plus 140 ms over ssh — while
  # nothing here depends on anything else.
  # NOTE: not mktemp. Two forks of an external binary cost ~8 ms of an ~80 ms
  # collection; the cache directory is ours, and the pid plus a counter keeps
  # concurrent refreshes apart without asking anyone.
  _dp_cache_dir || return 1
  # NOTE: host names kept in a parallel array. Iterating ${(k)hosts} twice and
  # trusting the order to match is the kind of assumption that holds until it
  # does not, and the failure would pin one host's outage on another.
  local -a tmps hnames
  local t
  local -i n=0
  for host in ${(k)hosts}; do
    (( n++ ))
    t=$DP_CACHE_DIR/state.${sysparams[pid]:-$$}.$n
    tmps+=("$t"); hnames+=("$host")
    _dp_probe_one "$host" "$t" "$probe" &
  done
  wait
  # NOTE: a host that did not answer is NOT a host with no containers. Without
  # the sentinel both look like an empty file, and every workspace on that host
  # was then reported as having lost its container — a dropped ssh connection
  # was indistinguishable from a wiped docker host. Failed hosts are announced
  # so the snapshot can say "unknown" instead of lying.
  local -i i
  for (( i = 1; i <= $#tmps; i++ )); do
    if grep -q '^#ok$' "$tmps[$i]" 2>/dev/null; then
      grep -v '^#ok$' "$tmps[$i]" 2>/dev/null
    else
      print -r -- "!down	$hnames[$i]"
    fi
  done
  (( $#tmps )) && rm -f "${tmps[@]}"
}

# One table with every fact the pickers, the preview and the doctor need, built
# in one pass and written to a file.
# NOTE: sorted by the full timestamp but showing only the date — otherwise
# workspaces touched on the same day would come out in arbitrary order.
# NOTE: a file and not a variable, because fzf runs --preview as its OWN process
# for every move of the cursor. Recomputing there would mean an ssh round trip
# per keystroke; reading a prepared line is free.
# Columns: id state provider host uid image lastused source profile repo
_dp_snapshot() {
  emulate -L zsh
  local out=${1:-/dev/stdout}
  local -A state_of image_of seen prof_of repo_of sec_of
  local id uid prov host st im line src date want
  local -a meta

  # NOTE: the metadata is read ONCE and kept, not re-read per section — it is
  # the same jq call the state collection already pays for.
  meta=(${(f)"$(_dp_meta)"})
  local -A host_down
  while IFS=$'\t' read -r uid st im sec; do
    # A host that never answered announces itself; its workspaces then get
    # "unknown" rather than "no container", which is a different problem with a
    # different fix and used to be indistinguishable.
    [[ $uid == '!down' ]] && { host_down[$st]=1; continue }
    [[ -n $uid ]] && { state_of[$uid]=$st; image_of[$uid]=$im; sec_of[$uid]=$sec }
  done < <(_dp_state)
  for line in $DP_CATALOG; do
    prof_of[${${(s:|:)line}[3]}]=${${(s:|:)line}[1]}
    repo_of[${${(s:|:)line}[3]}]=${${(s:|:)line}[2]}
  done

  {
    for line in $meta; do
      IFS=$'\t' read -r id uid prov host date src im <<< "$line"
      seen[$id]=1
      # NOTE: never an empty column. The readers split with ${(ps:\t:)}, which
      # DROPS empty fields and silently shifts every later column left — the
      # preview showed the profile under "repository" until this was a dash.
      # Column 11 is the secrets pair, "claude age": 11 both, 10 token only,
      # "--" nothing to ask because the container is not running.
      # absent = the host said there is no such container; unknown = the host
      # said nothing at all. Only the first is a reason to recreate anything.
      local st_now=${state_of[$uid]}
      if [[ -z $st_now ]]; then
        [[ -n ${host_down[${host:-LOCAL}]} || -n ${host_down[LOCAL]} && $host == - ]] \
          && st_now=unknown || st_now=absent
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$id" "$st_now" "${prov:--}" "${host:--}" \
        "${uid:--}" "${image_of[$uid]:--}" "${date[1,10]:--}" "${src:--}" \
        "${prof_of[$id]:--}" "${repo_of[$id]:-$src}" "${sec_of[$uid]:---}"
    done
    for line in $DP_CATALOG; do
      id=${${(s:|:)line}[3]}
      (( ${+seen[$id]} )) && continue
      printf '%s\tnew\t-\t-\t-\t-\t-\t%s\t%s\t%s\t--\n' \
        "$id" "${${(s:|:)line}[2]}" "${${(s:|:)line}[1]}" "${${(s:|:)line}[2]}"
    done
  } > $out
}

# Rebuild the cached snapshot.
# NOTE: one mv and not a `>` into the live file. mv within a directory is
# atomic, so a picker or a preview reading the cache at that moment gets the old
# table or the new one and never half of each — which is the whole reason
# several refreshes may run at once without a lock.
_dp_snapshot_refresh() {
  emulate -L zsh
  _dp_cache_dir || return 1
  local part=$DP_SNAPSHOT.${sysparams[pid]:-$$}
  local t0=$EPOCHREALTIME
  local -i ms
  if ! _dp_snapshot "$part"; then
    (( ms = (EPOCHREALTIME - t0) * 1000 ))
    _dp_log snapshot $ms 1 reason=collect-failed
    rm -f -- $part
    return 1
  fi
  # NOTE: an empty result is never an answer worth keeping. jq off PATH, an
  # unreadable ~/.devpod, every host down — the collection returns nothing and
  # would blank the cache, and because the refresh usually runs in the
  # background that happens silently. The old code collected on every run and
  # healed itself next time; this one would stay broken.
  if [[ ! -s $part ]]; then
    (( ms = (EPOCHREALTIME - t0) * 1000 ))
    _dp_log snapshot $ms 1 reason=empty
    rm -f -- $part
    return 1
  fi
  local -i rows=${#${(f)"$(< $part)"}}
  (( ms = (EPOCHREALTIME - t0) * 1000 ))
  _dp_log snapshot $ms 0 "rows=$rows"
  mv -f -- $part $DP_SNAPSHOT
}

# Make sure $DP_SNAPSHOT is worth reading, rebuilding it only when it is missing
# or older than $1 seconds. 0 — the cache was good, 2 — it was just rebuilt, so
# the caller has nothing left to prefetch.
_dp_snapshot_use() {
  emulate -L zsh
  _dp_cache_dir || return 1
  local -i age=${1:-$DP_CACHE_TTL}
  local -a good=( $DP_SNAPSHOT(N.ms-$age) )
  (( $#good )) && [[ -s $DP_SNAPSHOT ]] && return 0
  _dp_snapshot_refresh || return 1
  return 2
}

# Collect for the NEXT run — and, when a picker is waiting, for the redraw it is
# about to do: with an argument the fresh rows land in that file, which is what
# fzf's reload-sync is blocking on.
# NOTE: >/dev/null is not tidiness. A background job inherits the caller's
# stdout, and `x=$(_dp_rows)` waits for EVERY writer of that pipe to close — so
# without this the refresh is paid for synchronously after all, just less
# visibly, and `dp` sits there for as long as the ssh takes.
# NOTE: no lock. Two refreshes racing cost one extra ssh and nothing else: each
# writes its own file and lands it with a single mv.
_dp_refresh_async() {
  emulate -L zsh
  # NOTE: no_monitor, or the job number is printed on top of the picker.
  setopt local_options no_monitor
  local rows=$1
  if [[ -n $rows ]]; then
    { _dp_snapshot_refresh \
        && _dp_rows "$DP_SNAPSHOT" > $rows.part \
        && [[ -s $rows.part ]] \
        && mv -f -- $rows.part $rows } >/dev/null 2>&1 &!
  else
    # NOTE: a floor, so that `dp ls` in a loop does not start a refresh per
    # iteration. A picker is exempt — it is waiting for the rows file and a skip
    # would leave it on the fallback.
    local -a hot=( $DP_SNAPSHOT(N.ms-${DP_REFRESH_FLOOR:-3}) )
    (( $#hot )) && return 0
    _dp_snapshot_refresh >/dev/null 2>&1 &!
  fi
}

# The list behind every picker, rendered from a snapshot. Keyed by id, so an
# instance that exists without a catalog line still shows up — which is the
# point, since `dp new` invents ids the catalog never knew.
_dp_rows() {
  emulate -L zsh
  local snap=$1
  if [[ -z $snap ]]; then
    # The cache, rebuilt only if it is missing or too old to trust; when it was
    # good enough the collection still happens, just behind us, so the next
    # caller finds a warm file.
    local rc
    _dp_snapshot_use
    rc=$?
    (( rc == 1 )) && return 1
    snap=$DP_SNAPSHOT
    (( rc == 0 )) && _dp_refresh_async
  fi
  local -a lines=(${(f)"$(< $snap)"})
  (( $#lines )) || return 0

  local -i w=0
  local line
  local -a c
  for line in $lines; do
    c=(${(ps:\t:)line}); (( ${#c[1]} > w )) && w=${#c[1]}
  done

  # NOTE: no "last used" column. The rows are already SORTED by it, so the date
  # repeated an order the eye can see, and the preview shows it for the one row
  # that is actually being looked at.
  # NOTE: the provider is set in faint (SGR 2) on top of the muted colour. It
  # matters only when workspaces live on different hosts, which is rare — this
  # keeps it readable when looked for and out of the way when not.
  # A running job outranks the snapshot: the snapshot says what the container
  # was when it was last polled, the job says what is being done to it now.
  local jobs=$DP_CACHE_DIR/jobs
  local mark colour job jverb jstate
  for line in $lines; do
    c=(${(ps:\t:)line})
    job=
    [[ -r $jobs/$c[1].status ]] && job=$(< $jobs/$c[1].status)
    if [[ -n $job ]]; then
      jverb=${job%%$'\t'*}; jstate=${job##*$'\t'}
      case $jstate in
        # NOTE: only the running form is inflected. "recreating: partial" ran
        # two columns past the field width and pushed the provider out of line
        # — the outcome states keep the bare verb so every row stays aligned.
        # NOTE: no spinner animation. fzf redraws only when the list reloads,
        # and reloading on a timer to turn a character would fight the picker
        # for the terminal every 100ms.
        running) case $jverb in
                   stop)     mark='● stopping…' ;;
                   recreate) mark='● recreating…' ;;
                   *)        mark="● ${jverb}…" ;;
                 esac
                 colour=$_DP_YELLOW ;;
        partial) mark="⚠ ${jverb} partial"; colour=$_DP_YELLOW ;;
        *)       mark="✗ ${jverb} failed";  colour=$_DP_RED ;;
      esac
    else
      case $c[2] in
        running) mark='● running';      colour=$_DP_GREEN ;;
        exited)  mark='○ stopped';      colour=$_DP_BLUE ;;
        new)     mark='· not created';  colour=$_DP_MUTED ;;
        unknown) mark='? host silent';   colour=$_DP_YELLOW ;;
        *)       mark='⚠ no container'; colour=$_DP_YELLOW ;;
      esac
    fi
    printf "%-${w}s  %s%-18s%s  %s%s%s%s\n" \
      "$c[1]" "$colour" "$mark" "$_DP_OFF" \
      "$_DP_FAINT$_DP_MUTED" "${c[3]/#-/—}" "$_DP_OFF"
  done
}

# Shared picker engine: padded rows on stdin, the first column of each chosen
# row on stdout. -m enables multi-select. Factored out because the pickers
# differ only in their data and labels, and the no-fzf fallback would otherwise
# exist in three copies.
_dp_choose() {
  emulate -L zsh
  local multi=0 tmux_footer=0
  while [[ $1 == -* ]]; do
    case $1 in
      -m) multi=1 ;;
      # The chooser `ds` opens: it gets the keys spelled out at the bottom and
      # the tmux flag, because where you land is decided here and nowhere else.
      -t) tmux_footer=1 ;;
    esac
    shift
  done
  local prompt=$1 header=$2
  local -a rows
  rows=(${(f)"$(cat)"})
  rows=(${rows:#})
  (( ${#rows} )) || return 1

  if (( $+commands[fzf] )); then
    local -a args
    # NOTE: no --height and no --reverse here. Both already come from
    # FZF_DEFAULT_OPTS, and repeating them locally pinned this picker to a fixed
    # 40% of the terminal while the global setting sizes the window to the list.
    # NOTE: --ansi because the rows carry their own colour, and --accept-nth=1
    # because fzf then prints the id itself — with the escape sequences removed,
    # which is what makes colouring the rows safe at all. Without it the codes
    # would travel on inside a workspace id.
    # NOTE: no --delimiter any more. The default is a run of whitespace, which
    # is exactly what padded columns need; a tab delimiter would now see the
    # whole line as one field and --nth=1 would match against the date too.
    args=(--ansi --nth=1 --accept-nth=1 --prompt="$prompt" --header="$header")
    (( multi )) && args+=(--multi --bind 'ctrl-a:select-all,ctrl-d:deselect-all')
    if (( tmux_footer )); then
      local fdot=${DOTFILES_DIR:-$HOME/.dotfiles}
      args+=(--footer="$($fdot/tools/devpod/footer.zsh $DP_TMUX_FLAG simple)"
             --footer-border=top
             --bind="ctrl-t:execute-silent($fdot/tools/devpod/toggle-tmux.sh $DP_TMUX_FLAG)+transform-footer($fdot/tools/devpod/footer.zsh $DP_TMUX_FLAG simple)")
    fi
    print -rl -- $rows | fzf "${args[@]}"
    return ${pipestatus[2]}
  fi

  # No fzf: a numbered list. `select` cannot mark several entries, so
  # multi-select reads the numbers as one line instead.
  # NOTE: the list goes to the terminal — stdout carries the answer and is
  # usually being captured.
  # NOTE: extended_glob for the `##` below. The rows carry SGR sequences meant
  # for fzf and nothing here understands them; without the option the pattern
  # stays a literal, matches nothing, and the escapes reach the terminal raw.
  setopt local_options extended_glob
  local -a plain=(${rows//$'\e'\[[0-9;]##m/})
  local -a names=(${plain%% *})
  local i
  for (( i = 1; i <= ${#names}; i++ )); do
    print -r -- "  $i) ${plain[i]}" > /dev/tty
  done
  # NOTE: read from the terminal, not stdin — `cat` above has already drained
  # stdin, so a plain `read` would see EOF and return nothing.
  local reply n
  read "reply?$prompt" < /dev/tty || return 1
  [[ -z $reply ]] && return 1
  (( multi )) || reply=${reply%% *}
  for n in ${=reply}; do
    [[ $n == <-> ]] && (( n >= 1 && n <= ${#names} )) && print -r -- "${names[n]}"
  done
}

_dp_pick() {
  emulate -L zsh
  local -a rows
  rows=(${(f)"$(_dp_rows)"})
  (( ${#rows} )) || { print -u2 "no workspaces found"; return 1; }
  local hdr='most recent first'
  [[ $1 == -m ]] && hdr='Tab — mark, Ctrl-A — all; most recent first'
  print -rl -- $rows | _dp_choose ${1:+-m} -t 'workspace> ' "$hdr"
}

# Image picker for kvt-up. Not derived from the catalog on purpose: the image is
# chosen once and applies to every workspace of that run.
_dp_pick_image() {
  emulate -L zsh
  printf '%-8s %s%s%s\n' \
    devops "$_DP_MUTED" 'IaC/K8s: terraform, ansible, kubectl, helm, talos' "$_DP_OFF" \
    core   "$_DP_MUTED" 'editor, shell, git, CI' "$_DP_OFF" \
    | _dp_choose 'image> ' 'image profile for the whole run'
}

# NOTE: the entries are filtered by name because there are over a hundred of
# them and only a couple of keys; DPKEY_ITEM is the starting query, so the usual
# key is on top while the list stays complete. Entry contents are not read here
# — the list is built from names and `rbw get` runs only for the chosen one.
_dp_pick_key() {
  emulate -L zsh
  local -a items
  items=(${(f)"$(rbw list 2>/dev/null | grep -i -- "$DPKEY_FILTER")"})
  (( ${#items} )) || {
    print -u2 "dpkey: no Bitwarden entry matched the «$DPKEY_FILTER» filter"
    print -u2 "       DPKEY_FILTER='' shows all of them"
    return 1
  }

  if (( $+commands[fzf] )); then
    print -rl -- $items \
      | fzf --prompt='age-key> ' \
            --query="$DPKEY_ITEM" \
            --header='private key; Ctrl-U — clear the query to see all'
  else
    local choice
    select choice in $items; do
      [[ -n $choice ]] && { print -r -- "$choice"; return 0; }
    done
    return 1
  fi
}

# Delivering the zone key into a container. The key survives until the workspace
# is recreated, which is why this is its own command rather than a tail of `dp`.
dpkey() {
  emulate -L zsh
  setopt local_options pipefail

  # NOTE: assignment separate from `local` — `local id=$(...)` always returns 0
  # and would swallow a failure from _dp_pick.
  local id
  if (( $# )); then
    id=$1
  else
    id=$(_dp_pick) || return 1
  fi
  [[ -z $id ]] && { print -u2 "dpkey: no workspace selected"; return 1; }

  local item
  if (( $# > 1 )); then
    item=$2
  else
    item=$(_dp_pick_key) || return 1
  fi
  [[ -z $item ]] && { print -u2 "dpkey: no key selected"; return 1; }

  local key
  if [[ -n $DPKEY_FIELD ]]; then
    key=$(rbw get -f "$DPKEY_FIELD" "$item") || return 1
  else
    key=$(rbw get "$item") || return 1
  fi

  # NOTE: without this check an empty output or a public key would arrive in the
  # container as a plausible-looking file and cost a long debugging session
  # later.
  if [[ $key != *AGE-SECRET-KEY-* ]]; then
    print -u2 "dpkey: entry «$item» holds no private age key."
    print -u2 "       A private one (AGE-SECRET-KEY-...) is required, not a public age1..."
    return 1
  fi

  local errfile
  errfile=$(mktemp) || return 1
  print -r -- "$key" \
    | devpod ssh "$id" --command \
        'install -D -m600 /dev/stdin "$HOME/.config/sops/age/keys.txt"' 2>"$errfile" >/dev/null
  local rc=$?
  unset key

  if (( rc != 0 )); then
    print -u2 "dpkey: key not delivered to $id"
    # NOTE: devpod prints "Error tunneling to container" on successful runs too
    # — its own noise, shown only when something actually failed.
    grep -v 'Error tunneling to container' "$errfile" >&2
  else
    print "dpkey: zone key delivered to $id"
  fi
  rm -f "$errfile"
  return $rc
}

# Writes stdin to a 0600 file inside the workspace.
# NOTE: $dest is expanded on the REMOTE side, so pass it single-quoted.
_dp_put_file() {
  emulate -L zsh
  local id=$1 dest=$2
  local errfile rc
  errfile=$(mktemp) || return 1
  devpod ssh "$id" --command "install -D -m600 /dev/stdin \"$dest\"" \
    2>"$errfile" >/dev/null
  rc=$?
  (( rc != 0 )) && grep -v 'Error tunneling to container' "$errfile" >&2
  rm -f "$errfile"
  return $rc
}

# Claude Code auth for the container: the long-lived OAuth token from Bitwarden,
# picked up by .zshrc as CLAUDE_CODE_OAUTH_TOKEN.
# NOTE: deliberately a file and not `devpod up --workspace-env` — an env var is
# visible in `docker inspect` to anyone with root on the docker host.
: ${DPCLAUDE_ITEM:=claude-code-oauth-token}

_dp_put_claude() {
  emulate -L zsh
  local id=$1 token
  token=$(rbw get "$DPCLAUDE_ITEM" 2>/dev/null) || {
    print -u2 "claude: entry «$DPCLAUDE_ITEM» cannot be read from Bitwarden"
    return 1
  }
  # NOTE: anything else would land as a plausible-looking file and fail much
  # later, inside the container, as an auth error with no obvious cause.
  if [[ $token != sk-ant-oat* ]]; then
    print -u2 "claude: «$DPCLAUDE_ITEM» is not an OAuth token (sk-ant-oat... expected)"
    return 1
  fi
  print -r -- "$token" | _dp_put_file "$id" '$HOME/.config/claude/token'
  local rc=$?
  unset token
  if (( rc != 0 )); then
    print -u2 "claude: token not delivered to $id"
    return $rc
  fi

  # NOTE: onboarding is a separate gate from authentication. With a working
  # token the CLI still opens its first-run setup and offers a subscription
  # login, which looks exactly like the token being ignored — while `claude -p`
  # answers fine at the same moment.
  devpod ssh "$id" --command \
    'f=$HOME/.claude.json; [ -f "$f" ] || printf "{}" > "$f";
     t=$(mktemp) && jq ".hasCompletedOnboarding = true" "$f" > "$t" && mv "$t" "$f"' \
    2>/dev/null >/dev/null \
    || print -u2 "claude: onboarding in $id not disabled — the CLI will ask to sign in"

  print "claude: token delivered to $id"
  return 0
}

# The state the last collection saw for one workspace: running, exited, new,
# or empty when it is not in the snapshot at all.
_dp_snap_state() {
  emulate -L zsh
  [[ -s $DP_SNAPSHOT ]] || return 1
  awk -F'\t' -v i="$1" '$1==i{print $2; exit}' $DP_SNAPSHOT
}

# One field out of a workspace's own record. The image pinned at creation and
# the provider it belongs to both live here, and nowhere else: `devpod list`
# reports neither.
_dp_ws_field() {
  emulate -L zsh
  local f=${HOME}/.devpod/contexts/default/workspaces/$1/workspace.json
  [[ -r $f ]] || return 1
  jq -r "$2 // empty" "$f" 2>/dev/null
}

# The SSH host behind a provider, empty when it builds locally. `docker pull`
# needs it: the image is set by a flag, so devcontainer.json's initializeCommand
# never runs and nothing else refreshes a floating tag on the build host.
# NOTE: a non-zero exit means the lookup itself failed and the answer is unknown
# — the caller must not read that as "local", or it pulls onto the wrong machine
# and leaves the real build host on its stale tag.
_dp_provider_host() {
  emulate -L zsh
  local out
  out=$(devpod provider options "$1" --output json 2>/dev/null) || return 1
  print -r -- "$out" | jq -r '.HOST.value // empty' 2>/dev/null || return 1
}

# NOTE: names only. Showing each provider's host would mean one `devpod provider
# options` call per row — ~1.6s each, so the picker would sit for five seconds
# before drawing. The chosen one is resolved afterwards, in a single call.
_dp_pick_provider() {
  emulate -L zsh
  local -a names
  names=(${(f)"$(devpod provider list --output json 2>/dev/null | jq -r 'keys[]')"})
  names=(${names:#})
  (( ${#names} )) || { print -u2 "no providers configured"; return 1 }
  print -rl -- $names | _dp_choose 'provider> ' 'where to bring containers up'
}

# ── dp: one verb-driven entry point ───────────────────────────────────────────
#
# The pickers above are the parts; this is the surface. `dp` with no verb opens
# the list and lets a key decide what happens to the selection, which is what
# makes `dp new` possible at all: the name of a brand new instance is simply
# what was typed into the search line.

# The catalog line for an id, or nothing.
_dp_entry() {
  emulate -L zsh
  local e
  for e in $DP_CATALOG; do
    [[ ${${(s:|:)e}[3]} == $1 ]] && { print -r -- "$e"; return 0 }
  done
  return 1
}

# NOTE: docker does NOT re-pull a floating tag it already has locally, and the
# build host is not this machine — without this a workspace comes up on whatever
# was pulled first, which once cost four minutes of rebuilding terraform.
_dp_pull() {
  emulate -L zsh
  local provider=$1 tag=$2 host
  if ! host=$(_dp_provider_host "$provider"); then
    print -u2 "⚠ provider host for $provider unknown — pull skipped"
    return 0
  fi
  local t0=$EPOCHREALTIME
  local -i rc=0 ms
  if [[ -n $host ]]; then
    ssh -o BatchMode=yes -o ConnectTimeout=5 -T "$host" \
        "docker pull ${DP_IMAGE}:${tag}" >/dev/null 2>&1
  else
    docker pull "${DP_IMAGE}:${tag}" >/dev/null 2>&1
  fi
  rc=$?
  (( ms = (EPOCHREALTIME - t0) * 1000 ))
  # A pull that finds nothing new still costs a round trip to the registry;
  # telling that apart from a real six-gigabyte transfer is what the duration is
  # for, since docker says nothing useful about which happened.
  _dp_log pull $ms $(( rc == 0 ? 0 : 1 )) "tag=$tag" "host=${host:-local}" "rc=$rc"
  (( rc == 0 )) || print -u2 "⚠ pull ${DP_IMAGE}:${tag} failed — will run on the local tag"
}

# One workspace up. Every caller goes through here so the flags stay in one
# place: id, image by profile, and the env file.
_dp_up_one() {
  emulate -L zsh
  local id=$1 repo=$2 profile=${3:-core} provider=${4:-$DP_PROVIDER}
  local -a args=("$repo" --id "$id" --devcontainer-image "${DP_IMAGE}:${profile}")
  [[ -n $provider ]] && args+=(--provider "$provider")
  # NOTE: no --workspace-env-file. It put the nine work variables into
  # /etc/envfile.json inside the container with mode 644; they are delivered
  # as a 0600 file by `dp secrets` instead. See _dp_put_workenv.
  local t0=$EPOCHREALTIME
  devpod up "${args[@]}"
  local -i rc=$? ms
  (( ms = (EPOCHREALTIME - t0) * 1000 ))
  _dp_log up $ms $(( rc == 0 ? 0 : 1 )) "id=$id" "profile=$profile" "rc=$rc"
  return $rc
}

# Everything the picker needs in one place: snapshot, rows, keys. Prints
# "<key>\n<query>\n<id>..." the way fzf does, so the caller can dispatch.
_dp_pick_action() {
  emulate -L zsh
  setopt local_options no_monitor
  _dp_cache_dir || return 1
  # Once per opening — the one place cheap enough to check the log's size.
  _dp_log_roll
  local _t0=$EPOCHREALTIME
  local -i _ms
  local dot=${DOTFILES_DIR:-$HOME/.dotfiles}
  # NOTE: fzf renders ANSI inside --footer (checked, it passes the codes
  # through), so the key and what it does can be told apart at a glance. Read as
  # one grey run they blurred into "Ctrl-R recreate Ctrl-D delete".
  # The footer is generated, not written out here: it carries the tmux flag's
  # state in colour, and Ctrl-T has to be able to redraw it without reopening
  # the picker.
  local _dp_footer=$($dot/tools/devpod/footer.zsh $DP_TMUX_FLAG)
  (( _DP_RUN++ ))
  local tag=${sysparams[pid]:-$$}.$_DP_RUN
  local base=$DP_CACHE_DIR/rows.$tag fresh=$DP_CACHE_DIR/rows.$tag.fresh
  # Row files and half-written snapshots belong to one run in flight, so
  # anything this old is left over from a run that was killed — closing the
  # terminal on an open picker takes its background refresh down with it.
  rm -f -- $DP_CACHE_DIR/rows.*(N.mm+5) $DP_SNAPSHOT.*(N.mm+5) \
           $base $fresh $fresh.part
  # NOTE: state files are swept on a much longer leash. Their writer holds the
  # fd open for as long as its ssh takes, and unlinking one underneath it does
  # NOT fail loudly — the collection just comes back short and every container
  # on that host is recorded as missing.
  rm -f -- $DP_CACHE_DIR/state.*(N.mm+60)

  # Only the very first run has nothing at all to draw. -s and not -f: an empty
  # file passes -f, renders no rows, and there is no path from here back to a
  # collection — `dp` would report "no workspaces" forever.
  # Whether this opening waited for a collection is the difference between 40ms
  # and a second and a half, so the row says which of the two it was.
  local _cached=yes
  [[ -s $DP_SNAPSHOT ]] || { _cached=no; _dp_snapshot_refresh || return 1 }
  _dp_rows "$DP_SNAPSHOT" > $base
  if [[ ! -s $base ]]; then
    rm -f -- $base
    print -u2 "dp: no workspaces and an empty catalog"
    return 1
  fi
  # The states on screen are as old as the cache; this is what corrects them.
  _dp_refresh_async "$fresh"

  # NOTE: reload-sync and not reload — reload blanks the list while its command
  # runs, which is exactly the empty picker this whole arrangement exists to
  # avoid. reload-sync keeps the cached rows on screen, and they stay usable
  # while the refresh is in flight.
  # NOTE: unbind(load) first. reload-sync finishes by loading a list, which
  # fires `load` again — without the unbind the picker refreshes itself forever.
  # NOTE: --id-nth=1 makes the id the item's identity, so the marks made with
  # Tab survive the swap instead of being cleared by it. Deliberately without
  # --track: tracking blocks the query line until it has found the item again,
  # and the whole point here is that the picker stays live.
  # NOTE: --info carries a PREFIX of one space, and that space is the point: a
  # prefix replaces fzf's spinner. This picker always has a reload command in
  # flight — the wait for the next row update — so the spinner turned forever
  # and told nobody anything. What a job is doing is written on its own row.
  # NOTE: recreate and delete do not act on the keypress. They arm a yes/no
  # that the next Enter answers, and only the "yes" row runs anything — pressing
  # the key twice, or leaning on it, changes nothing. Stop is deliberately not
  # among them: it is undone by opening the workspace again.
  # NOTE: stop and recreate are NOT in --expect any more. Leaving the picker to
  # run them meant reopening it afterwards to do the next one, and watching a
  # bare terminal in between; they run detached now and report back through the
  # row they belong to.
  local jobs=$DP_CACHE_DIR/jobs
  mkdir -p -- $jobs
  local runner=$dot/tools/devpod/run-job.zsh
  # The confirmation's own state: which verb is armed and what it would act on.
  # Cleared on every opening — an Esc out of an armed picker must not leave a
  # recreate waiting to be confirmed by the next unrelated Enter.
  local cstate=$DP_CACHE_DIR/confirm.$tag ctargets=$DP_CACHE_DIR/targets.$tag
  rm -f -- $cstate $ctargets $DP_CACHE_DIR/confirm.*(N.mm+60) $DP_CACHE_DIR/targets.*(N.mm+60)
  local confirm=$dot/tools/devpod/confirm.zsh
  local -i _rows=${#${(f)"$(< $base)"}}
  (( _ms = (EPOCHREALTIME - _t0) * 1000 ))
  _dp_log picker $_ms 0 "cached=$_cached" "rows=$_rows"
  local _t_open=$EPOCHREALTIME
  local out
  out=$(fzf --ansi --nth=1 --accept-nth=1 --multi --id-nth=1 \
      --print-query --expect=ctrl-n,ctrl-s \
      --prompt='workspace> ' \
      --info='inline-right: ' \
      --bind="load:reload-sync($dot/tools/devpod/await-rows.zsh $fresh $base)" \
      --bind="ctrl-x:execute-silent($runner stop $jobs $fresh {+1})" \
      --bind="ctrl-r:transform($confirm arm recreate $cstate $ctargets {+1})" \
      --bind="ctrl-d:transform($confirm arm delete $cstate $ctargets {+1})" \
      --bind="enter:transform($confirm run $cstate $ctargets {q} $base $jobs $fresh $runner $DP_TMUX_FLAG)" \
      --bind="ctrl-l:execute($dot/tools/devpod/show-log.zsh $jobs {1})" \
      --bind="ctrl-t:execute-silent($dot/tools/devpod/toggle-tmux.sh $DP_TMUX_FLAG)+transform-footer($dot/tools/devpod/footer.zsh $DP_TMUX_FLAG)" \
      --preview="$dot/tools/devpod/preview.zsh {1} $DP_SNAPSHOT $jobs" \
      --preview-window='right,46%,border-left' \
      --footer="$_dp_footer" \
      --footer-border=top < $base)
  local rc=$?
  (( _ms = (EPOCHREALTIME - _t_open) * 1000 ))
  _dp_log picker-close $_ms $(( rc == 0 ? 0 : 1 )) "rc=$rc"
  rm -f -- $base $fresh $fresh.part
  # NOTE: rc 130 is a deliberate Esc, rc 1 with --print-query still carries the
  # query — that is exactly the "nothing matched, make it" case.
  (( rc == 130 )) && return 1
  print -r -- "$out"
}

# dp new — the reason this exists. devpod has always been able to run several
# workspaces off one repository (`--id`); what was missing was somewhere to say
# the name. Here it is whatever was typed into the search line.
_dp_new() {
  emulate -L zsh
  local id=$1 repo=$2 profile=$3
  if [[ -z $id ]]; then
    print -u2 "dp new: a name for the new workspace is required"
    return 1
  fi
  if devpod list --output json 2>/dev/null | jq -e --arg i "$id" \
       'map(select(.id == $i)) | length > 0' >/dev/null; then
    print -u2 "dp new: workspace «$id» already exists — dp in $id"
    return 1
  fi
  if [[ -z $repo ]]; then
    # Which repository the new instance comes from: pick it from the catalog.
    local -a rows
    local e
    for e in $DP_CATALOG; do
      rows+=("$(printf '%-26s %s%s%s' "${${(s:|:)e}[3]}" \
                 "$_DP_MUTED" "${${(s:|:)e}[1]}" "$_DP_OFF")")
    done
    (( $#rows )) || { print -u2 "dp new: catalog is empty, pass the repository as the second argument"; return 1 }
    local base
    base=$(print -rl -- $rows | _dp_choose 'from which repository> ' \
             "new workspace «$id»") || return 1
    [[ -z $base ]] && return 1
    e=$(_dp_entry "$base") || return 1
    repo=${${(s:|:)e}[2]}; profile=${${(s:|:)e}[1]}
  fi
  [[ -z $profile ]] && profile=core
  print "▲ $id ← $repo ($profile)"
  _dp_pull "${DP_PROVIDER}" "$profile"
  # NOTE: a failed `devpod up` does NOT mean nothing happened. Seen for real:
  # provisioning finished, then the agent connection dropped with "run agent
  # command: EOF" — and the workspace was left running as root with no secrets,
  # because remoteUser is applied late and the delivery below never ran. Saying
  # so is the difference between a two-command fix and an afternoon.
  if ! _dp_up_one "$id" "$repo" "$profile"; then
    print -u2 "dp new: «$id» did not come up fully. The workspace may still exist —" \
              "check «dp doctor $id» and fix it with «dp recreate $id»."
    return 1
  fi
  # NOTE: every registered secret by name, NOT the bare call. Without names
  # _dp_secrets opens the picker and waits — which turns an automatic restore
  # after a rebuild into a command that hangs forever when nobody is looking.
  _dp_secrets "$id" ${DP_SECRETS%%\|*}
}

# Deleting, as a function so it can run detached like the others and be logged
# the same way. Reached only through the picker's confirmation.
_dp_delete() {
  emulate -L zsh
  local id
  local t0
  local -i rc ms
  for id in "$@"; do
    [[ -z $id ]] && continue
    print "✗ $id"
    t0=$EPOCHREALTIME
    rc=0
    devpod delete "$id" || rc=$?
    (( ms = (EPOCHREALTIME - t0) * 1000 ))
    _dp_log delete $ms $(( rc == 0 ? 0 : 1 )) "id=$id" "rc=$rc"
  done
}

# Rebuilding a workspace that already exists. Deliberately NOT routed through
# the catalog: an instance made by `dp new` is never in it, and that is the whole
# point of `dp new` — the first version of this only handled catalog entries and
# silently did nothing for exactly the workspaces it was meant to serve.
# devpod already stores the source and the image, so id plus --recreate is
# enough; the image is passed again because losing that override is what dropped
# a container to root once already.
# Stopping is the cheap half of recreate: the container goes down, its home and
# everything in it stays. `ds` brings it back up on the next entry.
_dp_stop() {
  emulate -L zsh
  local id state
  for id in "$@"; do
    [[ -z $id ]] && continue
    # NOTE: only `running` is skipped-past. An unknown state means the host
    # never answered, and refusing to act on that would leave the one case
    # where stopping is most likely the right thing with no way to do it.
    # NOTE: only a FRESH snapshot may talk us out of stopping something. The
    # cache is minutes old at times, and acting on it skipped a container that
    # had been started since — reported "already stopped" while it kept running.
    # A stop against something already down costs about a second and is
    # harmless; not stopping what should be stopped is not.
    local -a fresh_snap=( $DP_SNAPSHOT(Nms-60) )
    state=
    (( $#fresh_snap )) && state=$(_dp_snap_state "$id")
    if [[ $state == exited || $state == new ]]; then
      print "■ $id is already stopped"
      _dp_log stop 0 0 "id=$id" skipped=already-stopped
      continue
    fi
    print "■ $id"
    local t0=$EPOCHREALTIME
    local -i rc=0 ms
    devpod stop "$id" || { rc=$?; print -u2 "⚠ stop $id failed" }
    (( ms = (EPOCHREALTIME - t0) * 1000 ))
    _dp_log stop $ms $(( rc == 0 ? 0 : 1 )) "id=$id" "rc=$rc"
  done
}

_dp_recreate() {
  emulate -L zsh
  local id=$1
  [[ -z $id ]] && return 1
  local _t0=$EPOCHREALTIME
  local -i _ms
  local image=$(_dp_ws_field "$id" .devContainerImage)
  local -a args=("$id" --recreate)
  [[ -n $image ]] && args+=(--devcontainer-image "$image")
  # NOTE: the same stale-tag trap `dp new` guards against, and it bites harder
  # here: docker keeps a floating tag it already holds, so a recreate comes up
  # on whatever the build host pulled first, and provisioning then rebuilds
  # from source everything the old image is missing — terraform is unfree, so
  # cache.nixos.org has no binary for it and the host compiles it itself.
  # Only our own tags: a workspace on a locally built vsc-* image has no
  # registry to pull from.
  if [[ $image == ${DP_IMAGE}:* ]]; then
    local provider=$(_dp_ws_field "$id" .provider.name)
    print "⇣ $image"
    _dp_pull "$provider" "${image##*:}"
  fi
  # NOTE: no --workspace-env-file. It put the nine work variables into
  # /etc/envfile.json inside the container with mode 644; they are delivered
  # as a 0600 file by `dp secrets` instead. See _dp_put_workenv.
  print "↻ $id${image:+ ($image)}"
  local _t_up=$EPOCHREALTIME
  if ! devpod up "${args[@]}"; then
    (( _ms = (EPOCHREALTIME - _t_up) * 1000 ))
    _dp_log up $_ms 1 "id=$id" mode=recreate
    return 1
  fi
  (( _ms = (EPOCHREALTIME - _t_up) * 1000 ))
  _dp_log up $_ms 0 "id=$id" mode=recreate
  # NOTE: the container is new, so its home is new — the secrets went with the
  # old one. This is the gap that cost a session before it became a verb.
  # NOTE: every registered secret by name, NOT the bare call. Without names
  # _dp_secrets opens the picker and waits — which turns an automatic restore
  # after a rebuild into a command that hangs forever when nobody is looking.
  _dp_secrets "$id" ${DP_SECRETS%%\|*}
  local -i rc=$?
  (( _ms = (EPOCHREALTIME - _t0) * 1000 ))
  # End to end: pull, up, and the secret delivery after it. The parts have rows
  # of their own; this is the number a person actually waits through.
  _dp_log recreate $_ms $(( rc == 0 ? 0 : 1 )) "id=$id" "rc=$rc"
  return $rc
}

# What a workspace can be handed, and what puts it there. One line per secret:
#   name|description|function|position in the probe-host.sh report
# The delivery function takes the workspace id and is free to ask its own
# questions — dpkey opens the Bitwarden picker when no entry is pinned. Adding a
# third secret means adding a line here and a test in probe-host.sh, nothing
# else: the picker, the progress output and the preview all read this list.
typeset -ga DP_SECRETS=(
  "claude|Claude Code token|_dp_put_claude|1"
  "age|zone age key for sops|_dp_put_age|2"
  "env|work env file (jira, gitlab, nomad…)|_dp_put_workenv|3"
)

# Where the work variables live inside a container.
: ${DP_ENV_DEST:='$HOME/.config/dp/work.env'}
: ${DP_ENV_SRC:=$HOME/.dotfiles/.env}

_dp_secret_entry() {
  emulate -L zsh
  local e
  for e in $DP_SECRETS; do
    [[ ${${(s:|:)e}[1]} == $1 ]] && { print -r -- "$e"; return 0 }
  done
  return 1
}

# The work variables, as a file the container's shell reads rather than as
# workspace env.
# NOTE: this replaces `devpod up --workspace-env-file`. That flag looked
# harmless and was not: devpod writes the values into /etc/envfile.json inside
# the container with mode 644, where every process can read them — checked, and
# four of the nine are real secrets. A 0600 file read by ~/.zshrc gives the same
# variables to the same tools while keeping them out of everything else. It also
# restores the whitelist: the env-file route exported all nine to every child
# process, while .zshrc exports only the five that need it.
_dp_put_workenv() {
  emulate -L zsh
  local id=$1
  if [[ ! -r $DP_ENV_SRC ]]; then
    print -u2 "env: $DP_ENV_SRC не читается — нечего доставлять"
    return 1
  fi
  if _dp_put_file "$id" "$DP_ENV_DEST" < $DP_ENV_SRC; then
    print "env: переменные доставлены в $id"
  else
    print -u2 "env: файл не доставлен в $id"
    return 1
  fi
}

# NOTE: a wrapper and not `dpkey` directly, so that pinning an entry in
# DPKEY_AUTO_ITEM stays optional. Without it dpkey asks which key to use, which
# is the interactive behaviour that was missing when this was skipped outright.
_dp_put_age() {
  emulate -L zsh
  if [[ -n $DPKEY_AUTO_ITEM ]]; then
    dpkey "$1" "$DPKEY_AUTO_ITEM"
  elif [[ -n $DP_JOB ]]; then
    # NOTE: which vault entry holds the key is a CHOICE, and a detached job has
    # nobody to ask — dpkey would open a picker onto a terminal that is not
    # there. Exit 2 is the "everything else went in, this one needs you" signal
    # the runner turns into a partial rather than a failure.
    print -u2 "age key needs a choice — dp secrets $1 age (or set DPKEY_AUTO_ITEM)"
    return 2
  else
    dpkey "$1"
  fi
}

# The secrets picker: every known secret with whether it is already in place.
# NOTE: the state comes from the cached snapshot, not from a fresh look inside
# the container — asking would cost a `devpod ssh` before a picker that exists
# to save exactly that kind of wait.
# One row per registered secret, with the state the last collection saw.
# A function of its own because the picker RELOADS these after every delivery —
# that reload is what makes a delivered secret stop saying "missing".
_dp_secret_rows() {
  emulate -L zsh
  local id=$1 sec= e name descr pos mark colour
  [[ -r $DP_SNAPSHOT ]] && \
    sec=$(awk -F'\t' -v i="$id" '$1==i{print $11; exit}' "$DP_SNAPSHOT" 2>/dev/null)
  for e in $DP_SECRETS; do
    name=${${(s:|:)e}[1]}; descr=${${(s:|:)e}[2]}; pos=${${(s:|:)e}[4]}
    case ${sec[$pos]} in
      1) mark='✓ present';  colour=$_DP_GREEN ;;
      0) mark='✗ missing';  colour=$_DP_YELLOW ;;
      *) mark='· unknown';  colour=$_DP_MUTED ;;
    esac
    printf '%-8s %s%-15s%s %s%s%s\n' \
      "$name" "$colour" "$mark" "$_DP_OFF" "$_DP_MUTED" "$descr" "$_DP_OFF"
  done
}

# The secrets picker DELIVERS; it does not report back what to deliver.
#
# It used to return a list of names and let the caller do the work, which meant
# the picker closed on the first Enter and its states were whatever the snapshot
# said when it opened — deliver three secrets and all three still read "missing"
# until something else refreshed. Now Enter delivers the marked ones through
# `execute` (the whole terminal, so the age key can ask which vault entry), then
# the rows reload from a freshly collected snapshot and the states are current.
_dp_secret_pick() {
  emulate -L zsh
  local id=$1
  [[ -n $id ]] || return 1
  (( $+commands[fzf] )) || {
    # No fzf: fall back to the old behaviour — name them on the command line.
    print -u2 "secrets: fzf not found — name them: dp secrets $id ${DP_SECRETS%%\|*}"
    return 1
  }
  local dot=${DOTFILES_DIR:-$HOME/.dotfiles}
  local k=$_DP_BLUE a="${_DP_FAINT}${_DP_MUTED}" o=$_DP_OFF
  _dp_secret_rows "$id" | fzf --ansi --nth=1 --accept-nth=1 --multi \
    --prompt='secrets> ' \
    --header="what to deliver to $id" \
    --footer="${k}Enter${o} ${a}deliver${o}   ${k}Tab${o} ${a}mark several${o}   ${k}Esc${o} ${a}done${o}" \
    --footer-border=top \
    --bind="enter:execute($dot/tools/devpod/put-secret.zsh $id {+1})+reload($dot/tools/devpod/secret-rows.zsh $id)" \
    > /dev/null
  # NOTE: always 0. Esc is how you leave a picker that has already done its
  # work, and fzf calls that 130 — reporting it as failure made `dp secrets`
  # look like it had failed after delivering everything asked of it.
  return 0
}

# dp secrets — the gap that recreating a workspace opened: the files live in the
# container's home and do not survive it, while the delivery was buried inside
# kvt-up and never ran again.
_dp_secrets() {
  emulate -L zsh
  # NOTE: shift, or the id itself stays in "$@" and the loop below reports the
  # workspace as an unknown secret before doing the right thing anyway.
  local id=$1
  if [[ -n $id ]]; then shift; else id=$(_dp_pick) || return 1; fi
  [[ -z $id ]] && return 1
  # Which secrets, asked rather than assumed. Named on the command line they are
  # delivered as given; without names the picker opens and shows what is already
  # in place, so the usual answer — "the one that is missing" — is one Tab away.
  local -a want=("$@")
  # Without names the picker takes over entirely: it delivers, refreshes and
  # stays open until Esc.
  (( $#want )) || { _dp_secret_pick "$id"; return $? }

  # NOTE: every step announces itself BEFORE it runs. Each one opens a `devpod
  # ssh` tunnel and takes seconds, and the old version printed only its verdict
  # at the end — from the outside that is indistinguishable from a hang.
  local rc=0 name entry fn descr
  local -i frc
  print -r -- "${_DP_MUTED}secrets → $id${_DP_OFF}"
  for name in $want; do
    entry=$(_dp_secret_entry "$name") || {
      print -u2 "secrets: «$name» is not in the list (dp secrets $id shows them)"
      rc=1; continue
    }
    descr=${${(s:|:)entry}[2]}; fn=${${(s:|:)entry}[3]}
    print -r -- "${_DP_MUTED}  · ${descr}…${_DP_OFF}"
    local t0=$EPOCHREALTIME
    local -i ms
    $fn "$id"
    frc=$?
    (( ms = (EPOCHREALTIME - t0) * 1000 ))
    # Every delivery opens its own `devpod ssh` tunnel, so this measures that
    # tunnel — the reason restoring three secrets takes as long as it does.
    _dp_log secret $ms $frc "id=$id" "name=$name"
    # NOTE: 2 means "this one needs a person", not "this one broke" — it must
    # not be flattened into 1, and a real failure must not be downgraded by a 2
    # that came after it.
    if (( frc == 0 )); then
      # A hand-delivered secret settles the "partial" a detached recreate left
      # behind: the row would otherwise keep warning about something already
      # done, until the next job happened to overwrite it.
      local _st=$DP_CACHE_DIR/jobs/$id.status
      [[ -r $_st && $(< $_st) == *partial* ]] && rm -f -- $_st
      continue
    fi
    (( frc == 2 && rc == 0 )) && { rc=2; continue }
    (( frc != 2 )) && rc=1
  done
  return $rc
}

# What the doctor asks a live container about itself. One round trip, every
# answer at once, because `devpod ssh` costs seconds and asking twice shows.
: ${_DP_PROBE:='f=.devcontainer/devcontainer.json
if [ -f "$f" ]; then grep -q remoteUser "$f" && dc=own || dc=root; else dc=none; fi
[ -f "$HOME/.config/claude/token" ] && cl=1 || cl=0
[ -f "$HOME/.config/sops/age/keys.txt" ] && ag=1 || ag=0
d=$(cd /workspaces/* 2>/dev/null && git status --porcelain 2>/dev/null | wc -l)
dh=$(git -C "$HOME/dotfiles" rev-parse --short HEAD 2>/dev/null)
dd=$(git -C "$HOME/dotfiles" status --porcelain 2>/dev/null | wc -l)
echo "$dc $cl $ag ${d:-0} ${dh:--} ${dd:-0}"'}

# dp doctor — the difference between how a workspace was meant to come up and
# how it actually did. Every check here is one that has already cost a session.
_dp_doctor() {
  emulate -L zsh
  setopt local_options extended_glob
  local only=$1
  # The doctor talks to the containers themselves, so a stale table would send
  # it to the wrong ones: always collected here and now — and the picker gets a
  # warm cache out of it.
  _dp_snapshot_refresh || return 1

  local line id state image profile
  # NOTE: declared here, not inside the loop. A second `local` for a name that
  # already exists in this scope makes zsh PRINT it — the doctor was spitting
  # `answer='root 1 1 3'` between its own findings.
  local answer dc cl ag dirty dhead ddirty
  local -i findings=0
  local -a c
  while IFS= read -r line; do
    c=(${(ps:\t:)line})
    id=$c[1]; state=$c[2]; image=$c[6]; profile=$c[9]
    [[ -n $only && $id != $only ]] && continue
    [[ $state == new ]] && continue

    # 1. the image the container actually runs, against the one we asked for
    case $image in
      ${DP_IMAGE}:*)
        if [[ $profile != - && $image != ${DP_IMAGE}:$profile ]]; then
          print -r -- "${_DP_YELLOW}⚠${_DP_OFF} $id: image ${image##*:}, catalog promises $profile"
          (( findings++ ))
        fi ;;
      vsc-*|*devpod-*)
        # NOTE: not a lost flag. --devcontainer-image sets the base, but any
        # `features` in the repository's devcontainer.json still make devpod
        # build on top of it — measured: minutes per creation, and the result no
        # longer tracks the registry tag.
        print -r -- "${_DP_YELLOW}⚠${_DP_OFF} $id: image built on top of ours (features in the repository's devcontainer.json)"
        (( findings++ )) ;;
      [0-9a-f](#c12))
        print -r -- "${_DP_YELLOW}⚠${_DP_OFF} $id: untagged image ($image) — the registry has moved on"
        (( findings++ )) ;;
      -) ;;
      *)
        print -r -- "${_DP_YELLOW}⚠${_DP_OFF} $id: foreign image ($image)"
        (( findings++ )) ;;
    esac

    # Everything else lives inside the container, so it can only be asked of a
    # running one — a stopped workspace gets the image verdict and nothing more.
    [[ $state == running ]] || continue
    # NOTE: </dev/null is not decoration. `devpod ssh` reads stdin, and stdin
    # here IS the snapshot the loop is reading — without this it swallowed the
    # remaining rows and the doctor silently checked only the first workspace.
    answer=$(devpod ssh "$id" --command "$_DP_PROBE" < /dev/null 2>/dev/null | tr -d '\r')
    [[ -z $answer ]] && { print -r -- "${_DP_MUTED}·${_DP_OFF} $id: container did not answer"; continue }
    read -r dc cl ag dirty dhead ddirty <<< "$answer"

    # 2. a devcontainer.json in the repository overrides our flags on the next
    #    reconnect, and without remoteUser the container comes up as root
    [[ $dc == root ]] && {
      print -r -- "${_DP_RED}✗${_DP_OFF} $id: own devcontainer.json without remoteUser — login will land as root"
      (( findings++ ))
    }
    # 3. secrets live in the container's home and do not survive a recreate
    (( cl && ag )) || {
      print -r -- "${_DP_YELLOW}⚠${_DP_OFF} $id: secrets incomplete (claude=$cl age=$ag) — dp secrets $id"
      (( findings++ ))
    }
    # 4. work a recreate would take with it
    (( dirty )) && print -r -- "${_DP_MUTED}·${_DP_OFF} $id: $dirty uncommitted files"
    # 5. the container runs entry scripts out of its OWN clone, so a stale one
    #    keeps executing last month's version of them. Silent until it is not:
    #    a clone 13 commits behind still had the copy of tmux-enter.sh from
    #    before the TERM fix, and every entry printed five "missing or
    #    unsuitable terminal". Measured against THIS repository rather than
    #    the container's own origin, whose refs are as stale as the clone.
    local -i behind
    if [[ $dhead == - || -z $dhead ]]; then
      print -r -- "${_DP_YELLOW}⚠${_DP_OFF} $id: no dotfiles clone in the container"
      (( findings++ ))
    elif ! git -C "$DOTFILES_DIR" cat-file -e "${dhead}^{commit}" 2>/dev/null; then
      print -r -- "${_DP_YELLOW}⚠${_DP_OFF} $id: dotfiles clone at $dhead, a commit this repository does not have"
      (( findings++ ))
    else
      behind=$(git -C "$DOTFILES_DIR" rev-list --count "${dhead}..HEAD" 2>/dev/null)
      (( behind )) && {
        print -r -- "${_DP_YELLOW}⚠${_DP_OFF} $id: dotfiles clone $behind commits behind — updl in the container"
        (( findings++ ))
      }
    fi
    (( ddirty )) && print -r -- "${_DP_MUTED}·${_DP_OFF} $id: $ddirty uncommitted files in the dotfiles clone"
  done < "$DP_SNAPSHOT"
  (( findings == 0 )) && print -r -- "${_DP_GREEN}✓${_DP_OFF} no discrepancies"
  return 0
}

# dp gc — what the hosts keep after a workspace is gone: content directories and
# containers whose workspace no longer exists.
_dp_gc() {
  emulate -L zsh
  local -A live_uid live_id hosts
  local id uid prov host
  while IFS=$'\t' read -r id uid prov host; do
    # NOTE: same dash-is-local rule as in _dp_state — see the note there.
    [[ $host == - ]] && host=
    live_uid[$uid]=1; live_id[$id]=1; hosts[${host:-LOCAL}]=1
  done < <(_dp_meta)

  local h dir cid lbl
  local -a dirs conts
  for h in ${(k)hosts}; do
    print -r -- "${_DP_MUTED}host ${h/LOCAL/local docker}${_DP_OFF}"
    if [[ $h == LOCAL ]]; then
      conts=(${(f)"$(docker ps -a --filter label=dev.containers.id \
        --format '{{.ID}} {{.Label "dev.containers.id"}}' 2>/dev/null)"})
      dirs=()
    else
      dirs=(${(f)"$(ssh -o BatchMode=yes -o ConnectTimeout=5 -T "$h" \
        'ls -1 ~/.devpod/agent/contexts/*/workspaces/ 2>/dev/null' 2>/dev/null)"})
      conts=(${(f)"$(ssh -o BatchMode=yes -o ConnectTimeout=5 -T "$h" \
        'docker ps -a --format "{{.ID}} {{.Label \"dev.containers.id\"}}"' 2>/dev/null)"})
    fi
    local -i orphan=0
    for dir in $dirs; do
      [[ -z $dir || -n ${live_id[$dir]} ]] && continue
      print -r -- "  directory  $dir"
      (( orphan++ ))
    done
    for lbl in $conts; do
      cid=${lbl%% *}
      lbl=${lbl#* }
      # NOTE: no label means the container is not devpod's at all — somebody
      # else's docker on a shared host. Listing those as orphans is how a
      # cleanup tool earns a reputation it cannot lose.
      [[ $lbl == $cid ]] && lbl=
      [[ -z $lbl || -n ${live_uid[$lbl]} ]] && continue
      print -r -- "  container  $cid  (label $lbl)"
      (( orphan++ ))
    done
    (( orphan == 0 )) && print -r -- "  ${_DP_GREEN}clean${_DP_OFF}"
  done
  # NOTE: listing only. Deleting someone else's container on a shared docker
  # host is not something a picker should ever do on its own.
  return 0
}

# What the log adds up to. Both files: the rolled one holds the older half of
# the same measurements, and percentiles want every sample they can get.
_dp_stats() {
  emulate -L zsh
  local -a files=( $DP_LOG(N) $DP_LOG.1(N) )
  (( $#files )) || { print -u2 "dp stats: nothing logged yet ($DP_LOG)"; return 1 }
  awk -f ${DOTFILES_DIR:-$HOME/.dotfiles}/tools/devpod/stats.awk $files
  print -r -- ""
  print -r -- "${_DP_FAINT}${_DP_MUTED}${DP_LOG}${_DP_OFF}"
}

# The verb surface. `dp` with nothing opens the picker and lets a key decide.
dp() {
  emulate -L zsh
  local verb=$1
  (( $# )) && shift
  case $verb in
    in)       ds "$@" ;;
    ls)       _dp_rows ;;
    new)      _dp_new "$@" ;;
    up)       local id e
              for id in "$@"; do
                e=$(_dp_entry "$id") || { print -u2 "dp up: $id is not in the catalog"; continue }
                _dp_pull "$DP_PROVIDER" "${${(s:|:)e}[1]}"
                _dp_up_one "$id" "${${(s:|:)e}[2]}" "${${(s:|:)e}[1]}"
              done ;;
    recreate) local i; for i in "$@"; do _dp_recreate "$i"; done ;;
    stop)     _dp_stop "$@" ;;
    rm)       devpod delete "$@" ;;
    secrets)  _dp_secrets "$@" ;;
    doctor)   _dp_doctor "$@" ;;
    gc)       _dp_gc "$@" ;;
    stats)    _dp_stats "$@" ;;
    tmux)     case $1 in
                on|off|exit) _dp_tmux_set "$1" ;;
                '') _dp_tmux_cycle ;;
                *) print -u2 "dp tmux: on, off, exit — or nothing to cycle"; return 1 ;;
              esac
              print -r -- "tmux landing: $(_dp_tmux_mode)" ;;
    log)      local -a f=( $DP_LOG(N) ); (( $#f )) && tail -n ${1:-20} $DP_LOG \
                || print -u2 "dp log: nothing logged yet ($DP_LOG)" ;;
    ''|pick)
      local out
      out=$(_dp_pick_action) || return 1
      # NOTE: "${(@f)…}" and not ${(f)…}. fzf prints the query FIRST, and with
      # an empty search line that first line is empty — plain (f) drops empty
      # elements, so the key slid into the query's slot and every binding
      # silently did nothing. Only a typed query made it work, which is exactly
      # what the first round of testing did.
      local -a lines=("${(@f)out}")
      local query=$lines[1] key=$lines[2]
      local -a ids=(${lines[3,-1]})
      ids=(${ids:#})
      local i e
      case $key in
        ctrl-n) _dp_new "${query// /}" ;;
        ctrl-s) for i in $ids; do _dp_secrets "$i"; done ;;
        *)      (( $#ids )) && ds "$ids[1]" ;;
      esac ;;
    -h|--help|help)
      print -r -- 'dp                 list, then a key decides'
      print -r -- 'dp in [id]         enter the container'
      print -r -- 'dp new <name>      new instance from a catalog repository'
      print -r -- 'dp up <id...>      bring up from the catalog'
      print -r -- 'dp recreate <id>   rebuild the container and restore its secrets'
      print -r -- 'dp stop|rm <id>    stop, delete'
      print -r -- 'dp secrets [id]    deliver secrets, picking which'
      print -r -- 'dp doctor [id]     drift: image, remoteUser, secrets, git'
      print -r -- 'dp gc              orphaned directories and containers on the hosts'
      print -r -- 'dp tmux [on|off|exit]  land in the container'\''s tmux; exit also closes the tab'
      print -r -- 'dp stats           how long each call takes, p50/p95, failures'
      print -r -- 'dp log [n]         the last n raw events (default 20)' ;;
    *) print -u2 "dp: unknown verb «$verb» (dp --help)"; return 1 ;;
  esac
}
