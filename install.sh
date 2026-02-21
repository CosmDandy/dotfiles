#!/usr/bin/env zsh

set -e

# Определяем корень репозитория и экспортируем для всех дочерних скриптов
export DOTFILES_ROOT="$(cd "$(dirname "$0")" && pwd)"

if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "🍎 Detected macOS"
  ./platform/macos/install.sh
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  echo "🐧 Detected Linux"
  ./platform/linux/install.sh
else
  echo "❌ Unsupported OS: $OSTYPE"
  exit 1
fi
