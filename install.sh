#!/usr/bin/env zsh

set -e

# Suppress debconf warnings in non-interactive containers
export DEBIAN_FRONTEND=noninteractive

# Определяем корень репозитория и экспортируем для всех дочерних скриптов
export DOTFILES_ROOT="$(cd "$(dirname "$0")" && pwd)"

# Вызовы — через $DOTFILES_ROOT, а не относительным путём: он и так вычисляется
# выше, но раньше игнорировался, и запуск не из корня репозитория падал на
# «no such file». Работало лишь потому, что README требует cd первым шагом.
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "🍎 Detected macOS"
  "$DOTFILES_ROOT/platform/macos/install.sh"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  echo "🐧 Detected Linux"
  "$DOTFILES_ROOT/platform/linux/install.sh"
else
  echo "❌ Unsupported OS: $OSTYPE"
  exit 1
fi
