---
name: ops-remote
description: Running commands on remote hosts over SSH — server setup, package installs, service restarts, remote file edits, ansible runs, long-running remote operations, copying files with scp/rsync.
when_to_use: Any command that targets another machine — ssh, scp, rsync, ansible-playbook — or any request phrased as work "on the server". Triggers - «зайди на сервер», «проверь на кластере», «выполни по ssh», «поставь пакет на хосте», «перезапусти сервис на», «скопируй на сервер», «посмотри логи на», ssh into, on the remote box, deploy to that host.
---

# Remote work over SSH

## Non-negotiable

- Every ssh invocation: `ssh -o BatchMode=yes -o ConnectTimeout=5 -T host …`.
  `BatchMode=yes` disables password prompts AND host-key confirmation, so the command fails
  fast instead of silently consuming the whole tool timeout waiting on a prompt you cannot
  answer. `-T` avoids allocating a TTY that nothing reads.
- Never run a command that can turn interactive: `apt`/`dnf` without `-y`, anything that may
  open an editor, `passwd`, a first-run wizard.
- Anything that may exceed ~45 seconds — package upgrades, `dd`, image writes, firmware,
  `talosctl upgrade` — starts detached and gets polled:
  `ssh host 'tmux new -d -s job "…"'` or `systemd-run --unit=job …`, then poll for status.
  At 45s the tool backgrounds the local ssh client rather than killing it, so the remote
  work does keep running — but only while that channel lives. Stop the task, drop the link
  or end the session and the remote job takes SIGHUP mid-write. Detaching on the remote side
  is what makes it survive; the foreground is never the answer here.
- No `sudo`: the PreToolUse guard denies it. Ask the user to run privileged steps, or use a
  path that does not need elevation.
- Never edit a remote file in place without a backup first:
  `cp -a /etc/thing /etc/thing.bak-$(date +%s)`. That includes `sed -i` and `>` redirects.

## In a dev container or behind a jump host

Read out of the transcripts — every one of these cost turns more than once.

- **Credentials do not travel with you.** `gh` and git inside a devcontainer are usually
  unauthenticated even when they work fine on the host. Run `gh auth status` before a
  series of `gh` calls, not after the first one fails.
- **`ssh -A` reaches the first hop, not the second.** Before relying on your identity
  further down a ProxyJump chain, check `ssh-add -l` on the intermediate node.
- **Take the process name from `pgrep`, not from what you think you launched.**
  `pkill -f site.yml` misses `ansible-playbook-wrapped`; the usual outcome is three
  wasted attempts against a process that was never named that.
- **`git commit` can outlast the 45s clock** when the repo has pre-commit hooks or
  signing. Start it with `run_in_background` instead of discovering that at the timeout.
- **The image is not this machine.** Packages present locally — PyYAML is the recurring
  one — may simply be absent. Check the import before building a script around it.

## Efficiency

- Reuse one connection across the session — an agent makes dozens of ssh calls:
  `-o ControlMaster=auto -o ControlPath=~/.ssh/cm-%C -o ControlPersist=10m`.
  Without it every call is a fresh key exchange, and every call re-prompts if the key
  requires confirmation.
- Prefer one ssh invocation with a small script over many round trips.
- `rsync -a --dry-run` before the real copy when the destination already has content.

## Discipline

- Read state before changing it, and capture what you read to a file when the change is not
  trivially reversible.
- One change at a time, then re-measure. Batched changes make attribution impossible.
- After the change, verify from the same vantage point the user cares about — a service that
  answers on localhost but not from outside is not fixed.
- Report what you actually ran and what came back. Never summarise a remote result you did
  not read.

## Safety for agent access

- A dedicated key for automated access, constrained in `authorized_keys`
  (`restrict,from="…",command="…"`), is revocable and auditable independently of the
  human's key. Prefer that over reusing the interactive key when setting up unattended work.
