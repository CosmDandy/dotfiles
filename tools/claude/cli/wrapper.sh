#!/bin/sh
# Degrade-quietly wrapper for claude-cli: settings.json and .tmux.conf call
# this instead of the binary directly. On macOS /nix mounts ~11s after
# login, so anything launched early (a statusline render right after
# unlock, a tmux status tick before the store is up) must not point through
# the store and must not error where a statusline/title used to be — a
# missing binary here means silence and exit 0, not a visible failure.
bin="$(dirname "$0")/claude-cli"
[ -x "$bin" ] || exit 0
exec "$bin" "$@"
