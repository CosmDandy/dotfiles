#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle Built-in Display
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🖥️
# @raycast.packageName BetterDisplay

# Documentation:
# @raycast.description Подключить/отключить встроенный дисплей MacBook (BetterDisplay Pro).
# @raycast.author CosmDandy

# NOTE: matched by the LOCALISED display name, so it breaks if the system language changes.
# The language-independent fallback is the UUID, stable on this machine:
#   -UUID="37D8832A-2D66-02CA-B9F7-8F30A301B230"
exec /opt/homebrew/bin/betterdisplaycli toggle -nameLike="Встроенный" -connected
