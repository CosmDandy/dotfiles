#!/usr/bin/env bash
# Loads the commit-signing key into the system ssh-agent at login.
#
# Зачем. git подписывает коммиты ключом, заданным как
# `user.signingkey = key::ssh-ed25519 …`, а форма `key::` заставляет ssh-keygen
# искать приватную половину В АГЕНТЕ — файлы он в этом режиме не читает вовсе.
# Системный агент наполняется только побочно, через `AddKeysToAgent yes` при
# ssh-подключениях, а ключом подписи никуда не ходят — значит сам он туда не
# попадает никогда. После каждой перезагрузки агент поднимается без него, и
# `git commit` падает на «No private key found for public key».
#
# Выделенный агент для контейнеров (org.nixos.ssh-devpod-agent) этот ключ тоже
# держит, но git разговаривает с тем сокетом, на который смотрит $SSH_AUTH_SOCK,
# то есть с системным агентом. Поэтому ключ нужен в обоих.
#
# ssh-add вызывается по абсолютному пути: --apple-use-keychain есть только у
# Apple-сборки из /usr/bin, а nix-овый openssh в PATH её перекрывает.

set -uo pipefail

KEY="$HOME/.ssh/id_ed25519_sign"

# launchd отдаёт user-агенту сокет системного ssh-agent в наследуемом окружении.
# Без него добавлять некуда, и это не «нечего делать», а поломка конфигурации.
if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
  echo "SSH_AUTH_SOCK не задан — системный агент недоступен" >&2
  exit 1
fi

if [[ ! -f "$KEY" ]]; then
  echo "нет ключа $KEY" >&2
  exit 1
fi

# Идемпотентность по отпечатку, а не по факту вызова: повторный ssh-add молча
# перезаписал бы запись в агенте и лишний раз сходил в Keychain.
fp=$(/usr/bin/ssh-keygen -lf "$KEY.pub" 2>/dev/null | awk '{print $2}')
if [[ -n "$fp" ]] && /usr/bin/ssh-add -l 2>/dev/null | grep -qF "$fp"; then
  echo "ключ подписи уже в агенте: $fp"
  exit 0
fi

# Пароль берётся из Keychain. Агент стартует user-агентом launchd, то есть уже
# после логина, когда Keychain разблокирован.
/usr/bin/ssh-add --apple-use-keychain "$KEY"
/usr/bin/ssh-add -l
