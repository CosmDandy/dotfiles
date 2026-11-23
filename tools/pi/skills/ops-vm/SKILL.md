---
name: ops-vm
description: "Virtual machine lifecycle — UTM and Lima on macOS, golden images, cloning VMs, regenerating UUID and MAC, resetting machine-id and SSH host keys, snapshots, cloud-init and ignition, finding a VM's IP from DHCP leases."
when_to_use: "Creating, cloning or provisioning a VM, and any symptom of a clone still carrying its source's identity. Triggers - «подними виртуалку», «склонируй VM», «сделай из золотого образа», «какой IP у виртуалки», «не могу найти машину в сети», «клон получил тот же адрес», «ругается на host key», «cloud-init не отработал», «сделай снапшот», UTM, Lima, golden image, virt-sysprep."
---

# VM lifecycle

## A clone is not usable until five identities are reset

UUID and MAC are the obvious two. The three that get forgotten cause confusing failures
hours later:

1. **VM UUID** — hypervisor-level identity.
2. **All MAC addresses** — every interface, not just the first.
3. **`/etc/machine-id`** — `rm /etc/machine-id && systemd-machine-id-setup`. Left alone,
   journald and monitoring merge two hosts into one, and DHCPv6 hands out the same lease
   because the DUID derives from it.
4. **SSH host keys** — `rm /etc/ssh/ssh_host_* && ssh-keygen -A`. Otherwise every clone
   presents the same fingerprint and clients cannot tell a real MITM from a lazy clone.
5. **cloud-init instance-id** — `cloud-init clean --logs`, or the clone believes it is
   already provisioned and skips first-boot configuration entirely.

`virt-sysprep` does all of this in one pass where available; do it by hand only when it is
not.

Do not boot a clone on the same L2 segment as its source before the MAC is changed — two
identical MACs make the ARP table and any DHCP-lease lookup lie to you.

## Golden image discipline

- The golden image stays pristine: never work inside it, clone first. Take a snapshot before
  any change you might want to undo.
- Cloning by copy is faster with `cp -c` on APFS (copy-on-write) than a full byte copy.
- Record what the image contains and when it was built. An undated golden image becomes
  untrustworthy within months.

## Finding a fresh VM

- macOS hands leases from `/var/db/dhcpd_leases` — look the VM up by its NEW MAC, and be
  aware stale entries for the old MAC linger.
- Prefer a deterministic path when repeating: fixed MAC plus a DHCP reservation beats
  grepping leases every time.

## Provisioning

- cloud-init and ignition are validated before boot, not debugged after:
  `cloud-init schema --config-file user-data`.
- First boot is where provisioning fails silently. Read the logs
  (`cloud-init status --long`, `journalctl -u cloud-init`) rather than concluding from the
  fact that the VM answers ping.
