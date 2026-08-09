#!/usr/bin/env bash
# Отдельный ssh-agent для dev-контейнеров DevPod.
#
# Зачем. Блоки *.devpod в ~/.ssh/config автогенерирует DevPod, и в каждом стоит
# ForwardAgent yes. Убрать эту строку нельзя — она вернётся на следующем
# `devpod up`. А форвардинг отдаёт контейнеру не ключ, а право подписи всем,
# что лежит в агенте: любой процесс внутри контейнера может попросить подпись и
# зайти этим ключом куда угодно. IdentitiesOnly здесь не помогает — она про
# выбор identity при аутентификации, а не про содержимое агента.
#
# Что делает. Поднимает второй агент на своём сокете и кладёт туда только те
# ключи, которыми реально ходят из контейнеров. `IdentityAgent` в блоке
# `Host *.devpod` указывает ssh на этот сокет, а ForwardAgent пробрасывает
# именно выбранный IdentityAgent — значит контейнер получает ровно эти ключи, а
# не весь системный агент (там ещё cluster-autossh, ключ автоматики).
#
# Сокет лежит вне ~/.ssh намеренно: это runtime state, а не конфиг и не ключ.
#
# ssh-agent/ssh-add вызываются по абсолютному пути: --apple-use-keychain есть
# только у Apple-сборки из /usr/bin, а nix-овый openssh в PATH её перекрывает.

set -uo pipefail

SOCK_DIR="$HOME/.local/state/ssh-agents"
SOCK="$SOCK_DIR/devpod.sock"
KEYS=(private_ed25519 work_ed25519)

mkdir -p "$SOCK_DIR"
chmod 700 "$SOCK_DIR"
# Сокет от прошлого запуска: ssh-agent не стартует поверх существующего файла
rm -f "$SOCK"

/usr/bin/ssh-agent -D -a "$SOCK" &
agent_pid=$!

# Сокет появляется не мгновенно — без ожидания ssh-add отработает в пустоту
for _ in $(seq 1 50); do
  [[ -S "$SOCK" ]] && break
  sleep 0.1
done
if [[ ! -S "$SOCK" ]]; then
  echo "сокет $SOCK так и не появился" >&2
  exit 1
fi

export SSH_AUTH_SOCK="$SOCK"
for k in "${KEYS[@]}"; do
  key="$HOME/.ssh/$k"
  if [[ ! -f "$key" ]]; then
    echo "нет ключа $key — пропускаю" >&2
    continue
  fi
  # Пароль берётся из Keychain. Агент стартует user-агентом launchd, то есть
  # уже после логина, когда Keychain разблокирован.
  /usr/bin/ssh-add --apple-use-keychain "$key" || echo "не добавлен: $key" >&2
done

echo "агент готов, сокет $SOCK:"
/usr/bin/ssh-add -l

# launchd держит службу живой по этому процессу: агент запущен с -D
# (foreground), поэтому wait не вернётся, пока он работает.
wait "$agent_pid"
