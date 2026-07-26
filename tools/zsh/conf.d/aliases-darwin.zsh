# Алиасы, полезные только на macOS: Downloads есть только там, cleanup-mac.sh
# и Arc — mac-only, ghostty — локальный терминал мака.
[[ "$OSTYPE" == darwin* ]] || return

alias dl='cd ~/Downloads'

alias clean='bash ~/.dotfiles/automation/launchd/scripts/cleanup-mac.sh'
# Обновиться и сразу прибраться. Отдельной связкой, а НЕ чисткой внутри updm:
# всё, что порождает само обновление (brew, Caskroom, поколения nix), уже чистится
# в onActivation/postActivation и хвосте updm. cleanup-mac.sh сносит кэши от
# повседневной работы — кэш сборки Go, pip, прогретый код VS Code, — и терять их
# в начале рабочей сессии незачем. Так решение остаётся за тем, кто запускает.
# Arc теряет привязку Space → Chrome-профиль после переустановки .app: рабочий
# Space открывается на личном профиле, без расширений и паролей. Кнопки сменить
# профиль у Space в интерфейсе нет — правим состояние. `arcs status` покажет
# расхождение, `arcs apply` починит (Arc должен быть закрыт).
alias arcs='python3 ~/.dotfiles/automation/arc/arc-profiles.py'

alias ttyh='ghostty +list-keybinds --default'
