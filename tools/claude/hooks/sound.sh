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
# Внутри контейнера своего afplay нет, и все четыре тембра там неизбежно
# сходятся в один BEL. Различие сохраняем текстом: OSC 9 показывает на Маке
# всплывашку с названием состояния (ghostty desktop-notifications = true).
set -u

snd="${1:-Glass}"
f="/System/Library/Sounds/${snd}.aiff"

# macOS: играем сами — не зависим ни от bell-action, ни от активности окна
if command -v afplay >/dev/null 2>&1 && [ -r "$f" ]; then
    afplay "$f" 2>/dev/null &
    exit 0
fi

case "$snd" in
Basso) label="упало" ;;
Blow) label="нужен ответ" ;;
Glass) label="фоновая задача готова" ;;
*) label="$snd" ;;
esac

# Писать строго в терминал: в фоновых сессиях stdout перехвачен, и BEL,
# отправленный в него, до Ghostty не доедет. Проверять правами нельзя —
# у фоновой сессии /dev/tty существует и выглядит доступным, но не открывается
# («Device not configured»), поэтому пробуем открыть и молча уходим при отказе.
if ! { exec 3>/dev/tty; } 2>/dev/null; then
    exit 0
fi

if [ -n "${TMUX:-}" ]; then
    # tmux не пропускает OSC наружу сам — нужен passthrough (allow-passthrough on)
    printf '\033Ptmux;\033\033]9;Claude: %s\007\033\\\a' "$label" >&3
else
    printf '\033]9;Claude: %s\007\a' "$label" >&3
fi

exec 3>&-
exit 0
