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

# Встроенный дисплей у CosmDandy называется "Встроенный дисплей" (локализованное имя).
# Язык-независимый запасной вариант — по UUID (стабилен на этой машине):
#   -UUID="37D8832A-2D66-02CA-B9F7-8F30A301B230"
exec /opt/homebrew/bin/betterdisplaycli toggle -nameLike="Встроенный" -connected
