---
name: ops-metal
description: Bare-metal server management — BIOS and UEFI settings, IPMI/BMC/IMM access, Serial-over-LAN consoles, firmware updates, remote power control, boot order, PXE boot from the firmware side, sensors and event logs. Covers the IBM x3550 M3 homelab.
when_to_use: Any command against a BMC (ipmitool, racadm, redfishtool), or any request about a machine that is not reachable over the network. Triggers - «включи сервер», «выключи по IPMI», «зайди в BIOS», «нужна консоль», «SOL», «поменяй порядок загрузки», «не грузится», «не поднимается после ребута», «посмотри температуру / сенсоры», «обнови прошивку», IMM, iLO, iDRAC, x3550, out-of-band.
---

# Bare metal and BMC

## Nothing blind

The rule that matters most: **prove you have a console before you change anything that can
stop the machine from booting.** Order is always — console first, then power or boot or BIOS.

- Confirm SOL genuinely works: `ipmitool … sol info` AND actually see output from the
  machine. An `sol info` that returns settings proves configuration, not a working console.
- `chassis power soft` (ACPI shutdown) before `power reset` or `power off`. A hard cycle on a
  running OS risks the filesystem.
- `chassis bootdev pxe` is ONE-SHOT unless you pass `options=persistent`. Expecting it to
  stick is a classic way to lose an afternoon.
- Never `mc reset cold` while the BMC is the only way in — it drops every IPMI and SOL
  session and the controller takes minutes to return.
- Never flash firmware over the only path in, and never combine a firmware update with other
  operations. Component order and standby power matter; read the vendor's sequence first.

## Command hygiene

- Credentials via `-E` (environment) or `-f pwfile`, never `-P` on the command line — the
  password lands in shell history and in `ps` output for every user on the box.
- `-I lanplus` with cipher suite 3. Never cipher 0: it accepts any password.
- Keep the BMC network non-routable. IPMI RMCP+ carries decades-old crypto; where Redfish
  exists (HTTPS/JSON) prefer it, but first-generation IMM as on the x3550 M3 has no Redfish,
  so `ipmitool` is correct there.

## Useful reads before acting

```bash
ipmitool -I lanplus -H <bmc> -U <user> -E chassis status
ipmitool -I lanplus -H <bmc> -U <user> -E sol info
ipmitool -I lanplus -H <bmc> -U <user> -E sel list       # event log: what already went wrong
ipmitool -I lanplus -H <bmc> -U <user> -E sdr type temperature
ipmitool -I lanplus -H <bmc> -U <user> -E chassis bootparam get 5
```

Then, and only then:

```bash
ipmitool … sol activate                      # console; escape is ~.
ipmitool … chassis bootdev pxe options=persistent
ipmitool … chassis power soft
```

## Reporting

State what the machine actually showed, including the SEL entries you read. A power action
whose result you did not observe on the console is not a completed action.
