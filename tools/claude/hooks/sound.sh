#!/bin/sh
# One timbre per Claude Code state, so they are distinguishable without looking:
#   Blow  — an answer or permission is needed (Notification)
#   Basso — something failed (PostToolUseFailure, StopFailure)
#
# macOS only, and through afplay alone: it plays by itself, independent of bell-action and
# of which window is focused.
#
# NOTE: the BEL branch for containers was removed — Claude Code hooks run without a
# controlling terminal, so /dev/tty never opens, synchronously or otherwise. There is no
# sound from a container and cannot be; the branch was always silent while creating the
# impression that sound depended on focus.
set -u

snd="${1:-Glass}"
f="/System/Library/Sounds/${snd}.aiff"

if command -v afplay >/dev/null 2>&1 && [ -r "$f" ]; then
    afplay "$f" 2>/dev/null &
fi

exit 0
