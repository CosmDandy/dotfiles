#!/bin/sh
# PreToolUse Bash hook entry: settings.json calls this, not the binary directly.
#
# Lookup order: a binary next to this script (a local `go build -o claude-guard .`),
# then the profile (home.packages on Linux, systemPackages on the mac — both from
# packages.<system>.claude-guard in platform/nix/flake.nix).
#
# NOTE: fails CLOSED, unlike tools/claude/cli/wrapper.sh. A statusline that goes
# blank costs nothing; a guard that goes missing lets every command through — and a
# hook that exits 127 is a non-blocking error to Claude Code, i.e. an allow. So a
# missing binary denies with a reason that says how to fix it. On the mac that is
# also what happens in the ~11 s after login before /nix is mounted.
dir=$(dirname "$0")
bin="$dir/claude-guard"
[ -x "$bin" ] || bin=$(command -v claude-guard 2>/dev/null)
if [ -n "$bin" ] && [ -x "$bin" ]; then
  exec "$bin" "$@"
fi
cat >/dev/null
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"claude-guard binary not found (not built into the profile yet, or /nix not mounted). Run home-manager switch / darwin-rebuild switch, or go build -o claude-guard . in tools/claude/guard."}}'
