#!/bin/sh
# Звуковая метка события Claude Code: один тембр = одно состояние, чтобы
# различать их не глядя на экран.
#   Submarine — турн закончен. Ставится НЕ здесь: Stop бьёт в bell, а озвучивает
#               его Ghostty (bell-features audio) — так сигнал одинаково слышен
#               и с Мака, и из dev-контейнера.
#   Blow      — нужен ответ или разрешение (Notification).
#   Glass     — фоновая задача завершилась (TaskCompleted).
#   Basso     — упало (PostToolUseFailure, StopFailure).
#
# В контейнере своего afplay нет, и все четыре тембра там неизбежно сходятся
# в один BEL — его озвучит Ghostty на хосте. Различать события текстом не
# получается: уведомления Ghostty на macOS не работают (ghostty-org/ghostty#10151),
# ни OSC 9, ни OSC 777. Визуальную часть поэтому несёт progress.sh — полоса
# прогресса работает надёжно и локально, и из контейнера.
set -u

snd="${1:-Glass}"
f="/System/Library/Sounds/${snd}.aiff"

# macOS: играем сами — не зависим ни от bell-action, ни от активности окна
if command -v afplay >/dev/null 2>&1 && [ -r "$f" ]; then
    afplay "$f" 2>/dev/null &
    exit 0
fi

# Иначе (контейнер) — BEL в терминал. Не в stdout: у хуков он перехвачен.
# Открываем tty попыткой, а не проверкой прав: в фоновых сессиях /dev/tty
# выглядит доступным, но не открывается («Device not configured»).
if { exec 3>/dev/tty; } 2>/dev/null; then
    printf '\a' >&3
    exec 3>&-
fi

exit 0
