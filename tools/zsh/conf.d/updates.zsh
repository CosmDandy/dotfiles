# Shared update machinery, used by both updm (mac) and updl (container).

zmodload zsh/datetime   # EPOCHREALTIME, for step durations

# Seconds → "12.3s" / "4m05s".
# NOTE: LC_NUMERIC=C — under a Russian locale printf writes a decimal comma.
_upd_fmt_dur() {
  local LC_NUMERIC=C
  local -i whole=$1
  if (( whole >= 60 )); then
    printf '%dm%02ds' $(( whole / 60 )) $(( whole % 60 ))
  else
    printf '%.1fs' $1
  fi
}

# Appends a step to the caller's report, if the caller keeps one (updm does, updl not).
_upd_record() { (( ${+_upd_report} )) && _upd_report+=("$1"$'\t'"$2"$'\t'"$3"$'\t'"$4") }

# One step of an update run: prints the label before running and, on failure, the number,
# the name and how many steps already applied.
# NOTE: updm used to be an 11-command && chain — a failure halfway told you neither where
# it stopped, nor whether it reached the switch, nor whether a generation needed rolling
# back.
_upd_step() {
  local label=$1; shift
  (( _upd_i++ ))
  print -P "%F{blue}▸ [$_upd_i] $label%f"
  local -F t0=$EPOCHREALTIME
  # NOTE: the exit code is taken right after the command, not inside `if ! cmd` — there $?
  # is the result of the negation, i.e. always 0, and the step would report success on a
  # failure.
  "$@"
  local code=$?
  _upd_record $_upd_i "$label" $(( EPOCHREALTIME - t0 )) $code
  if (( code != 0 )); then
    print -P "%F{red}✗ шаг $_upd_i «$label» упал (код $code).%f" >&2
    print -P "%F{yellow}  Шаги 1..$((_upd_i - 1)) уже применены — прогон не откатывается сам.%f" >&2
    return $code
  fi
}

# --- Concurrent phase -------------------------------------------------------------------
# Steps after the fail-fast chain do not depend on each other, so a failure no longer stops
# the run: every step finishes, each failure is reported by label and exit code, and the
# caller returns non-zero at the end. The caller declares and owns the state:
#   _upd_i, _upd_report, _upd_failed, _upd_pids, _upd_bg (parallel to _upd_pids:
#   "num<TAB>label<TAB>log"), _upd_dir (mktemp -d), and sets no_monitor/no_notify.

# A foreground step of the concurrent phase: the terminal is its own, so interactive and
# sudo steps go here. Unlike _upd_step it does not claim "steps 1..N-1 applied" — with
# lanes in flight that count would be a lie.
_upd_fg() {
  local label=$1; shift
  (( _upd_i++ ))
  print -P "%F{blue}▸ [$_upd_i] $label%f"
  local -F t0=$EPOCHREALTIME
  "$@"
  local code=$?
  local -F dt=$(( EPOCHREALTIME - t0 ))
  _upd_record $_upd_i "$label" $dt $code
  if (( code )); then
    _upd_failed+=("$label")
    print -P "%F{red}✗ [$_upd_i] $label упал (код $code, $(_upd_fmt_dur $dt))%f" >&2
  fi
  return 0
}

# Starts a step as a background lane with its output in its own log.
_upd_spawn() {
  local label=$1; shift
  (( _upd_i++ ))
  local log="$_upd_dir/$_upd_i.log"
  print -P "%F{blue}▸ [$_upd_i] $label%f %F{8}(фон → $log)%f"
  _upd_lane $_upd_i "$label" "$log" "$@" &
  _upd_pids+=($!)
  _upd_bg+=("$_upd_i"$'\t'"$label"$'\t'"$log")
}

# Body of a lane; runs in the forked subshell.
# NOTE: `trap - INT QUIT` — with job control off, zsh starts background jobs with SIGINT
# ignored, and the children inherit that: Ctrl-C would stop the foreground step and leave
# brew running behind the prompt. Restored, the lanes share the terminal's process group
# and die with the rest of the run.
# NOTE: stdin is /dev/null so a lane cannot steal keystrokes meant for the foreground
# step. sudo reads /dev/tty, not stdin — that is handled by the caller's keepalive and by
# SUDO_ASKPASS in the step itself.
_upd_lane() {
  local num=$1 label=$2 log=$3; shift 3
  trap - INT QUIT
  local -F t0=$EPOCHREALTIME
  "$@" > "$log" 2>&1 < /dev/null
  local code=$?
  local -F dt=$(( EPOCHREALTIME - t0 ))
  # the parent cannot see this subshell's variables; the duration goes back via a file
  print -r -- $dt > "$log.time"
  if (( code )); then
    print -P "%F{red}✗ [$num] $label упал (код $code, $(_upd_fmt_dur $dt))%f" >&2
  else
    print -P "%F{green}✓ [$num] $label%f %F{8}($(_upd_fmt_dur $dt))%f"
  fi
  exit $code
}

