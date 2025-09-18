#!/usr/bin/env zsh

set -e

if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "🍎 Detected macOS"
  ./scripts/install_macos.sh
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  echo "🐧 Detected Linux"
  ./scripts/install_linux.sh
else
  echo "❌ Unsupported OS: $OSTYPE"
  exit 1
fi
