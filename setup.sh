#!/usr/bin/env zsh

set -e

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
