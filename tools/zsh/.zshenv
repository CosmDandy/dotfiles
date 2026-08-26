# Read by EVERY zsh, before anything else — so it stays two assignments and no
# side effects.
#
# Both lines exist to stop a SYSTEM rc file from running `compinit` before
# ~/.zshrc gets a word in. That global compinit has no cache flag and no dump of
# its own, so it walks the whole fpath on every interactive shell. Measured on
# this machine, first shell after a pause: 1342 ms with it, 38 ms without. Warm:
# 106 ms against 38.
#
# Our own compinit still runs — with its own dump, with -C when the dump is
# fresh, and deferred until after the first prompt. Nothing is lost by skipping
# the system one; the rest of what it does (history sizes, `bindkey -e`, the
# `suse` prompt) is overridden by ~/.zshrc anyway, and vi mode and starship are
# what we actually want.

# nix-darwin's /etc/zshrc checks this on its first line and returns.
NOSYSZSHRC=1

# Debian and Ubuntu — the devcontainers — use a different name and skip only the
# compinit block, which is the part that costs. Their /etc/zsh/zshrc documents
# it at the line above the call.
skip_global_compinit=1
