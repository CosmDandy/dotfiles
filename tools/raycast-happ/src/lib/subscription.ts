import { LocalStorage } from "@raycast/api";

/**
 * The subscription is the only place server names, addresses and ports exist
 * in the clear: Happ encrypts everything it stores locally. Fetching it gives
 * the full list without connecting to anything, and — because addresses come
 * with it — makes per-server latency possible at all.
 */

export type SubscriptionServer = {
  /** Name as shown by the panel, e.g. "🇸🇪 HHH-STO · Vision". */
  name: string;
  protocol: string;
  host: string;
  port: number;
};

export type SubscriptionInfo = {
  /** From the profile-title header, base64 or plain. */
  title?: string;
  /** Bytes downloaded, from subscription-userinfo. */
  download?: number;
  /** Total quota in bytes; 0 in the header means unlimited. */
  total?: number;
  /** Unix seconds; 0 means never. */
  expire?: number;
  supportUrl?: string;
  servers: SubscriptionServer[];
  fetchedAt: number;
};

const CACHE_KEY = "subscription-cache";
/** profile-update-interval is given in days; an hour is polite enough here. */
const TTL_MS = 60 * 60 * 1000;

/**
 * Some panels reject unknown clients, so identify as the app whose data this is.
 * (A urllib-style agent is a known 403 on this kind of endpoint.)
 */
const USER_AGENT = "Happ/5.5.0 (macOS; Raycast)";

/** Control characters, which decoded text should not contain. */
// eslint-disable-next-line no-control-regex
const CONTROL_CHARS = /[\u0000-\u0008\u000e-\u001f]/;

/**
 * Headers arrive either plain or prefixed with "base64:", and the body of a
 * subscription is usually base64 with no marker at all.
 *
 * Base64 never throws on garbage — it returns mojibake — so an unmarked value
 * is accepted only once the result looks like text.
 */
function decodeMaybeBase64(value: string): string {
  const marked = value.startsWith("base64:");
  const payload = marked ? value.slice("base64:".length) : value;
  if (!marked && !/^[A-Za-z0-9+/=\s]+$/.test(payload)) return value;
  try {
    const decoded = Buffer.from(payload, "base64").toString("utf8");
    if (marked) return decoded;
    return decoded.length > 0 && !CONTROL_CHARS.test(decoded) ? decoded : value;
  } catch {
    return value;
  }
}

/**
 * Parse one proxy URL.
 *
 * vless://uuid@host:port?params#name — the fragment is the display name.
 * hysteria2 shares the shape. Ports can be a range for hop configs ("2080-2090"),
 * where the first one is what a probe should use.
 */
function parseServerLine(line: string): SubscriptionServer | undefined {
  const match = line.match(/^([a-z0-9]+):\/\/([^#]*)(?:#(.*))?$/i);
  if (!match) return undefined;
  const [, protocol, body, rawName] = match;

  const authority = body.split("?")[0];
  const hostPart = authority.includes("@")
    ? authority.slice(authority.lastIndexOf("@") + 1)
    : authority;

  const portMatch = hostPart.match(/^(.*?):(\d+)(?:-\d+)?\/?$/);
  if (!portMatch) return undefined;

  const name = rawName ? decodeURIComponent(rawName) : hostPart;
  return {
    name,
    protocol,
    host: portMatch[1],
    port: Number(portMatch[2]),
  };
}

function parseUserInfo(header?: string): Partial<SubscriptionInfo> {
  if (!header) return {};
  const out: Record<string, number> = {};
  for (const part of header.split(";")) {
    const [key, value] = part.split("=").map((s) => s.trim());
    if (key && value !== undefined && !Number.isNaN(Number(value))) {
      out[key] = Number(value);
    }
  }
  return { download: out.download, total: out.total, expire: out.expire };
}

export async function fetchSubscription(
  url: string,
): Promise<SubscriptionInfo> {
  const response = await fetch(url, {
    headers: { "User-Agent": USER_AGENT },
  });
  if (!response.ok) {
    throw new Error(`Subscription returned ${response.status}`);
  }

  const body = await response.text();
  const decoded = decodeMaybeBase64(body.trim());

  const servers = decoded
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean)
    .map(parseServerLine)
    .filter((s): s is SubscriptionServer => s !== undefined);

  const titleHeader = response.headers.get("profile-title") ?? undefined;

  const info: SubscriptionInfo = {
    title: titleHeader ? decodeMaybeBase64(titleHeader) : undefined,
    supportUrl: response.headers.get("support-url") ?? undefined,
    ...parseUserInfo(
      response.headers.get("subscription-userinfo") ?? undefined,
    ),
    servers,
    fetchedAt: Date.now(),
  };

  await LocalStorage.setItem(CACHE_KEY, JSON.stringify(info));
  return info;
}

export async function loadCachedSubscription(): Promise<
  SubscriptionInfo | undefined
> {
  const raw = await LocalStorage.getItem<string>(CACHE_KEY);
  if (!raw) return undefined;
  try {
    return JSON.parse(raw) as SubscriptionInfo;
  } catch {
    return undefined;
  }
}

/** Cached copy when fresh, network otherwise; cache also covers being offline. */
export async function getSubscription(
  url?: string,
  force = false,
): Promise<SubscriptionInfo | undefined> {
  const cached = await loadCachedSubscription();
  if (!url) return cached;
  if (!force && cached && Date.now() - cached.fetchedAt < TTL_MS) return cached;
  try {
    return await fetchSubscription(url);
  } catch {
    return cached;
  }
}

export function formatBytes(bytes?: number): string | undefined {
  if (bytes === undefined) return undefined;
  const units = ["B", "KB", "MB", "GB", "TB"];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(value >= 100 || unit === 0 ? 0 : 1)} ${units[unit]}`;
}
