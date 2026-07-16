#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

print_section "Setting up devpod"
print_section "Setting up devpod options"
devpod context set-options --option DOTFILES_URL=git@github.com:CosmDandy/dotfiles.git --option GIT_SSH_SIGNATURE_FORWARDING=false --option SSH_ADD_PRIVATE_KEYS=true --option SSH_AGENT_FORWARDING=true --option SSH_INJECT_DOCKER_CREDENTIALS=true --option SSH_INJECT_GIT_CREDENTIALS=false

print_section "Setting up default ide: none"
devpod ide use none
# Необходимо добавить указания .files конкретного

# provider add не идемпотентен («already exists» на повторном запуске)
print_section "Setting up local provider: local-docker"
if ! devpod provider list 2>/dev/null | grep -q "local-docker"; then
  devpod provider add docker --name local-docker --use -o INACTIVITY_TIMEOUT=1h
else
  echo "provider local-docker уже настроен"
fi

# ssh-провайдер требует Host kvt-d-01 из private/ssh/config и доступности хоста —
# на машине без приватного конфига/VPN не валим установку
print_section "Setting up ssh provider: kvt-d-01-ssh"
if ! devpod provider list 2>/dev/null | grep -q "kvt-d-01-ssh"; then
  devpod provider add ssh --name kvt-d-01-ssh -o HOST=kvt-d-01 \
    || echo "warn: ssh-провайдер kvt-d-01 не настроен (нет ~/.ssh/config или хост недоступен)"
else
  echo "provider kvt-d-01-ssh уже настроен"
fi

print_section "Setting up default provider: local-docker"
devpod provider use local-docker

print_section "Showing prowider list"
devpod provider list