# Waits for every lane, records it, then prints the log tail of each failed one — only
# after all have finished, so no finish line lands in the middle of a tail.
_upd_join() {
  local -i i
  local -a codes
  local num label log dt
  (( ${#_upd_pids} )) || return 0   # {1..0} counts down, it is not empty
  for i in {1..${#_upd_pids}}; do
    wait ${_upd_pids[i]}
    codes[i]=$?
  done
  for i in {1..${#_upd_pids}}; do
    IFS=$'\t' read -r num label log <<< "${_upd_bg[i]}"
    dt=0
    [[ -r "$log.time" ]] && read -r dt < "$log.time"
    _upd_record $num "$label" $dt ${codes[i]}
    (( codes[i] )) || continue
    _upd_failed+=("$label")
    print -P "%F{red}── [$num] $label: код ${codes[i]}, хвост лога ($log):%f" >&2
    tail -n 20 "$log" >&2
  done
}

# Per-step durations; the gap between wall time and the sum is what concurrency saved.
_upd_summary() {
  local -F wall=$1 sum=0
  local row num label dt code mark
  print -P "%F{blue}── итог по шагам%f"
  for row in "${(@on)_upd_report}"; do
    IFS=$'\t' read -r num label dt code <<< "$row"
    (( sum += dt ))
    if (( code )); then mark="%F{red}✗ код $code%f"; else mark="%F{green}✓%f"; fi
    print -P "  ${(l:4:)${:-[$num]}} ${(r:24:)label} ${(l:7:)$(_upd_fmt_dur $dt)}  $mark"
  done
  print -P "  %F{8}всего $(_upd_fmt_dur $wall) (последовательно было бы $(_upd_fmt_dur $sum))%f"
}

_upd_zinit() { zinit self-update && zinit update && zinit cclear }

# NOTE: the claude/custom installer places MCP servers once, guarded by "no binary" — so it
# never updates them. context7-mcp fell a major version behind that way, and the uv tools
# vanished together with ~/.local/share/uv, leaving broken paths in ~/.claude.json and a
# server that failed on every Claude start. One step fixes both: a missing tool is
# installed, an existing one upgraded.
# NOTE: paths are taken the same way install.sh takes them — an env override plus a hard
# default, never by parsing `uv tool dir` or `npm prefix -g`, which colourise their output.
_upd_uv_tool() {
  local name=$1
  # NOTE: a broken symlink fails -x exactly like a missing file and falls into
  # `install --force`, which is the only thing that repairs the entry once uv's directory
  # has been wiped.
  if [[ -x "${UV_TOOL_BIN_DIR:-$HOME/.local/bin}/$name" ]]; then
    uv tool upgrade "$name"
  else
    uv tool install --force "$name"
  fi
}

# timing-mcp is a local project inside the custom submodule, not a published tool, so
# `uv tool` never reaches it and its venv used to be built once at install time and never
# touched again — that is how one machine sat on mcp 1.x while a fresh install resolved
# 2.x and crash-looped on the renamed API.
# NOTE: `uv lock --upgrade` then `uv sync`, not a bare sync: the lock is tracked now, so
# the bump has to land as a reviewable diff in the submodule, the same way updm treats
# flake.lock. A sync alone would only reinstall what the lock already pins.
# NOTE: bootout + bootstrap, not `launchctl kickstart -k`. kickstart restarts the process
# but keeps the job definition launchd loaded at login, and the listen address now comes
# from the plist's EnvironmentVariables (TIMING_MCP_HOST). A kickstarted agent would run
# the new code with the old environment, fall back to loopback, and every container would
# lose timing until the next login. The plist is a symlink into the submodule, so
# re-bootstrapping it is what picks up a changed one.
_upd_timing_mcp() {
  local dir="$HOME/.dotfiles/tools/claude/custom/mcp/timing"
  local plist="$HOME/Library/LaunchAgents/com.cosmdandy.timing-mcp.plist"
  [[ -f "$dir/pyproject.toml" ]] || return 0
  uv lock --upgrade --directory "$dir" --quiet || return 1
  uv sync --directory "$dir" --quiet || return 1
  if [[ -e "$plist" ]]; then
    launchctl bootout "gui/$(id -u)" "$plist" &> /dev/null
    launchctl bootstrap "gui/$(id -u)" "$plist" || return 1
  fi
  return 0
}

# NOTE: this step never fails the run — MCP is an auxiliary layer, and the network to
# npm/PyPI drops more often than everything else in updm combined.
_upd_mcp_tools() {
  local -i rc=0
  if command -v npm > /dev/null; then
    npm i -g --prefix "${NPM_CONFIG_PREFIX:-$HOME/.npm-global}" @upstash/context7-mcp@latest || rc=1
  fi
  if command -v uv > /dev/null; then
    _upd_uv_tool mcp-atlassian || rc=1
    # things-mcp needs Things.app — mac only, as in install.sh
    if [[ "$OSTYPE" == darwin* ]]; then
      _upd_uv_tool things-mcp || rc=1
      _upd_timing_mcp || rc=1
    fi
  fi
  (( rc )) && print -P "%F{yellow}  часть MCP-инструментов не обновилась%f" >&2
  return 0
}
