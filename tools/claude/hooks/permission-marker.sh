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
#   Notification      set the marker when notification_type is permission_prompt,
#                     and raise a banner either way
#   StopFailure       banner only: the turn broke off
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

# The session's own name, so the banner says which one wants something. It lives in
# state.json next to the marker; falls back to the short id when the file has none.
session_name() {
    n=$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$dir/state.json" 2>/dev/null | head -1)
    [ -n "$n" ] || n="$short"
    # the classifier names sessions from the first prompt, and sometimes that is a
    # sentence; a banner title has room for about thirty characters before macOS
    # truncates it mid-word without a marker
    if [ "${#n}" -gt 28 ]; then
        n="$(printf '%s' "$n" | cut -c1-28)…"
    fi
    # osascript takes an AppleScript string literal: a quote or a backslash inside
    # it would end the argument early
    printf '%s' "$n" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# A banner is the only channel that reaches past the terminal: the indicator in the
# title is invisible the moment the window is not on screen. macOS only — inside a
# devcontainer there is no osascript, and the counters have to carry it alone.
# Where it came from, in the same terms the window title uses: the working
# directory's basename names the container (/workspaces/kvt-platform-main) as
# readily as it names a project on the Mac. hostname is useless here — inside a
# devcontainer it is the docker id, 697b6f3dc5bf.
origin() {
    d=$(field cwd)
    [ -n "$d" ] || d=$(sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$dir/state.json" 2>/dev/null | head -1)
    b=${d##*/}
    [ -n "$b" ] || b=$(hostname -s 2>/dev/null)
    printf '%s' "$b" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# notify <text> <sound>. Two sounds, and only two: Blow asks for attention, Basso
# says something broke. Everything else stays silent — a sound is for what needs
# doing, and the rest can be seen on the way back.
notify() {
    command -v osascript >/dev/null 2>&1 || return 0
    body=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
    osascript -e "display notification \"$body\" with title \"$(origin) · $(session_name)\" sound name \"$2\"" >/dev/null 2>&1 &
}

case "$(field hook_event_name)" in
    Notification)
        # every notification is worth a banner; only a permission request also
        # needs the marker, because only it changes what the counters show
        [ "$(field notification_type)" = permission_prompt ] && : >|"$marker"
        notify "$(field message)" Blow
        ;;
    StopFailure)
        # the turn did not finish: rare, and the only place a negative sound earns
        # its keep. PostToolUseFailure is deliberately not here — a failing tool call
        # happens on 5% of calls and the model simply retries.
        detail=$(field error_details)
        [ -n "$detail" ] || detail=$(field error)
        [ -n "$detail" ] || detail="ход не завершился"
        notify "$detail" Basso
        ;;
    PostToolBatch | PermissionDenied)
        [ -f "$marker" ] && rm -f "$marker"
        ;;
esac

exit 0
