---
name: ops-net
description: Network work and diagnostics — network namespaces, bridges, veth, VLANs, routing, DHCP, PXE and TFTP boot, DNS resolution, MTU and MSS, firewall rules (nft/iptables), tcpdump captures.
when_to_use: Any connectivity symptom or network change. Triggers - «не работает сеть», «не пингуется», «не резолвится», «отваливается по таймауту», «работает через раз», «мелкие запросы проходят, большие висят», «почему медленно», «настрой мост / VLAN / netns», «PXE не грузится», «не выдаётся адрес по DHCP», no route to host, connection refused, intermittent packet loss, MTU issues.
---

# Network work

## Before touching anything

- Capture a baseline to a file, not to the conversation:
  `ip -br a; ip r; ip n; ss -tulpn; nft list ruleset` → `/tmp/net-before-$(date +%s)`.
  Without it you cannot prove what your change did, or undo it.
- If the change touches link, address, route, firewall or sshd on a host you reached over
  that same path, arm a rollback BEFORE applying:
  `systemd-run --on-active=120 --unit=rb /usr/local/bin/restore-net`, or `netplan try`.
  Disarm only after confirming connectivity. Applying first and checking after leaves nothing
  to check with.

## Ordering

Work the layers in order and re-measure after each step: link → address → route → neighbour
→ DNS → firewall → application. Jumping straight to firewall or DNS is the usual way to
lose an hour.

One change at a time, then re-measure. Batched changes make attribution impossible.
Independent read-only checks can run in parallel; this rule is about changes, not tool calls.

## Diagnostics that are easy to get wrong

- DNS: check with `getent hosts` or `resolvectl query`, not only `dig`. `dig` bypasses
  nsswitch and systemd-resolved, so it happily answers while the application cannot resolve.
- `tcpdump`: use `-nn`, an explicit BPF filter and a packet limit (`-c N`), even when
  saving to a file. `-w file` sets the destination, not a limit. Set a time limit too
  if the matching packets might never arrive.
- Symptom "small things work, large things hang" is a PMTU blackhole, not "the network is
  slow". Bisect with `ping -M do -s <size>`; MSS clamping is the practical fix, letting ICMP
  type 3 code 4 through is the correct one. Watch for `rp_filter` silently dropping return
  traffic on asymmetric paths.
- Prefer `ip` over `ifconfig`, and `ss` over `netstat` — the legacy tools misreport on modern
  kernels.
- For flapping, watch instead of polling: `ip monitor`, `nft monitor`,
  `journalctl -f -u systemd-networkd`, `mtr --report --json` for intermittent loss.

## Namespaces

- A network namespace does not require a privileged container:
  `unshare --user --map-root-user --net` works because `CAP_NET_ADMIN` is checked inside the
  user namespace that owns the netns. Host interfaces are not reachable that way, and
  `ip netns` (which bind-mounts into `/var/run/netns`) still wants real root — verify
  empirically for the topology at hand rather than assuming either way.
- Name veth ends after both sides (`veth-a-b`) — debugging a topology with `veth0`/`veth1`
  everywhere is guesswork.

## Validation

```bash
nft -c -f ruleset.nft          # parse without loading
sshd -t                        # config test before restarting sshd
netplan try                    # auto-reverts if connectivity is lost
ip -br a; ip r; ip n           # compact state
ss -tulpn                      # who listens where
```
