#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

# NOTE: rerunning the installer over a live nix fails, hence the guard; --no-confirm is
# required or a headless run dies with "Unable to run interactively".
if ! command -v nix &>/dev/null; then
  print_section "Installing Nix"
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --determinate --no-confirm
fi

if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    print_section "Loading Nix into current session"
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

# primaryUser/hostname are mkDarwin parameters in flake.nix rather than an edit to a
# tracked file — the sed over the working copy is gone, so the flake is a function of the
# commit again and installing no longer dirties the tree.
print_section "Applying nix-darwin configuration"
if command -v darwin-rebuild &> /dev/null; then
    echo "darwin-rebuild установлен"
    # NOTE: sudo is required — "system activation must now be run as root".
    sudo darwin-rebuild switch --flake "$DOTFILES_ROOT/platform/nix#macbook-cosmdandy"
else
    echo "darwin-rebuild не найден, используем nix run"
    sudo nix --extra-experimental-features "nix-command flakes" run nix-darwin -- switch --flake "$DOTFILES_ROOT/platform/nix#macbook-cosmdandy"
fi
