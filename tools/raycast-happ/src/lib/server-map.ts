import { LocalStorage } from "@raycast/api";

const KEY = "server-map";

/**
 * UUID → human name, learned by selecting a config and reading back what
 * became active.
 *
 * Happ encrypts every stored config, so this mapping cannot be read directly;
 * it has to be observed. It also does not survive a subscription refresh if
 * Happ recreates the config directories, which is why callers compare the
 * known UUID set against the current one.
 */
export type ServerMap = Record<string, string>;

export async function loadServerMap(): Promise<ServerMap> {
  const raw = await LocalStorage.getItem<string>(KEY);
  if (!raw) return {};
  try {
    return JSON.parse(raw) as ServerMap;
  } catch {
    return {};
  }
}

export async function saveServerMap(map: ServerMap): Promise<void> {
  await LocalStorage.setItem(KEY, JSON.stringify(map));
}

export async function rememberServer(
  configId: string,
  name: string,
): Promise<void> {
  const map = await loadServerMap();
  if (map[configId] === name) return;
  map[configId] = name;
  await saveServerMap(map);
}

export async function clearServerMap(): Promise<void> {
  await LocalStorage.removeItem(KEY);
}

/** UUIDs present on disk but not yet named. */
export function unknownIds(map: ServerMap, configIds: string[]): string[] {
  return configIds.filter((id) => !map[id]);
}

/** Names remembered for configs that no longer exist — a refreshed subscription. */
export function staleIds(map: ServerMap, configIds: string[]): string[] {
  const present = new Set(configIds);
  return Object.keys(map).filter((id) => !present.has(id));
}
