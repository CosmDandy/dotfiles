#!/usr/bin/env zsh

set -e

# Desired state of the OrbStack settings as code.
# NOTE: driven through `orb config` because OrbStack rewrites its own files, so a symlink
# is no good. The declarative apply is idempotent and portable.
#
# Only deliberately chosen, non-default values are listed. Machine-specific ones (username,
# subnet4) are left to OrbStack. Full list: `orb config show`.

typeset -A ORB_CONFIG=(
  # NOTE: these are CEILINGS, not reservations — OrbStack takes memory as needed and gives
  # it back (two running containers held 130 MiB of six available GiB). The point is the
  # other direction: on an 8 GiB machine one heavy container taking 6 GiB leaves the system
  # two and drives it into swap. Half the RAM to the VM, two cores of eight to the system,
  # so the interface stays responsive under full container load.
  cpu                        6
  memory_mib                 4096

  mount_hide_shared          true
  rosetta                    true
  app.start_at_login         true
  power.pause_in_sleep       true

  docker.expose_ports_to_lan true

  k8s.enable                 false
)

apply_orb_config() {
  if ! command -v orb >/dev/null 2>&1; then
    echo "⊘ orb CLI не найден — пропускаю настройку OrbStack"
    return 0
  fi

  # NOTE: on a clean macOS the engine has never started, and `orb config set` applies
  # changes to a running VM. `orb start` is idempotent and blocks until the engine is ready.
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
