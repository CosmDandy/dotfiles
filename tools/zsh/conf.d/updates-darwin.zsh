# Обновление системы — только macOS (darwin-rebuild, softwareupdate).
# Использует _upd_step/_upd_zinit из conf.d/updates.zsh — обычные вызовы функций,
# резолвятся в момент вызова, так что порядок между этим файлом и updates.zsh
# внутри общего цикла подключения conf.d не важен.
[[ "$OSTYPE" == darwin* ]] || return

# determinate-nixd первым: сам nix живёт вне nix-darwin (nix.enable = false,
# демоном владеет Determinate) и иначе не обновляется вообще — отставал на шесть
# минорных версий, пока не заметили.
# Гашение ворнинга о грязном дереве (flake.lock правится тут же, шагом выше):
# у nix это --no-warn-dirty, а darwin-rebuild своих флагов не знает и такой
# отвергает — ему то же самое передаём как --option warn-dirty false.
# sudo -H для GC: без него root наследует $HOME=/Users/cosmdandy и ругается
# «$HOME не принадлежит вам, откат на /var/root» дважды за прогон.
# flake check между update и switch: ловит сломанный на свежем nixpkgs пакет до
# активации (так укусил blueutil). --all-systems — иначе тихо пропускаются Linux-конфиги.
# GC: --delete-older-than вместо -d. `-d` сносит все старые генерации всех профилей
# ("makes rollbacks impossible") — после него откатываться некуда.
# Command Line Tools живут вне nix и brew — обновляются только через softwareupdate,
# а потому отстают молча: на машине стояла 26.2, когда доступны были 26.5 и 26.6.
# Ставим ТОЧЕЧНО по метке: `-i --all` затянул бы и macOS Tahoe с перезагрузкой прямо
# посреди updm. Побочный эффект — система сама выносит скачанные .pkg из
# /Library/Updates, которые заперты флагом SIP restricted и не удаляются даже под root.
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

# Сабмодули к пину из основного репо, но только безопасные для перемотки:
# грязные (незакоммиченные правки) и ушедшие вперёд пина (локальные коммиты,
# ещё не влитые в dotfiles) пропускаются с warn — иначе submodule update увёз
# бы локальную работу в detached HEAD, откуда её искать только по reflog.
# Пин может указывать на ещё не скачанный коммит (pull привёз новый gitlink) —
# тогда сперва fetch, иначе merge-base ложно посчитает сабмодуль «впереди».
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

# GC: --delete-older-than вместо -d. `-d` сносит все старые генерации всех профилей
# ("makes rollbacks impossible") — после него откатываться некуда.
# sudo -H: без него root наследует $HOME=/Users/cosmdandy и ругается
# «$HOME не принадлежит вам, откат на /var/root» дважды за прогон.
_upd_gc_darwin() {
  sudo nix-env -p /nix/var/nix/profiles/system --delete-generations +3 \
    && sudo -H nix-collect-garbage --delete-older-than 3d
}

updm() {
  emulate -L zsh
  local -i _upd_i=0

  _upd_step "dotfiles: pull"        git -C ~/.dotfiles pull --ff-only --no-recurse-submodules || return
  _upd_step "сабмодули к пину"      upds || return
  # determinate-nixd первым: сам nix живёт вне nix-darwin (nix.enable = false,
  # демоном владеет Determinate) и иначе не обновляется вообще — отставал на шесть
  # минорных версий, пока не заметили.
  _upd_step "determinate-nixd"      sudo determinate-nixd upgrade || return
  # Гашение ворнинга о грязном дереве (flake.lock правится тут же, шагом выше):
  # у nix это --no-warn-dirty, а darwin-rebuild своих флагов не знает и такой
  # отвергает — ему то же самое передаём как --option warn-dirty false.
  _upd_step "flake update"          nix flake update --no-warn-dirty --flake ~/.dotfiles/platform/nix || return
  # flake check между update и switch: ловит сломанный на свежем nixpkgs пакет до
  # активации (так укусил blueutil). --all-systems — иначе тихо пропускаются Linux-конфиги.
  _upd_step "flake check"           nix flake check --no-build --all-systems --no-warn-dirty ~/.dotfiles/platform/nix || return
  # $HOME, а не ~: тильда внутри кавычек не раскрывается и уехала бы в nix буквально.
  _upd_step "darwin-rebuild switch" sudo darwin-rebuild switch --option warn-dirty false --flake "$HOME/.dotfiles/platform/nix#macbook-cosmdandy" || return
  _upd_step "zinit"                 _upd_zinit || return
  _upd_step "GC поколений"          _upd_gc_darwin || return
  # Command Line Tools живут вне nix и brew — обновляются только через softwareupdate,
  # а потому отстают молча: на машине стояла 26.2, когда доступны были 26.5 и 26.6.
  _upd_step "Command Line Tools"    clt-update || return

  print -P "%F{green}✓ обновление прошло целиком ($_upd_i шагов)%f"
}
