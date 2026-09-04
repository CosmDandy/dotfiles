#!/usr/bin/env python3
"""Claude session counters for the window title and for Claude's own statusline.

A session that stops to ask goes silent: hooks run without a controlling terminal,
so nothing rings, and noticing it means looking at every window in turn.

The source is ~/.claude/sessions/<pid>.json — one file per live session, written by
Claude Code itself and covering interactive windows as well as background jobs.
~/.claude/jobs/ was the obvious candidate and is the wrong one: only background
tasks ever get a directory there, so every interactive window — the ones actually
worth pointing at — was invisible.

The two fields that matter are `status` and `waitingFor`, set together:

    if (waitingFor !== undefined) return {status:"waiting", waitingFor, ...}
    return {status: isLoading||delegatedActive ? "busy" : "idle", ...}

`waitingFor` names the kind of wait — "dialog open", "input needed", "goal
proposal", "sandbox request" — and falls back to "permission prompt", which is what
makes a permission request tellable from an ordinary question. Hence three states:

    running   status == busy
    waiting   status == waiting, or a background job gone idle (it finished and
              wants an answer; an idle interactive window is just a window)
    approval  waitingFor == "permission prompt"

Two outputs, because the two places answer different questions. The window title
asks "am I needed?" — waiting and approval only, no colour, since the system font
draws it. The statusline asks "what is going on?" — all three, coloured.

Scope is the machine it runs on: the Mac counts local sessions, a devcontainer the
ones inside it, an ssh host the ones there.

Usage: claude-sessions.py [full [session_id]]
"""

import json
import os
import sys

RUN_ICON = os.environ.get("CLAUDE_RUN_ICON", "◉")
WAIT_ICON = os.environ.get("CLAUDE_WAIT_ICON", "○")
APPROVE_ICON = os.environ.get("CLAUDE_APPROVE_ICON", "󰌾")

# Solarized: cyan for work in progress, yellow for "your turn", red for "cannot go
# on without you". All three hold on both the light and the dark variant.
RUN_COLOUR, WAIT_COLOUR, APPROVE_COLOUR = 37, 136, 160

PERMISSION = "permission prompt"


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except OSError:
        pass  # EPERM: someone else's process, so something is running under that pid
    return True


def counts(sessions_dir, self_id):
    running = waiting = approval = 0
    try:
        entries = sorted(os.scandir(sessions_dir), key=lambda e: e.name)
    except OSError:
        return 0, 0, 0

    for entry in entries:
        if not entry.name.endswith(".json"):
            continue
        try:
            with open(entry.path, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            continue

        # spare is a pre-warmed process waiting to be adopted, parked is a job put
        # aside — neither is a session anyone is waiting on. Stale files are rare
        # (Claude Code prunes its own) but a crash leaves one behind.
        if data.get("kind") not in ("interactive", "bg"):
            continue
        if data.get("spare") or data.get("parkedJobId") is not None:
            continue
        if data.get("sessionId") == self_id:
            continue
        pid = data.get("pid")
        if not isinstance(pid, int) or not alive(pid):
            continue

        status = data.get("status")
        if data.get("waitingFor") == PERMISSION:
            approval += 1
        elif status == "waiting":
            waiting += 1
        elif status == "busy":
            running += 1
        elif status == "idle" and data.get("kind") == "bg":
            waiting += 1

    return running, waiting, approval


def main():
    full = len(sys.argv) > 1 and sys.argv[1] == "full"
    # The session drawing the statusline is busy by definition; counting it would
    # print a permanent "1" that says nothing about anywhere else.
    self_id = sys.argv[2] if len(sys.argv) > 2 else None
    running, waiting, approval = counts(
        os.path.join(os.path.expanduser("~"), ".claude", "sessions"), self_id
    )

    # Counts, not names, in both places. A name tells you which window to go to, but
    # it has to be read; a circle is taken in without reading, and the title is
    # narrow.
    parts = [
        (WAIT_ICON, waiting, WAIT_COLOUR),
        (APPROVE_ICON, approval, APPROVE_COLOUR),
    ]
    if full:
        parts.insert(0, (RUN_ICON, running, RUN_COLOUR))

    out = []
    for icon, number, colour in parts:
        if number <= 0:
            continue
        piece = f"{icon} {number}"
        if full:
            piece = f"\x1b[38;5;{colour}m{piece}\x1b[0m"
        out.append(piece)

    if out:
        sys.stdout.write(" ".join(out))


if __name__ == "__main__":
    main()
