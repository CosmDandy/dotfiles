#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

print_section "Installing Nix"
# curl -L https://nixos.org/nix/install | sh
curl -fsSL https://install.determinate.systems/nix | sh -s -- install --determinate

if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    print_section "Loading Nix into current session"
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

print_section "Applying nix-darwin configuration"
if command -v darwin-rebuild &> /dev/null; then
    echo "darwin-rebuild установлен"
    darwin-rebuild switch --flake "$DOTFILES_ROOT/platform/macos/nix#macbook-cosmdandy"
else
    echo "darwin-rebuild не найден, используем nix run"
    sudo nix --extra-experimental-features "nix-command flakes" run nix-darwin -- switch --flake "$DOTFILES_ROOT/platform/macos/nix#macbook-cosmdandy"
fi
