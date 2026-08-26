# System updates — macOS only (darwin-rebuild, softwareupdate). Uses
# _upd_step/_upd_zinit from conf.d/updates.zsh: plain function calls, resolved
# when called, so the load order within conf.d does not matter.
[[ "$OSTYPE" == darwin* ]] || return

# NOTE: Command Line Tools live outside nix and brew and only softwareupdate
# moves them, so they lag silently — 26.2 was installed while 26.5 and 26.6 were
# available.
# NOTE: installed by exact label, never `-i --all` — a full macOS upgrade with a
# restart sits in the same list and would run in the middle of updm. Side effect
# worth having: the system then evicts the downloaded .pkg files from
# /Library/Updates, which SIP marks restricted and root cannot delete.
clt-update() {
  local label
  label=$(softwareupdate --list 2>/dev/null \
    | grep -o 'Command Line Tools for Xcode [0-9.]*-[0-9.]*' \
    | tail -1)
  if [[ -z $label ]]; then
    echo "Command Line Tools: обновлений нет"
    return 0
  fi
  echo "Command Line Tools: ставлю $label"
  sudo softwareupdate -i "$label"
}

# Submodules to the superproject's pin, but only where it is safe to move them.
# NOTE: dirty submodules and ones ahead of the pin are skipped with a warning —
# otherwise `submodule update` would drag local work into a detached HEAD,
# findable only by reflog.
# NOTE: the pin may name a commit not fetched yet (a pull brought a new
# gitlink), so fetch first or merge-base falsely reports the submodule as being
# ahead.
upds() {
  git -C ~/.dotfiles submodule foreach --quiet '
    expected=$(git -C "$toplevel" rev-parse "HEAD:$sm_path")
    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "warn: $sm_path грязный — пропущен, обнови руками"
    else
      git cat-file -e "$expected^{commit}" 2>/dev/null || git fetch --quiet origin
      if ! git merge-base --is-ancestor HEAD "$expected" 2>/dev/null; then
        echo "warn: $sm_path впереди пина (локальные коммиты) — пропущен"
      elif [ "$(git rev-parse HEAD)" != "$expected" ]; then
        git -C "$toplevel" submodule update --init -- "$sm_path" \
          && echo "$sm_path → $(git rev-parse --short "$expected")"
      fi
    fi'
}

# NOTE: --delete-older-than, never `-d` — that removes every old generation of
# every profile ("makes rollbacks impossible") and leaves nothing to roll back
# to.
# NOTE: sudo -H for the GC, or root inherits $HOME and complains that it is not
# owned by it, twice per run.
_upd_gc_darwin() {
  sudo nix-env -p /nix/var/nix/profiles/system --delete-generations +3 \
    && sudo -H nix-collect-garbage --delete-older-than 3d
}

# brew bundle installs new casks during activation but never upgrades existing
# ones (onActivation.upgrade = false, for the reproducibility of the switch), so
# the upgrade lives here as an explicit step.
# NOTE: --greedy is mandatory — without it brew stays silent about casks with
# auto_updates or version:latest, which looked current for years while never
# actually moving.
# NOTE: one cask at a time, not in a batch — brew abandons the rest on the first
# failure, so one broken recipe would eat the whole list. A failed cask does not
# fail the run; zinit, GC and Command Line Tools come after it.
# NOTE: `sudo -v` up front — pkg-based casks ask for a password from inside
# brew, which mid-run is indistinguishable from a hung step. A running app is
# updated on disk but keeps the old version in memory until restarted.
_upd_brew_casks() {
  local out cask
  local -a outdated failed
  # NOTE: NO_COLOR — the captured output becomes cask names, and ANSI inside a
  # name breaks the brew upgrade that follows.
  out=$(NO_COLOR=1 brew outdated --cask --greedy --quiet) || return 1
  outdated=(${(f)out})
  if (( ${#outdated} == 0 )); then
    echo "каски: обновлений нет"
    return 0
  fi
  echo "к обновлению (${#outdated}): ${outdated}"
  sudo -v
  for cask in $outdated; do
    brew upgrade --cask --greedy "$cask" || failed+=("$cask")
  done
  if (( ${#failed} )); then
    print -P "%F{yellow}  не обновились: ${failed}%f" >&2
  fi
  return 0
}

# The App Store is the third package manager on this machine and was missing
# from the run entirely — mas stayed as silent as the casks did.
_upd_mas() {
  local out
  command -v mas > /dev/null || { echo "mas не найден — пропуск"; return 0 }
  out=$(NO_COLOR=1 mas outdated 2> /dev/null)
  if [[ -z $out ]]; then
    echo "App Store: обновлений нет"
    return 0
  fi
  echo "$out"
  mas upgrade || print -P "%F{yellow}  mas upgrade не прошёл%f" >&2
  return 0
}

updm() {
  emulate -L zsh
  local -i _upd_i=0

  _upd_step "dotfiles: pull"        git -C ~/.dotfiles pull --ff-only --no-recurse-submodules || return
  _upd_step "сабмодули к пину"      upds || return
  # NOTE: determinate-nixd first — nix itself lives outside nix-darwin (the
  # daemon belongs to Determinate) and is otherwise never updated. It was six
  # minor versions behind before anyone noticed.
  _upd_step "determinate-nixd"      sudo determinate-nixd upgrade || return
  # NOTE: the dirty-tree warning (flake.lock is edited a step above) is silenced
  # with --no-warn-dirty for nix, but darwin-rebuild rejects its own flags and
  # needs the same thing as `--option warn-dirty false`.
  _upd_step "flake update"          nix flake update --no-warn-dirty --flake ~/.dotfiles/platform/nix || return
  # NOTE: a flake check between update and switch catches a package broken by
  # fresh nixpkgs before activation (blueutil did exactly that). --all-systems,
  # or the Linux configurations are skipped silently.
  _upd_step "flake check"           nix flake check --no-build --all-systems --no-warn-dirty ~/.dotfiles/platform/nix || return
  # NOTE: $HOME, not ~ — a tilde inside quotes is not expanded and would reach
  # nix literally.
  _upd_step "darwin-rebuild switch" sudo darwin-rebuild switch --option warn-dirty false --flake "$HOME/.dotfiles/platform/nix#macbook-cosmdandy" || return
  _upd_step "каски (brew upgrade)"  _upd_brew_casks || return
  _upd_step "App Store (mas)"       _upd_mas || return
  # the custom installer places MCP tools once and never updates them
  _upd_step "MCP-инструменты"       _upd_mcp_tools || return
  _upd_step "zinit"                 _upd_zinit || return
  _upd_step "GC поколений"          _upd_gc_darwin || return
  _upd_step "Command Line Tools"    clt-update || return

  print -P "%F{green}✓ обновление прошло целиком ($_upd_i шагов)%f"
}
