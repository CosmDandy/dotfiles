#!/bin/sh
# Degrade-quietly wrapper for claude-cli: settings.json and .tmux.conf call
# this instead of the binary directly. On macOS /nix mounts ~11s after
# login, so anything launched early (a statusline render right after
# unlock, a tmux status tick before the store is up) must not point through
# the store and must not error where a statusline/title used to be — a
# missing binary here means silence and exit 0, not a visible failure.
#
# Lookup order: a binary next to this script (a local `go build`), then the
# profile (home.packages on Linux, systemPackages on the mac — both from
# packages.<system>.claude-cli in platform/nix/flake.nix). Nothing else
# puts one here, so without the profile there is no statusline: check with
# `command -v claude-cli`.
bin="$(dirname "$0")/claude-cli"
[ -x "$bin" ] || bin="$(command -v claude-cli 2>/dev/null)"
[ -n "$bin" ] && [ -x "$bin" ] || exit 0
exec "$bin" "$@"
