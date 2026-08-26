#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

if ! command -v brew &> /dev/null; then
  print_section "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  print_section "Homebrew already installed, skipping"
fi

print_section "Configuring Homebrew environment"
eval "$(/opt/homebrew/bin/brew shellenv)"
# NOTE: shellenv for the login shell is declared in tools/zsh/.zprofile — appending it
# here would write through the home-manager symlink straight into the repo.
