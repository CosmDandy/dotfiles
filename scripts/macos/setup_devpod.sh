#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

print_section "Setting up devpod"
print_section "Setting up devpod options"
devpod context set-options --option DOTFILES_URL=git@github.com:CosmDandy/dotfiles.git --option GIT_SSH_SIGNATURE_FORWARDING=false --option SSH_ADD_PRIVATE_KEYS=true --option SSH_AGENT_FORWARDING=true --option SSH_INJECT_DOCKER_CREDENTIALS=true --option SSH_INJECT_GIT_CREDENTIALS=false

print_section "Setting up default ide: none"
devpod ide use none
# Необходимо добавить указания .files конкретного

print_section "Setting up local provider: local-docker"
devpod provider add docker --name local-docker --use

print_section "Setting up ssh provider: work-d-01-ssh"
devpod provider add ssh --name work-d-01-ssh -o HOST=work-d-01

print_section "Setting up default provider: local-docker"
devpod provider use local-docker

print_section "Showing prowider list"
devpod provider list
