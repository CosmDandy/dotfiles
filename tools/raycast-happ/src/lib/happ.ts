import { execFile } from "node:child_process";
import { readdir } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const run = promisify(execFile);

const GROUP = join(
  homedir(),
  "Library",
  "Group Containers",
  "group.su.ffg.happ",
);

export const PLIST = join(
  GROUP,
  "Library",
  "Preferences",
  "group.su.ffg.happ.plist",
);

const SUBSCRIPTION_ROOT = join(
  GROUP,
  "Library",
  "Application Support",
  "Xray",
  "subscriptionConfigs",
);

export const HAPP_APP = "/Applications/Happ.app";

/**
 * One key out of Happ's preferences.
 *
 * `plutil -extract` is used rather than parsing the whole file: the plist holds
 * a Date, which `-convert json` refuses to serialise, and pulling single keys
 * needs no plist parser in the bundle. A missing key is not an error here —
 * these keys are Happ's private storage, not an API, so any of them may vanish
 * in an update and the UI has to survive that.
 */
async function readKey(key: string): Promise<string | undefined> {
  try {
    const { stdout } = await run("/usr/bin/plutil", [
      "-extract",
      key,
      "raw",
      "-o",
      "-",
      PLIST,
    ]);
    const value = stdout.trim();
    return value.length > 0 ? value : undefined;
  } catch {
    return undefined;
  }
}

export type HappState = {
  /** Tunnel process is alive. See isTunnelUp() for why this is a process check. */
  connected: boolean;
  /** UUID of the selected config, the same value SelectServerIntent expects. */
  configId?: string;
  subscriptionId?: string;
  /** Human name of the active server, e.g. "🇸🇪 HHH-STO · gRPC". */
  serverName?: string;
  connectedSince?: Date;
  httpProxyPort?: string;
  socksProxyPort?: string;
  tcpConnections?: string;
  routingEnabled?: boolean;
  logFile?: string;
};

/**
 * Whether the tunnel is up.
 *
 * `isLibXrayRunXrayJsonRunning` looks like the obvious flag and is not: it was
 * false while the tunnel was demonstrably carrying traffic — it tracks the
 * JSON-config run mode, not the connection. The network extension process is
 * the honest signal.
 */
async function isTunnelUp(): Promise<boolean> {
  try {
    await run("/usr/bin/pgrep", [
      "-f",
      "Happ.app/Contents/PlugIns/Tunnel.appex",
    ]);
    return true;
  } catch {
    return false;
  }
}

export async function readState(): Promise<HappState> {
  const [
    connected,
    configId,
    subscriptionId,
    configJson,
    since,
    httpProxyPort,
    socksProxyPort,
    tcpConnections,
    routing,
    logFile,
  ] = await Promise.all([
    isTunnelUp(),
    readKey("XRAY_CURRENT"),
    readKey("XRAY_CURRENT_SUBSCRIPTION"),
    readKey("connectedConfigJson"),
    readKey("timerStartValue"),
    readKey("httpProxyPort"),
    // Happ's own spelling, not a typo on our side.
    readKey("sockstProxyPort"),
    readKey("tcpConnections"),
    readKey("XRAY_ROUTE_IS_ENABLED"),
    readKey("currentLogFileURL"),
  ]);

  return {
    connected,
    configId,
    subscriptionId,
    serverName: parseRemarks(configJson),
    connectedSince: since ? new Date(since) : undefined,
    httpProxyPort,
    socksProxyPort,
    tcpConnections,
    routingEnabled: routing === "true",
    logFile,
  };
}

/** The active config is stored as a JSON *string*; only `remarks` is of interest. */
function parseRemarks(configJson?: string): string | undefined {
  if (!configJson) return undefined;
  try {
    const parsed = JSON.parse(configJson) as { remarks?: string };
    return parsed.remarks;
  } catch {
    return undefined;
  }
}

