# Aliases that only make sense on macOS.
[[ "$OSTYPE" == darwin* ]] || return

alias dl='cd ~/Downloads'

alias clean='bash ~/.dotfiles/automation/launchd/scripts/cleanup-mac.sh'
# NOTE: cleanup stays a separate command rather than a tail of upd; cleanup-mac.sh
# drops caches from everyday work (Go build, pip, warmed VS Code) that are not worth losing
# at the start of a session.

alias ttyh='ghostty +list-keybinds --default'
