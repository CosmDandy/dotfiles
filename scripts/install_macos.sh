#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

print_section "Installing system dependencies"
softwareupdate --install-rosetta

print_section "Installing Homebrew"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

print_section "Configuring Homebrew environment"
BREW_PROFILE="$HOME/.zprofile"
if ! grep -q 'eval "\$\(\/opt\/homebrew\/bin\/brew shellenv\)"' "$BREW_PROFILE"; then
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$BREW_PROFILE"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

print_section "Installing Nix"
curl -L https://nixos.org/nix/install | sh

if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
  print_section "Loading Nix into current session"
  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

print_section "Applying nix-darwin configuration"
darwin-rebuild switch --flake $SCRIPT_DIR/nix#default
# sudo nix --extra-experimental-features "nix-command flakes" run nix-darwin -- switch --flake $SCRIPT_DIR/nix/flake.nix

print_section "Creating symbolic links"
"$SCRIPT_DIR/macos/setup_symlinks.sh"

print_section "Setting up devpod"
"$SCRIPT_DIR/macos/setup_devpod.sh"

print_section "Installing apps"
"$SCRIPT_DIR/macos/setup_extra.sh"

print_section "Install complete"
