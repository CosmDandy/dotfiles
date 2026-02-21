#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

print_section "Installing Homebrew"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

print_section "Configuring Homebrew environment"
eval "$(/opt/homebrew/bin/brew shellenv)"

print_section "Adding Homebrew environment to shell profile"
BREW_PROFILE="$HOME/.zprofile"
if ! grep -q 'eval "\$\(\/opt\/homebrew\/bin\/brew shellenv\)"' "$BREW_PROFILE"; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$BREW_PROFILE"
fi
