#!/usr/bin/env zsh

set -e

# Желаемое состояние настроек DevPod (config-as-code).
# Управляется через `devpod` CLI: своего конфигурационного файла, который можно
# было бы положить симлинком, у него нет — состояние живёт в ~/.devpod.
# Декларативный apply идемпотентен и переносим. По образцу tools/orbstack/apply.sh.
#
# Полный список опций контекста: `devpod context options`.

# Опции контекста. Пробрасывание ssh/git-доступов внутрь воркспейса и адрес
# dotfiles, которые DevPod разворачивает в каждом новом контейнере.
typeset -A DEVPOD_CONTEXT=(
  DOTFILES_URL                  git@github.com:CosmDandy/dotfiles.git
  # Подпись коммитов внутри контейнера выключена: ключ подписи остаётся на маке
  GIT_SSH_SIGNATURE_FORWARDING  false
  SSH_ADD_PRIVATE_KEYS          true
  SSH_AGENT_FORWARDING          true
  SSH_INJECT_DOCKER_CREDENTIALS true
  # Git-креды не инжектим: ходим по ssh-агенту, а не по токену в контейнере
  SSH_INJECT_GIT_CREDENTIALS    false
)

# IDE не навязываем: подключаемся своим редактором по ssh
DEVPOD_IDE=none

# Провайдер по умолчанию — локальный докер
DEVPOD_DEFAULT_PROVIDER=local-docker

apply_devpod_config() {
  if ! command -v devpod >/dev/null 2>&1; then
    echo "⊘ devpod CLI не найден — пропускаю настройку DevPod"
    return 0
  fi

  local rc=0

  # set-options принимает все опции одним вызовом и идемпотентен
  local -a opts
  local key
  for key in ${(k)DEVPOD_CONTEXT}; do
    opts+=(--option "$key=${DEVPOD_CONTEXT[$key]}")
  done
  if devpod context set-options "${opts[@]}"; then
    echo "✓ context options (${#DEVPOD_CONTEXT} шт.)"
  else
    echo "✗ devpod context set-options не сработал"
    rc=1
  fi

  if devpod ide use "$DEVPOD_IDE" >/dev/null; then
    echo "✓ ide = $DEVPOD_IDE"
  else
    echo "✗ devpod ide use $DEVPOD_IDE не сработал"
    rc=1
  fi

  # provider add НЕ идемпотентен — на повторном запуске отвечает «already
  # exists», поэтому добавляем только отсутствующие.
  if devpod provider list 2>/dev/null | grep -q "$DEVPOD_DEFAULT_PROVIDER"; then
    echo "✓ provider $DEVPOD_DEFAULT_PROVIDER"
  elif devpod provider add docker --name "$DEVPOD_DEFAULT_PROVIDER" --use -o INACTIVITY_TIMEOUT=1h; then
    echo "→ provider $DEVPOD_DEFAULT_PROVIDER добавлен"
  else
    echo "✗ provider $DEVPOD_DEFAULT_PROVIDER не добавлен"
    rc=1
  fi

  # ssh-провайдер требует Host kvt-d-01 из private/ssh/config и доступности
  # хоста. На машине без приватного сабмодуля или вне VPN это ожидаемый отказ,
  # а не поломка — rc не трогаем.
  if devpod provider list 2>/dev/null | grep -q "kvt-d-01-ssh"; then
    echo "✓ provider kvt-d-01-ssh"
  elif devpod provider add ssh --name kvt-d-01-ssh -o HOST=kvt-d-01; then
    echo "→ provider kvt-d-01-ssh добавлен"
  else
    echo "⊘ provider kvt-d-01-ssh пропущен (нет ~/.ssh/config или хост недоступен)"
  fi

  if devpod provider use "$DEVPOD_DEFAULT_PROVIDER" >/dev/null; then
    echo "✓ provider use $DEVPOD_DEFAULT_PROVIDER"
  else
    echo "✗ devpod provider use $DEVPOD_DEFAULT_PROVIDER не сработал"
    rc=1
  fi

  return $rc
}

apply_devpod_config
