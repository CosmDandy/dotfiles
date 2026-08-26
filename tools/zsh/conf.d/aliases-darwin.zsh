# Aliases that only make sense on macOS.
[[ "$OSTYPE" == darwin* ]] || return

alias dl='cd ~/Downloads'

alias clean='bash ~/.dotfiles/automation/launchd/scripts/cleanup-mac.sh'
# NOTE: cleanup stays a separate command rather than a tail of updm — everything the
# update itself produces is already cleaned by brew and the nix GC, while cleanup-mac.sh
# drops caches from everyday work (Go build, pip, warmed VS Code) that are not worth losing
# at the start of a session.
# Arc loses the Space → Chrome-profile link after the .app is reinstalled, and there is no
# UI button to restore it. `arcs status` shows the drift, `arcs apply` fixes it (Arc must
# be closed).
alias arcs='python3 ~/.dotfiles/automation/arc/arc-profiles.py'

alias ttyh='ghostty +list-keybinds --default'
