/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {
  /** Toggle Shortcut - Name of the shortcut wrapping Happ's Toggle TUNNEL action. It must accept input — the extension passes true to connect and false to disconnect, so this one shortcut covers both. */
  "shortcutToggle": string,
  /** Select Server Shortcut - Name of the shortcut wrapping Select Server. It must accept the config ID as its input. */
  "shortcutSelect": string,
  /** Refresh Shortcut - Optional. Shortcut wrapping Refresh widget. */
  "shortcutRefresh": string,
  /** Ping Shortcut - Optional. Shortcut wrapping Ping. Only the active connection can be measured. */
  "shortcutPing": string
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
  /** Preferences accessible in the `refresh-subscription` command */
  export type RefreshSubscription = ExtensionPreferences & {}
  /** Preferences accessible in the `rebuild-server-map` command */
  export type RebuildServerMap = ExtensionPreferences & {}
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
  /** Arguments passed to the `refresh-subscription` command */
  export type RefreshSubscription = {}
  /** Arguments passed to the `rebuild-server-map` command */
  export type RebuildServerMap = {}
}

