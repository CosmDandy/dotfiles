# Shared update machinery, used by both updm (mac) and updl (container).

# One step of an update run: prints the label before running and, on failure, the number,
# the name and how many steps already applied.
# NOTE: updm used to be an 11-command && chain — a failure halfway told you neither where
# it stopped, nor whether it reached the switch, nor whether a generation needed rolling
# back.
_upd_step() {
  local label=$1; shift
  (( _upd_i++ ))
  print -P "%F{blue}▸ [$_upd_i] $label%f"
  # NOTE: the exit code is taken right after the command, not inside `if ! cmd` — there $?
  # is the result of the negation, i.e. always 0, and the step would report success on a
  # failure.
  "$@"
  local code=$?
  if (( code != 0 )); then
    print -P "%F{red}✗ шаг $_upd_i «$label» упал (код $code).%f" >&2
    print -P "%F{yellow}  Шаги 1..$((_upd_i - 1)) уже применены — прогон не откатывается сам.%f" >&2
    return $code
  fi
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
    fi
  fi
  (( rc )) && print -P "%F{yellow}  часть MCP-инструментов не обновилась%f" >&2
  return 0
}
