#!/usr/bin/env zsh

set -e

# Желаемое состояние настроек OrbStack (config-as-code).
# Управляется через `orb config` — OrbStack сам переписывает свои файлы,
# поэтому симлинк не годится; декларативный apply идемпотентен и переносим.
#
# Список — только осознанно выбранные, не-дефолтные значения.
# Машино-специфичные (username, subnet4) намеренно не пиним — OrbStack
# назначает их сам. Полный список опций: `orb config show`.

typeset -A ORB_CONFIG=(
  # Ресурсы VM
  cpu                        7
  memory_mib                 6144

  # Поведение
  mount_hide_shared          true
  rosetta                    true
  app.start_at_login         true
  power.pause_in_sleep       true

  # Docker
  docker.expose_ports_to_lan true

  # Kubernetes выключен
  k8s.enable                 false
)

apply_orb_config() {
  if ! command -v orb >/dev/null 2>&1; then
    echo "⊘ orb CLI не найден — пропускаю настройку OrbStack"
    return 0
  fi

  # На чистом macOS движок ещё ни разу не стартовал, а `orb config set`
  # применяет изменения к VM — нужен запущенный OrbStack. `orb start`
  # идемпотентен (no-op если уже запущен) и блокирует до готовности движка.
  echo "→ ensuring OrbStack is running…"
  orb start

  local key value current
  for key in ${(k)ORB_CONFIG}; do
    value="${ORB_CONFIG[$key]}"
    current="$(orb config get "$key" 2>/dev/null || true)"
    if [[ "$current" == "$value" ]]; then
      echo "✓ $key = $value"
    else
      orb config set "$key" "$value"
      echo "→ $key: $current → $value"
    fi
  done
}

apply_orb_config
