#!/usr/bin/env bash
# PreToolUse: inject ops-domain discipline once per session per domain.
#
# Why a hook and not just a rule: path-scoped rules fire when Claude READS a file.
# Network diagnostics, BMC work and remote administration are commands, not files —
# no glob ever matches, so the knowledge would never load. This keys off the command
# itself and points at the right skill.
#
# Emits only additionalContext, never a permissionDecision — it must not interfere
# with pretooluse-guard.sh, which runs alongside it.
# NOTE: no `set -e` — grep returning 1 on "no match" must not kill the hook.
set -uo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[[ -n "$cmd" ]] || exit 0
sid="$(printf '%s' "$input" | jq -r '.session_id // "nosession"')"

state="${HOME}/.claude/.state/opsctx"
mkdir -p "$state" 2>/dev/null || exit 0
# latches are per session; drop stale ones so the directory does not grow forever
find "$state" -type f -mtime +7 -delete 2>/dev/null || true

# match only at command position — the same anchoring pretooluse-guard.sh uses, so a
# domain word quoted inside `git commit -m "..."` does not trigger anything.
CP='(^|[;&|]|&&|\|\|)[[:space:]]*'
at() { grep -Eq "${CP}$1" <<<"$cmd"; }

domain=""
at '(ssh|scp|rsync|ansible|ansible-playbook)\b'                  && domain=remote
at '(ip|tcpdump|ss|nft|iptables|dig|getent|resolvectl|mtr|bridge)\b' && domain=net
at '(ipmitool|racadm|redfishtool)\b'                             && domain=metal
at '(utmctl|limactl|virsh|virt-clone|virt-sysprep|qemu-img)\b'    && domain=vm
[[ -n "$domain" ]] || exit 0

latch="${state}/${sid}.${domain}"
[[ -e "$latch" ]] && exit 0
: >"$latch"

case "$domain" in
remote)
  msg='Ops domain: REMOTE (ssh). Load the ops-remote skill now. Non-negotiable: BatchMode=yes + ConnectTimeout + -T so a prompt fails fast instead of eating the tool timeout; reuse one connection (ControlMaster/ControlPath/ControlPersist); anything over ~45s runs detached under tmux/systemd-run and is polled, never in the foreground — the 45s tool clock only backgrounds the local ssh client, the remote job stays tied to that channel and dies on SIGHUP if it drops; back up any remote file before editing it in place; no sudo (the guard denies it) — ask the user to run privileged steps.' ;;
net)
  msg='Ops domain: NETWORK. Load the ops-net skill now. Non-negotiable: dump a baseline to a file first (ip -br a; ip r; ip n; ss -tulpn; nft list ruleset); read-only tools before any change; change ONE thing at a time and re-measure in the order link -> addr -> route -> neigh -> DNS -> firewall -> app; if the change touches the path you are connected through, arm a rollback BEFORE applying; check DNS with getent/resolvectl rather than dig alone; bound every capture (-nn, explicit BPF filter, -c N).' ;;
metal)
  msg='Ops domain: BARE-METAL / BMC. Load the ops-metal skill now. Non-negotiable: prove a live console (sol info AND actual output) BEFORE any power, boot-order or BIOS change; power soft before reset/off; bootdev is one-shot unless options=persistent; never mc reset cold while the BMC is your only path in; never flash firmware over that only path; pass credentials via -E or -f, never -P.' ;;
vm)
  msg='Ops domain: VM lifecycle. Load the ops-vm skill now. Non-negotiable: a clone is not usable until UUID, every MAC, /etc/machine-id, SSH host keys and the cloud-init instance-id are regenerated (virt-sysprep does all five); snapshot before risky changes; never boot a clone on the same L2 as its source before the MAC is changed.' ;;
esac

jq -nc --arg m "$msg" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
exit 0
