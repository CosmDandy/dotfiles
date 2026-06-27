#!/usr/bin/env bash
# Динамическое меню сессий для prefix+s: строит tmux display-menu из реального
# списка сессий, прыжок по горячей клавише. Имена автогенерируются (по директории),
# поэтому хардкод не годится — читаем их на лету.
#
# Горячая клавиша (3-й аргумент пункта) выводится самим tmux справа в скобках —
# это родной индикатор хоткея в 3.6, в подпись её дублировать не нужно.
set -eu

cur="$(tmux display-message -p '#S')"

args=()
i=0
while IFS= read -r name; do
  i=$((i + 1))

  # Текущую сессию помечаем точкой, чтобы видеть, где находишься.
  mark=""
  [ "$name" = "$cur" ] && mark=" ●"

  # Горячая клавиша — порядковый номер. Цифры не конфликтуют при любых именах
  # сессий (в отличие от первых букв); tmux сам припишет (1), (2)… справа.
  args+=("$name$mark" "$i" "switch-client -t \"$name\"")
done < <(tmux list-sessions -F '#{session_name}' | sort)

# Действия над сессиями (буква-мнемоника тоже в начале подписи).
args+=("")
args+=("new session"     "n" "command-prompt -p \"New session:\" \"new-session -A -s '%%'\"")
args+=("rename current"  "r" "command-prompt -I \"$cur\" -p \"Rename to:\" \"rename-session '%%'\"")
args+=("kill current"    "x" "confirm-before -p \"kill $cur? (y/n)\" kill-session")

# Быстрый возврат на предыдущую сессию (дублирует prefix+L).
args+=("")
args+=("last session"    "." "switch-client -l")

tmux display-menu -T "#[align=centre] sessions " "${args[@]}"