/**
 * Config UUIDs of the active subscription, in filesystem order.
 *
 * Only the directory names are readable — every config.json inside is encrypted
 * (Happ stores them under its own key), so a name can only be learned by
 * selecting the config and reading back what became active.
 */
export async function listConfigIds(): Promise<string[]> {
  const subscriptionId = await readKey("XRAY_CURRENT_SUBSCRIPTION");
  if (!subscriptionId) return [];
  try {
    const entries = await readdir(join(SUBSCRIPTION_ROOT, subscriptionId), {
      withFileTypes: true,
    });
    return entries.filter((e) => e.isDirectory()).map((e) => e.name);
  } catch {
    return [];
  }
}

export class ShortcutMissingError extends Error {
  constructor(readonly shortcutName: string) {
    super(`Shortcut "${shortcutName}" not found`);
    this.name = "ShortcutMissingError";
  }
}

/** Shortcut names as they exist right now, used to tell "missing" from "failed". */
export async function listShortcuts(): Promise<string[]> {
  try {
    const { stdout } = await run("/usr/bin/shortcuts", ["list"]);
    return stdout
      .split("\n")
      .map((l) => l.trim())
      .filter(Boolean);
  } catch {
    return [];
  }
}

/**
 * Run a shortcut, optionally feeding it input.
 *
 * Shortcuts is the only documented way to reach Happ's App Intents: the happ://
 * scheme covers subscription import only, with nothing for connect, disconnect
 * or select.
 */
export async function runShortcut(
  name: string,
  input?: string,
): Promise<string> {
  const known = await listShortcuts();
  if (known.length > 0 && !known.includes(name)) {
    throw new ShortcutMissingError(name);
  }

  const args = ["run", name];
  if (input !== undefined) {
    args.push("--input", "-");
  }
  args.push("--output-path", "-");

  const child = run("/usr/bin/shortcuts", args);
  if (input !== undefined) {
    child.child.stdin?.end(input);
  }
  const { stdout } = await child;
  return stdout.trim();
}

export type ToggleShortcuts = {
  shortcutConnect: string;
  shortcutDisconnect: string;
  shortcutToggle?: string;
};

/**
 * Bring the tunnel up or down.
 *
 * Prefers separate Connect/Disconnect shortcuts because those actions take no
 * parameters: wrapping them is one drag and nothing else. `Toggle TUNNEL` does
 * the same job in a single shortcut, but only if its boolean is wired to
 * Shortcut Input — and a shortcut whose header still says "receive input from
 * Nowhere" silently ignores what it is given. So Toggle is used when the user
 * has set it up, and the simple pair otherwise.
 */
export async function setTunnel(
  desired: boolean,
  shortcuts: ToggleShortcuts,
): Promise<void> {
  const known = await listShortcuts();
  const toggle = shortcuts.shortcutToggle?.trim();

  if (toggle && known.includes(toggle)) {
    await runShortcut(toggle, desired ? "true" : "false");
    return;
  }

  await runShortcut(
    desired ? shortcuts.shortcutConnect : shortcuts.shortcutDisconnect,
  );
}

export function formatUptime(since?: Date): string | undefined {
  if (!since || Number.isNaN(since.getTime())) return undefined;
  const seconds = Math.floor((Date.now() - since.getTime()) / 1000);
  if (seconds < 0) return undefined;
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
}

/**
 * Split "🇸🇪 HHH-STO · gRPC" into the location and the transport.
 *
 * The middle dot is how the panel names servers, so the location groups rows
 * and the transport labels them — otherwise every row repeats the same city.
 * Names without a separator stay whole and become their own group, which is
 * what any other naming scheme degrades to.
 */
export function splitServerName(name: string): {
  location: string;
  transport?: string;
} {
  const parts = name.split(/\s*[·|]\s*/);
  if (parts.length < 2) return { location: name };
  const transport = parts.slice(1).join(" · ").trim();
  return { location: parts[0].trim(), transport: transport || undefined };
}
