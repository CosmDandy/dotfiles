#!/usr/bin/env zsh
set -eu
export DOTFILES_DIR=${0:A:h:h:h}
local tmp=$(mktemp -d)
local sock=$tmp/tmux
trap 'tmux -S "$sock" kill-server 2>/dev/null || :; rm -rf -- "$tmp"' EXIT
export HOME=$tmp
mkdir -p "$HOME/.devpod/contexts/default/workspaces"
# Exercise fzf on a real tty; only the final provisioning step is replaced.
tmux -S "$sock" -f /dev/null new-session -d -x 160 -y 32 'zsh -fc '\''source "$DOTFILES_DIR/tools/zsh/conf.d/devpod.zsh"; _dp_new() { print -r -- "$1" > "$HOME/created"; }; dp'\'''
for i in {1..100}; do
  tmux -S "$sock" capture-pane -p | grep -Fq 'type a workspace name' && break
  sleep .05
done
tmux -S "$sock" capture-pane -p | grep -Fq 'type a workspace name'
tmux -S "$sock" send-keys -l first-workspace
tmux -S "$sock" send-keys C-n
for i in {1..100}; do [[ -f $tmp/created ]] && break; sleep .05; done
[[ $(< "$tmp/created") == first-workspace ]]
