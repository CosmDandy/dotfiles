# Happ for Raycast

See and switch the [Happ](https://www.happ.su) VPN tunnel from Raycast: what is
connected, for how long, how every server responds — and connect or disconnect
without opening the app.

Local only. This extension never talks to a panel or an API; it reads Happ's own
storage on this Mac and, if you give it one, your subscription URL.

## What is possible, and what is not

Happ exposes seven App Intents, but only three of them are marked
`isDiscoverable: true` — `Connect TUNNEL`, `Disconnect TUNNEL`, `Toggle TUNNEL`.
The other four (`Select Server`, `Ping`, `Refresh widget`, `Change Server Page`)
are internal to the interactive widget: they never appear in the Shortcuts app,
and no automation can reach them.

**So the tunnel can be toggled from here; the server cannot be switched.**
Switching stays inside Happ, and every list here offers ⌘↵ to open it. If the
author ever flips that flag, one-click switching becomes possible without any
other change.

The `happ://` URL scheme does not help either — it covers subscription import
and nothing else.

## Where the data comes from

**Connection state** is read from `group.su.ffg.happ.plist` in Happ's group
container: active config UUID, the full config JSON of the running connection
(including its human-readable `remarks`), connection timestamp, local proxy
ports, connection counters. Reading has no side effects.

Two details worth knowing. Connection state comes from the `Tunnel.appex`
process, not from `isLibXrayRunXrayJsonRunning` — that flag was `false` while
the tunnel was demonstrably carrying traffic; it tracks the JSON-config run
mode. And server names cannot be read from disk at all: every stored config is
encrypted, and the only name in the clear belongs to whatever is active.

**The server list** therefore comes from the subscription URL, which is the one
place names, hosts and ports exist in the clear. It also carries the profile
title and the downloaded volume, both shown in the header row.

## Setup

1. Paste your subscription URL into the extension's preferences. Optional, but
   without it there is no server list at all. Stored in the Keychain, only read.
2. Create two shortcuts in the Shortcuts app. Each is one action dragged in and
   nothing else — no parameters, no input wiring:

| Shortcut name | Happ action |
|---|---|
| `Happ Connect` | Connect TUNNEL |
| `Happ Disconnect` | Disconnect TUNNEL |

   Any names work; set yours in the extension's preferences.

   `Toggle TUNNEL` would do both in one shortcut, but only if its `Is Turned On`
   field is wired to *Shortcut Input* — and while the shortcut's header still
   reads "receive input from Nowhere", it accepts the value and ignores it,
   silently. The parameterless pair avoids that trap entirely. If you do set up
   a working Toggle, name it in preferences and it takes precedence.

3. Import the extension: Raycast → `Import Extension` → this folder.

If the shortcut is missing, the extension names it and offers to open Shortcuts
rather than failing silently.

## Commands

| Command | What it does | Needs the shortcut |
|---|---|---|
| **VPN Status** | Menu bar: current server, uptime, TCP connections | only to toggle |
| **Toggle VPN** | Connects or disconnects | yes |
| **Servers** | Every server with latency, active one marked | no |
| **Copy Proxy URL** | Local HTTP and SOCKS addresses | no |
| **Open Log** | Opens the current Xray log | no |

## About latency

Two different measurements, and only one of them is available here.

`Measure Latency` (⌘P in the server list) opens a TCP connection to every
endpoint from the subscription — 27 probes take about 200 ms. That is the path
*to* the server, not the speed *through* the tunnel.

Hysteria2 servers carry traffic over QUIC, so their number means something
narrower: the port is reachable over TCP. Measured against a real subscription,
all twelve answer TCP even though none of them uses it — which is why those
rows are marked `UDP` rather than left to look like an ordinary result.

Happ's own `Ping` action, which measures the live connection properly, is one
of the four intents that never reach Shortcuts.

## Limits

- Switching servers is not automatable (see above).
- Settings like fragmentation, mux and routing are readable but not writable —
  Happ owns that file and would overwrite anything written behind its back.
- Everything here relies on Happ's private storage layout, not a public API.
  An update can move a key; commands degrade to "unknown" rather than crash.
