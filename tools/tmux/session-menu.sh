#!/usr/bin/env bash
# Dynamic session menu for prefix+s: builds a tmux display-menu from the live session list.
# Names are generated from the directory, so nothing can be hardcoded.
# NOTE: tmux prints the hotkey (the item's third argument) itself, in brackets on the right
# — it must not be duplicated in the label.
set -eu

cur="$(tmux display-message -p '#S')"

args=()
i=0
while IFS= read -r name; do
  i=$((i + 1))

  # a dot marks the current session
  mark=""
  [ "$name" = "$cur" ] && mark=" ●"

  # NOTE: the hotkey is an ordinal — digits never collide whatever the session names are,
  # unlike first letters.
  args+=("$name$mark" "$i" "switch-client -t \"$name\"")
done < <(tmux list-sessions -F '#{session_name}' | sort)

# session actions
args+=("")
args+=("new session"     "n" "command-prompt -p \"New session:\" \"new-session -A -s '%%'\"")
args+=("rename current"  "r" "command-prompt -I \"$cur\" -p \"Rename to:\" \"rename-session '%%'\"")
args+=("kill current"    "x" "confirm-before -p \"kill $cur? (y/n)\" kill-session")

# quick jump back (same as prefix+L)
args+=("")
args+=("last session"    "." "switch-client -l")

tmux display-menu -T "#[align=centre] sessions " "${args[@]}"
