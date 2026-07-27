#!/bin/sh
# Звуковая метка события Claude Code: один тембр = одно состояние, чтобы
# различать их не глядя на экран.
#   Submarine — турн закончен. Ставится НЕ здесь: Stop бьёт в bell, а звук
#               вешает tmux на alert-bell (так остаётся и подсветка окна).
#   Blow      — нужен ответ или разрешение (Notification).
#   Glass     — фоновая задача завершилась (TaskCompleted).
#   Basso     — упало (PostToolUseFailure, StopFailure).
#
# afplay есть только на macOS. В контейнере падаем в bell: звука не будет, но
# tmux (monitor-bell) подсветит окно — сигнал деградирует, а не исчезает.
set -u

snd="${1:-Glass}"
f="/System/Library/Sounds/${snd}.aiff"

if command -v afplay >/dev/null 2>&1 && [ -r "$f" ]; then
    # в фон: хук не должен ждать проигрывания даже при async
    afplay "$f" 2>/dev/null &
else
    printf '\a'
fi

exit 0
