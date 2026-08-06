#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

# Идемпотентность: повторный запуск инсталлера на живом nix падает;
# --no-confirm — без него headless-запуск умирает («Unable to run interactively»)
if ! command -v nix &>/dev/null; then
  print_section "Installing Nix"
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --determinate --no-confirm
fi

if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    print_section "Loading Nix into current session"
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

# primaryUser/hostname задаются параметрами mkDarwin во flake.nix, а не
# правкой трекаемого файла — sed по working copy убран (флейк снова функция
# от коммита, дерево не грязнится установкой).
print_section "Applying nix-darwin configuration"
if command -v darwin-rebuild &> /dev/null; then
    echo "darwin-rebuild установлен"
    # sudo обязателен: «system activation must now be run as root» (как в updm)
    sudo darwin-rebuild switch --flake "$DOTFILES_ROOT/platform/nix#macbook-cosmdandy"
else
    echo "darwin-rebuild не найден, используем nix run"
    sudo nix --extra-experimental-features "nix-command flakes" run nix-darwin -- switch --flake "$DOTFILES_ROOT/platform/nix#macbook-cosmdandy"
fi
