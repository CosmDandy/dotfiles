#!/bin/sh
# Point Claude Code's custom theme at the light or dark Solarized file and record
# the background for new shells. Called by tmux's client-{light,dark}-theme hooks
# (tools/tmux/.tmux.conf) and by _claude_theme_apply / term-theme in zsh.
# Usage: apply.sh light|dark
# NOTE: copied, not symlinked. Claude watches the themes directory and rereads what
# changed, which is what repaints a RUNNING session; a repointed symlink leaves the
# target's mtime untouched. Unchanged files are left alone so a hook that fires on
# every attach does not make every session reload its theme for nothing.
case $1 in
  light|dark) theme=$1 ;;
  *) echo "usage: apply.sh light|dark" >&2; exit 2 ;;
esac
dir=$(cd "$(dirname "$0")" && pwd) || exit 1
src=$dir/solarized-$theme.json
dst=$HOME/.claude/themes/solarized.json
[ -r "$src" ] || exit 1
mkdir -p "$HOME/.claude/themes" || exit 1
cmp -s "$src" "$dst" 2>/dev/null || cp -f "$src" "$dst"
# The cache .zshrc's _term_bg_is_dark reads, so fzf in a shell opened after the
# flip comes up in the right colours too.
cache=${XDG_CACHE_HOME:-$HOME/.cache}/zsh/term-bg
mkdir -p "$(dirname "$cache")" 2>/dev/null && printf '%s\n' "$theme" > "$cache"
exit 0
