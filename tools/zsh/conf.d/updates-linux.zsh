# System updates — Linux only (dev containers: apt, home-manager).
# Uses _upd_step/_upd_zinit from conf.d/updates.zsh; the load order does not matter.
[[ "$OSTYPE" == darwin* ]] && return

_upd_apt() { sudo apt-get update && sudo apt-get upgrade -y }
_upd_gc_linux() { home-manager expire-generations "-7 days" && nix-collect-garbage --delete-older-than 3d }

# NOTE: versions follow the repo's flake.lock, which is bumped on the mac and committed —
# so this pulls and switches rather than running flake update inside the container.
updl() {
  emulate -L zsh
  local -i _upd_i=0
  local profile="$(cat ~/.dotfiles-profile 2> /dev/null || echo devops)"
  local target="$HOME/dotfiles/platform/nix#$(whoami)-${profile}-$(uname -m)-linux"

  _upd_step "dotfiles: pull"     git -C ~/dotfiles pull --ff-only --no-recurse-submodules || return
  _upd_step "home-manager switch" home-manager switch --flake "$target" -b hm-backup || return
  _upd_step "apt upgrade"        _upd_apt || return
  # the same gap as on the mac: the claude/custom installer places context7-mcp once and
  # never updates it
  _upd_step "MCP-инструменты"    _upd_mcp_tools || return
  _upd_step "zinit"              _upd_zinit || return
  _upd_step "GC поколений"       _upd_gc_linux || return

  print -P "%F{green}✓ обновление прошло целиком ($_upd_i шагов)%f"
}
