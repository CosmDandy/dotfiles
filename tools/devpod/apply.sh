#!/usr/bin/env zsh

set -e

# Desired state of the DevPod settings as code. Driven through the CLI because devpod has
# no config file to symlink — its state lives in ~/.devpod. Idempotent and portable, in
# the same shape as tools/orbstack/apply.sh.
#
# Full option list: `devpod context options`.

# NOTE: DOTFILES_URL is deliberately unset. devpod's --dotfiles mechanism cost ~8s per up:
# having just created the container it tore the connection down and built a second one only
# to clone the repo and start the script. The clone is baked into the image now and
# provisioning is declared as onCreateCommand in the image label, which also reaches work
# repositories that have no devcontainer.json of their own.
# Consequence: a workspace on somebody else's image no longer gets dotfiles — that needs a
# one-off `devpod up --dotfiles git@github.com:CosmDandy/dotfiles.git`.
typeset -A DEVPOD_CONTEXT=(
  # commit signing inside a container is off: the signing key stays on the mac
  GIT_SSH_SIGNATURE_FORWARDING  false
  # NOTE: never ssh-add local keys on connect — it pollutes the curated devpod agent
  # (4 keys) with every passphraseless key and trips MaxAuthTries on servers.
  SSH_ADD_PRIVATE_KEYS          false
  SSH_AGENT_FORWARDING          true
  SSH_INJECT_DOCKER_CREDENTIALS true
  # no git credentials: forges are reached over the ssh agent, not a token in the container
  SSH_INJECT_GIT_CREDENTIALS    false
)

# no IDE: the editor connects over ssh
DEVPOD_IDE=none

DEVPOD_DEFAULT_PROVIDER=local-docker

apply_devpod_config() {
  if ! command -v devpod >/dev/null 2>&1; then
    echo "⊘ devpod CLI не найден — пропускаю настройку DevPod"
    return 0
  fi

  local rc=0

  # set-options takes every option in one call and is idempotent
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

  # NOTE: `provider add` is NOT idempotent — on a second run it answers "already exists",
  # so only missing providers are added.
  if devpod provider list 2>/dev/null | grep -q "$DEVPOD_DEFAULT_PROVIDER"; then
    echo "✓ provider $DEVPOD_DEFAULT_PROVIDER"
  elif devpod provider add docker --name "$DEVPOD_DEFAULT_PROVIDER" --use -o INACTIVITY_TIMEOUT=1h; then
    echo "→ provider $DEVPOD_DEFAULT_PROVIDER добавлен"
  else
    echo "✗ provider $DEVPOD_DEFAULT_PROVIDER не добавлен"
    rc=1
  fi

  # NOTE: the ssh provider needs the Host entry from private/ssh/config and a reachable
  # host. Without the private submodule or off VPN this failure is expected, not breakage —
  # so rc is left alone.
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
