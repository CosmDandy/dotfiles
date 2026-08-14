/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {
  /** Subscription URL - Optional but recommended. The same subscription link Happ uses. It is the only place server names, addresses and ports exist in the clear, so it gives the full list without calibration and makes per-server latency possible. Stored in the Keychain. */
  "subscriptionUrl"?: string,
  /** Connect Shortcut - Shortcut wrapping Happ's Connect TUNNEL action. It takes no parameters — one action and nothing else. */
  "shortcutConnect": string,
  /** Disconnect Shortcut - Shortcut wrapping Disconnect TUNNEL. Also parameterless. */
  "shortcutDisconnect": string,
  /** Toggle Shortcut (optional) - Optional single shortcut wrapping Toggle TUNNEL. Used only if it exists and its Is Turned On field is wired to Shortcut Input; otherwise the Connect/Disconnect pair is used. */
  "shortcutToggle": string
}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `toggle-vpn` command */
  export type ToggleVpn = ExtensionPreferences & {}
  /** Preferences accessible in the `select-server` command */
  export type SelectServer = ExtensionPreferences & {}
  /** Preferences accessible in the `vpn-status` command */
  export type VpnStatus = ExtensionPreferences & {}
  /** Preferences accessible in the `copy-proxy-url` command */
  export type CopyProxyUrl = ExtensionPreferences & {}
  /** Preferences accessible in the `open-log` command */
  export type OpenLog = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `toggle-vpn` command */
  export type ToggleVpn = {}
  /** Arguments passed to the `select-server` command */
  export type SelectServer = {}
  /** Arguments passed to the `vpn-status` command */
  export type VpnStatus = {}
  /** Arguments passed to the `copy-proxy-url` command */
  export type CopyProxyUrl = {}
  /** Arguments passed to the `open-log` command */
  export type OpenLog = {}
}

