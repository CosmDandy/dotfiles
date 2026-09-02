#!/usr/bin/env zsh
# One row per secret with its current state, for the picker to (re)load.
#
# Re-enters an interactive shell because the registry and the row renderer live
# there — the same reason run-job.zsh does. ~150ms, paid only when the list is
# rebuilt after a delivery.
#
# Usage: secret-rows.zsh <workspace-id>
emulate -L zsh
[[ -n $1 ]] || exit 1
zsh +m -ic "_dp_secret_rows ${(q)1}" < /dev/null 2>/dev/null
