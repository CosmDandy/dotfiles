#!/usr/bin/env python3
"""Claude session counters for the window title and for Claude's own statusline.

A session that stops to ask goes silent: hooks run without a controlling terminal,
so nothing rings, and the only trace is ~/.claude/jobs/<id>/state.json — read by
nothing outside Claude's own agents view.

Three states, and each needs BOTH fields of that file:

    running   tempo == active
    waiting   state == blocked and tempo != active
    approval  a marker file left by the Notification hook

`state` alone is the verdict on the last finished turn and stays put: a session
that asked something an hour ago and is working again still reads "blocked".
`tempo` alone loses the waiting ones entirely — the moment a turn ends it drops to
"idle" whether the session asked something or simply finished. Only the pair says
what is actually going on, which is why this is Python and not a grep: the two
values have to come from the same file.

Two outputs, because the two places answer different questions. The window title
asks "am I needed?" — waiting and approval only, no colour, since the system font
draws it. The statusline asks "what is going on?" — all three, coloured.

Scope is the machine it runs on: the Mac counts local sessions, a devcontainer the
ones inside it, an ssh host the ones there.

Usage: claude-sessions.py [full]
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


def counts(jobs_dir):
    running = waiting = approval = 0
    try:
        entries = sorted(os.scandir(jobs_dir), key=lambda e: e.name)
    except OSError:
        return 0, 0, 0

    for entry in entries:
        if not entry.is_dir():
            continue
        try:
            with open(os.path.join(entry.path, "state.json"), encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            continue

        tempo = data.get("tempo")
        state = data.get("state")

        # the marker outranks everything: a session waiting for permission is
        # waiting in the sharpest sense, and must not be counted twice
        if os.path.exists(os.path.join(entry.path, "awaiting-permission")):
            approval += 1
        elif tempo == "active":
            running += 1
        elif state == "blocked":
            waiting += 1

    return running, waiting, approval


def main():
    full = len(sys.argv) > 1 and sys.argv[1] == "full"
    running, waiting, approval = counts(
        os.path.join(os.path.expanduser("~"), ".claude", "jobs")
    )

    # Counts, not names, in both places. A name tells you which window to go to, but
    # it has to be read; a circle is taken in without reading, and the title is
    # narrow. Names live in the banner instead, which arrives once and is read once.
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
