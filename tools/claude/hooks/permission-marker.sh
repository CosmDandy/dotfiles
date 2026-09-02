#!/bin/sh
# Marks a session that is waiting for permission to use a tool, so the tmux status
# line and the window title can tell that apart from "finished a turn, wants an answer".
#
# Why a marker file at all: ~/.claude/jobs/<id>/state.json cannot express it. Its
# schema admits exactly active|idle|blocked, checked in the binary —
#   tempo: o.tempo==="active"||o.tempo==="idle"||o.tempo==="blocked" ? o.tempo : void 0
# — so a permission prompt and an ordinary question both land in "blocked". The
# distinction exists only in the hook payload, where Notification carries
# notification_type, and the value for a permission request is permission_prompt.
#
# Wired to three events, and reads which one it is from the payload:
#   Notification      set the marker when notification_type is permission_prompt
#   StopFailure       play the failure sound: the turn broke off
#   PostToolBatch     clear the marker — a tool ran, so permission was granted
#   PermissionDenied  clear it — refused, the session moves on without the tool
#
# Fails quietly by design: a hook that cannot mark anything must not break the turn.

set -u

payload=$(cat 2>/dev/null) || exit 0
[ -n "$payload" ] || exit 0

field() {
    printf '%s' "$payload" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

session=$(field session_id)
[ -n "$session" ] || exit 0

# The job directory is named by the first segment of the session id
short=$(printf '%s' "$session" | cut -c1-8)
dir="$HOME/.claude/jobs/$short"
[ -d "$dir" ] || exit 0

marker="$dir/awaiting-permission"

# NOTE: this hook used to raise macOS banners naming the session. Removed by choice:
# a popup on every question interrupted more than it helped, and noticing a waiting
# session two minutes later costs nothing — the counters in the window title already
# say who is waiting. Sound stays, but plays directly, without a notification to
# dismiss.

case "$(field hook_event_name)" in
    Notification)
        # No sound of its own: Claude Code sends a bell for this, Ghostty rings Blow,
        # and that reaches the Mac from inside a container too.
        [ "$(field notification_type)" = permission_prompt ] && : >|"$marker"
        ;;
    StopFailure)
        # No bell is sent for a broken turn, so this is the one place the hook makes
        # a sound itself. PostToolUseFailure deliberately stays silent — a tool call
        # fails on 5% of invocations and the model simply retries.
        [ -f /System/Library/Sounds/Basso.aiff ] &&
            afplay /System/Library/Sounds/Basso.aiff >/dev/null 2>&1 &
        ;;
    PostToolBatch | PermissionDenied)
        [ -f "$marker" ] && rm -f "$marker"
        ;;
esac

exit 0
