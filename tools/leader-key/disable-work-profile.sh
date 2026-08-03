#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Disable Work Profile
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author CosmDandy

# Закрывается только рабочее. Telegram, Things, Timing, Ghostty и Arc остаются
# открытыми намеренно — они нужны и вне работы.
# `|| true` обязателен: killall на незапущенном процессе возвращает 1, и Raycast
# показывал ошибку выполнения, хотя профиль отрабатывал как надо.
pkill -f "Microsoft Teams" || true
killall Calendar || true
killall Mail || true
killall Obsidian || true
killall Claude || true
