# Happ for Raycast

Control the [Happ](https://www.happ.su) VPN client from Raycast: toggle the
tunnel, switch servers, read connection state — without opening the app.

Local only. This extension never talks to a panel or an API; everything it knows
comes from Happ's own storage on this Mac.

## How it works

Happ exposes seven App Intents (`Metadata.appintents` inside the app bundle):
`ToggleVPN`, `ConnectVPN`, `DisconnectVPN`, `SelectServer`,
`CheckCurrentConnection`, `Refresh`, `ChangeServerPage`. The `happ://` URL
scheme covers subscription import only — nothing there connects, disconnects or
selects. So **actions go through Shortcuts**, which is the only documented path.

**State is read directly** from `group.su.ffg.happ.plist` in Happ's group
container: active config UUID, the full config JSON of the running connection
(with its human-readable `remarks`), connection timestamp, local proxy ports,
connection counters. Reading has no side effects, so status never disturbs the
tunnel.

Two things are worth knowing about the design:

**Connection state comes from the tunnel process, not from a flag.**
`isLibXrayRunXrayJsonRunning` looks like the obvious indicator and is not — it
was `false` while the tunnel was carrying traffic. The extension checks for the
`Tunnel.appex` network extension process instead.

**Server names have to be learned.** Every stored config under
`subscriptionConfigs/<subscription>/<uuid>/config.json` is encrypted, so the
UUIDs are visible but the names are not. The only place a name appears in the
clear is the *active* config. The extension therefore keeps a UUID → name map,
filled in two ways: passively, every time you look at the list (the running
server names itself), and actively via **Rebuild Server Map**, which selects
each config once and reads back what became active.

## Setup

1. Import the extension: Raycast → `Import Extension` → this folder.
2. Create five shortcuts in the Shortcuts app. Each is a single Happ action;
   the names below are the defaults and can be changed in the extension's
   preferences.

| Shortcut name | Happ action | Input |
|---|---|---|
| `Happ Toggle` | Toggle TUNNEL | Shortcut Input → `Is Turned On` |
| `Happ Connect` | Connect TUNNEL | — |
| `Happ Disconnect` | Disconnect TUNNEL | — |
| `Happ Select` | Select Server | Shortcut Input → `Selected config ID` |
| `Happ Refresh` | Refresh widget | — |
| `Happ Ping` | Ping | — |

For `Happ Toggle` and `Happ Select`, open the shortcut's settings and enable
**Accept input**, then wire *Shortcut Input* into the action's parameter — the
extension passes the value on stdin.

If a shortcut is missing, the extension says which one and offers to open
Shortcuts rather than failing silently.

## Commands

| Command | What it does |
|---|---|
| **Toggle VPN** | Connects or disconnects, whichever is the opposite of now |
| **Select Server** | Server list grouped by country flag, with the active one marked |
| **VPN Status** | Menu bar: current server, uptime, TCP connections |
| **Copy Proxy URL** | Local HTTP and SOCKS addresses — useful for `HTTPS_PROXY` in a container |
| **Open Log** | Opens the current Xray log |
| **Refresh Subscription** | Asks Happ to refresh |
| **Rebuild Server Map** | Learns which UUID is which server |

## About Rebuild Server Map

It starts with a probe: select one config *without* connecting and see whether
Happ republishes the active config anyway. If it does, the whole calibration is
silent and the tunnel is never touched. If it does not, naming every server
requires connecting to each in turn — the run says so before it starts, and the
original server is restored at the end.

The map is invalidated by a subscription refresh if Happ recreates its config
directories. The extension notices (remembered UUIDs that no longer exist) and
offers to rebuild.

## Limits

- Ping is available only for the active connection (`CheckCurrentConnection`),
  offered in the menu bar and as ⌘P in the server list. Per-server latency
  would need the addresses, and those are encrypted alongside the configs —
  there is nothing to probe an inactive server with.
- Shortcuts cannot be created programmatically. `shortcuts sign` rejects both
  XML and binary plists ("isn't in the correct format"), so the five wrappers
  are set up by hand once.
- Settings like fragmentation, mux and routing are readable but not writable —
  Happ owns that file and would overwrite anything written behind its back.
- Everything here relies on Happ's private storage layout, not on a public API.
  An update can move a key; commands degrade to "unknown" rather than crash.
