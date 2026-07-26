# Обновление системы — только Linux (dev-контейнеры: apt, home-manager).
# Использует _upd_step/_upd_zinit из conf.d/updates.zsh — см. комментарий в
# updates-darwin.zsh про независимость от порядка загрузки.
[[ "$OSTYPE" == darwin* ]] && return

_upd_apt() { sudo apt-get update && sudo apt-get upgrade -y }
_upd_gc_linux() { home-manager expire-generations "-7 days" && nix-collect-garbage --delete-older-than 3d }

# Linux: версии следуют за flake.lock репо (bump — на маке через updm + commit),
# поэтому git pull + home-manager switch, а не flake update в контейнере
updl() {
  emulate -L zsh
  local -i _upd_i=0
  local profile="$(cat ~/.dotfiles-profile 2> /dev/null || echo devops)"
  local target="$HOME/dotfiles/platform/nix#$(whoami)-${profile}-$(uname -m)-linux"

  _upd_step "dotfiles: pull"     git -C ~/dotfiles pull --ff-only --no-recurse-submodules || return
  _upd_step "home-manager switch" home-manager switch --flake "$target" -b hm-backup || return
  _upd_step "apt upgrade"        _upd_apt || return
  _upd_step "zinit"              _upd_zinit || return
  _upd_step "GC поколений"       _upd_gc_linux || return

  print -P "%F{green}✓ обновление прошло целиком ($_upd_i шагов)%f"
}
