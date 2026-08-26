#!/usr/bin/env zsh
#
# Shared library for the installers.
# NOTE: no `set` of its own on purpose — this file is sourced, and `set -e` here would
# change the CALLER's behaviour rather than its own. The installers set their own mode, and
# the code below is written to survive it (hence the `${VAR:-}` guards).
#
# NOTE: zsh rather than bash because on a fresh mac nix is not installed yet, so
# `#!/usr/bin/env bash` resolves to /bin/bash 3.2 (2007), where `"${arr[@]}"` on an empty
# array under `set -u` dies with "unbound variable". The system zsh is 5.9.

if [ -z "${DOTFILES_ROOT:-}" ]; then
  # NOTE: ${(%):-%x} is the zsh-native path of the sourced file — BASH_SOURCE is empty here.
  PLATFORM_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
  export DOTFILES_ROOT="$(dirname "$PLATFORM_DIR")"
fi

# NOTE: nix-darwin's /etc/zshenv rewrites PATH for every new zsh process, so sub-scripts
# lose the /opt/homebrew/bin they inherited from install.sh and cannot find devpod or orb.
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

RED='\033[0;31m'
NC='\033[0m'

print_section() {
  local message="$*"
  printf '%0.s~' {1..70}
  echo
  echo -e "${RED}$message${NC}"
  printf '%0.s~' {1..70}
  echo
}

confirm() {
  # NOTE: headless (no tty) — `read -k 1` returns EOF instantly and the loop would spin
  # forever, so auto-confirm and move on.
  if [[ ! -t 0 ]]; then
    echo "$1 — no tty, auto-yes"
    return 0
  fi
  while true; do
    read -k 1 "REPLY?$1 (y/n): " || { echo "stdin closed — auto-yes"; return 0; }
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Continuing..."
      return 0
    elif [[ $REPLY =~ ^[Nn]$ ]]; then
      echo "Cancelled"
      exit 1
    else
      echo "Please enter y or n"
    fi
  done
}

setup_app() {
  local app_name="$1"
  shift
  local tasks=("$@")

  print_section "Setting up: $app_name"
  open -a "$app_name"

  if [[ ${#tasks[@]} -gt 0 ]]; then
    echo "Tasks to complete:"
    for task in "${tasks[@]}"; do
      echo "  • $task"
    done
  fi

  echo ""
  read "response?Press Enter when done (or 's' to skip): "

  if [[ "${response:-}" == "s" ]]; then
    echo "⊘ Skipped $app_name"
  else
    echo "✓ Completed $app_name"
  fi
  echo ""

  osascript -e "quit app \"$app_name\""
}

create_directories() {
  local directories=("$@")
  for dir in "${directories[@]}"; do
    mkdir -p "$dir"
    echo "Created directory ${dir}"
  done
}
