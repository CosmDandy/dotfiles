#!/usr/bin/env bash
set -euo pipefail

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$*" >&2; }

dry_run=false
if [[ ${1:-} == --dry-run ]]; then
  dry_run=true
  shift
fi
if (( $# > 1 )); then
  log 'Usage: knowledge-autopull [--dry-run] [vault]'
  exit 2
fi

vault=${1:-$HOME/knowledge}
git_vault() { /usr/bin/git -C "$vault" -c core.hooksPath=/dev/null -c submodule.recurse=false "$@"; }

if [[ ! -e "$vault/.git" ]] || [[ $(git_vault symbolic-ref --quiet HEAD) != refs/heads/master ]]; then
  log 'Skipped: vault is not on master.'
  exit 0
fi
for state in MERGE_HEAD REBASE_HEAD rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD sequencer; do
  if [[ -e $(git_vault rev-parse --path-format=absolute --git-path "$state") ]]; then
    log "Skipped: a Git operation is in progress ($state)."
    exit 0
  fi
done

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-'/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=5 -T'}
if ! git_vault fetch --quiet --no-tags --no-recurse-submodules --no-auto-maintenance \
    origin '+refs/heads/master:refs/remotes/origin/master'; then
  log 'Fetch failed; will retry at the next run.'
  exit 1
fi

head=$(git_vault rev-parse HEAD)
target=$(git_vault rev-parse refs/remotes/origin/master)
if git_vault merge-base --is-ancestor "$target" "$head"; then
  if "$dry_run"; then log 'Dry run: no incoming changes.'; fi
  exit 0
fi
if ! git_vault merge-base --is-ancestor "$head" "$target"; then
  log 'Skipped: master and origin/master have diverged.'
  exit 1
fi

if "$dry_run"; then
  git_vault read-tree --dry-run -m -u "$head" "$target"
  log 'Dry run: fast-forward preview passed; merge will also check ignored files.'
  exit 0
fi
if ! git_vault merge --quiet --ff-only --no-autostash --no-overwrite-ignore "$target"; then
  log 'Update refused by Git; will retry at the next run.'
  exit 1
fi
log "Updated ${head:0:12} -> ${target:0:12}."
