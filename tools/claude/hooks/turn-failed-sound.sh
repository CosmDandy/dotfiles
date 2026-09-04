#!/bin/sh
# Plays a sound when a turn breaks off, which is the one event nothing else signals.
#
# Everything else here is deliberately silent. A permission prompt already rings:
# Claude Code sends a bell, Ghostty answers with Blow, and that reaches the Mac from
# inside a container too. PostToolUseFailure stays quiet as well — a tool call fails
# on some 5% of invocations and the model simply retries.
#
# This hook used to mark a session awaiting permission, so the window title could
# tell that apart from an ordinary question. That marker is gone: the state is in
# ~/.claude/sessions/<pid>.json, where status is busy|idle|waiting and waitingFor
# defaults to "permission prompt" — Claude Code draws the distinction itself, and
# claude-sessions.py reads it straight from there.
#
# Fails quietly by design: a hook that cannot make a sound must not break the turn.

set -u

[ -f /System/Library/Sounds/Basso.aiff ] || exit 0
afplay /System/Library/Sounds/Basso.aiff >/dev/null 2>&1 &

exit 0
