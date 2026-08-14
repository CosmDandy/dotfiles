import {
  Action,
  ActionPanel,
  Color,
  Icon,
  List,
  Toast,
  getPreferenceValues,
  showToast,
} from "@raycast/api";
import { useEffect, useState } from "react";
import {
  HappState,
  formatUptime,
  listConfigIds,
  readState,
  runShortcut,
  splitServerName,
} from "./lib/happ";
import { reportFailure } from "./lib/feedback";
import { ServerMap, loadServerMap, rememberServer } from "./lib/server-map";
import {
  SubscriptionInfo,
  SubscriptionServer,
  formatBytes,
  getSubscription,
} from "./lib/subscription";
import { pingAll } from "./lib/ping";
import RebuildServerMap from "./rebuild-server-map";

type Preferences = {
  subscriptionUrl?: string;
  shortcutSelect: string;
  shortcutToggle: string;
  shortcutPing: string;
};

/**
 * A row is a server as the subscription describes it, joined — when possible —
 * to the config UUID Happ needs in order to switch.
 *
 * The join is by name, and it is the weak link: the subscription knows names,
 * Happ knows UUIDs, and nothing carries both. The map fills in as servers are
 * used, or all at once via Rebuild Server Map.
 */
type Row = {
  key: string;
  name: string;
  location: string;
  transport?: string;
  configId?: string;
  host?: string;
  port?: number;
  latency?: number;
};

export default function Command() {
  const [loading, setLoading] = useState(true);
  const [state, setState] = useState<HappState | null>(null);
  const [rows, setRows] = useState<Row[]>([]);
  const [sub, setSub] = useState<SubscriptionInfo | undefined>();
  const [pinging, setPinging] = useState(false);

  const prefs = getPreferenceValues<Preferences>();

  function build(
    current: HappState,
    ids: string[],
    map: ServerMap,
    subscription?: SubscriptionInfo,
  ): Row[] {
    const idByName = new Map(
      Object.entries(map).map(([id, name]) => [name, id]),
    );

    if (subscription && subscription.servers.length > 0) {
      return subscription.servers.map((server: SubscriptionServer) => {
        const { location, transport } = splitServerName(server.name);
        return {
          key: server.name,
          name: server.name,
          location,
          transport,
          configId: idByName.get(server.name),
          host: server.host,
          port: server.port,
        };
      });
    }

    // No subscription: fall back to what Happ stores, where only UUIDs and the
    // active config's name are readable.
    return ids.map((id) => {
      const name = map[id] ?? id.slice(0, 8);
      const { location, transport } = splitServerName(name);
      return { key: id, name, location, transport, configId: id };
    });
  }

  async function refresh(forceSubscription = false) {
    setLoading(true);
    const [current, ids, map, subscription] = await Promise.all([
      readState(),
      listConfigIds(),
      loadServerMap(),
      getSubscription(prefs.subscriptionUrl, forceSubscription),
    ]);

    // Whatever is running names itself, so every visit teaches one more pair.
    if (current.configId && current.serverName) {
      await rememberServer(current.configId, current.serverName);
      map[current.configId] = current.serverName;
    }

    setState(current);
    setSub(subscription);
    setRows(build(current, ids, map, subscription));
    setLoading(false);
  }

  useEffect(() => {
    refresh();
  }, []);

  async function measure() {
    const targets = rows.filter(
      (r): r is Row & { host: string; port: number } =>
        r.host !== undefined && r.port !== undefined,
    );
    if (targets.length === 0) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Nothing to probe",
        message:
          "Latency needs the subscription URL — addresses are not stored in the clear",
      });
      return;
    }

    setPinging(true);
    const results = await pingAll(targets);
    setRows((previous) =>
      previous.map((row) =>
        row.host && row.port
          ? { ...row, latency: results.get(`${row.host}:${row.port}`) }
          : row,
      ),
    );
    setPinging(false);
  }

  async function connectTo(row: Row) {
    if (!row.configId) {
      await showToast({
        style: Toast.Style.Failure,
        title: "This server has no config ID yet",
        message: "Run Rebuild Server Map, or switch to it once inside Happ",
      });
      return;
    }

    const toast = await showToast({
      style: Toast.Style.Animated,
      title: `Switching to ${row.name}`,
    });
    try {
      await runShortcut(prefs.shortcutSelect, row.configId);
      await runShortcut(prefs.shortcutToggle, "true");
      toast.style = Toast.Style.Success;
      toast.title = `Connected to ${row.name}`;
      setTimeout(() => refresh(), 1500);
    } catch (error) {
      await toast.hide();
      await reportFailure(error, "switch servers");
    }
  }

  async function disconnect() {
    try {
      await runShortcut(prefs.shortcutToggle, "false");
      await showToast({ style: Toast.Style.Success, title: "Disconnected" });
      setTimeout(() => refresh(), 1000);
    } catch (error) {
      await reportFailure(error, "disconnect");
    }
  }

  async function pingActive() {
    try {
      const result = await runShortcut(prefs.shortcutPing);
      await showToast({
        style: Toast.Style.Success,
        title: result ? `Ping ${result}` : "Happ returned nothing",
      });
    } catch (error) {
      await reportFailure(error, "measure the connection");
    }
  }

  const groups = new Map<string, Row[]>();
  for (const row of rows) {
    const list = groups.get(row.location) ?? [];
    list.push(row);
    groups.set(row.location, list);
  }

  const quota =
    sub?.download !== undefined
      ? `${formatBytes(sub.download)}${sub.total ? ` of ${formatBytes(sub.total)}` : ""}`
      : undefined;

  return (
    <List
      isLoading={loading || pinging}
      searchBarPlaceholder="Search servers…"
      actions={
        <ActionPanel>
          <Action
            title="Measure Latency"
            icon={Icon.Gauge}
            onAction={measure}
          />
        </ActionPanel>
      }
    >
      {state && (
        <List.Section title={sub?.title ?? "Connection"}>
          <List.Item
            icon={{
              source: state.connected ? Icon.Bolt : Icon.BoltDisabled,
              tintColor: state.connected ? Color.Green : Color.SecondaryText,
            }}
            title={state.serverName ?? "No active config"}
            subtitle={
              state.connected
                ? `connected${formatUptime(state.connectedSince) ? ` · ${formatUptime(state.connectedSince)}` : ""}`
                : "disconnected"
            }
            accessories={[
              ...(quota ? [{ text: quota, tooltip: "Downloaded" }] : []),
              ...(state.tcpConnections
                ? [{ text: `${state.tcpConnections} tcp` }]
                : []),
            ]}
            actions={
              <ActionPanel>
                {state.connected && (
                  <Action
                    title="Disconnect"
                    icon={Icon.BoltDisabled}
                    onAction={disconnect}
                  />
                )}
                {state.connected && (
                  <Action
                    title="Ping Active"
                    icon={Icon.Gauge}
                    shortcut={{ modifiers: ["cmd"], key: "p" }}
                    onAction={pingActive}
                  />
                )}
                <Action
                  title="Measure Latency"
                  icon={Icon.Gauge}
                  shortcut={{ modifiers: ["cmd", "shift"], key: "p" }}
                  onAction={measure}
                />
                <Action
                  title="Refresh"
                  icon={Icon.ArrowClockwise}
                  shortcut={{ modifiers: ["cmd"], key: "r" }}
                  onAction={() => refresh(true)}
                />
              </ActionPanel>
            }
          />
        </List.Section>
      )}

      {[...groups.entries()].map(([location, list]) => (
        <List.Section
          key={location}
          title={location}
          subtitle={`${list.length}`}
        >
          {list.map((row) => {
            const active = row.configId
              ? row.configId === state?.configId
              : row.name === state?.serverName;
            return (
              <List.Item
                key={row.key}
                icon={
                  active
                    ? { source: Icon.CircleFilled, tintColor: Color.Green }
                    : row.configId
                      ? Icon.Circle
                      : Icon.QuestionMarkCircle
                }
                title={row.transport ?? row.name}
                accessories={[
                  ...(row.latency !== undefined
                    ? [{ text: `${row.latency} ms` }]
                    : []),
                  ...(active && state?.connected ? [{ text: "active" }] : []),
                ]}
                actions={
                  <ActionPanel>
                    <Action
                      title="Connect"
                      icon={Icon.Bolt}
                      onAction={() => connectTo(row)}
                    />
                    {state?.connected && (
                      <Action
                        title="Disconnect"
                        icon={Icon.BoltDisabled}
                        onAction={disconnect}
                      />
                    )}
                    <Action
                      title="Measure Latency"
                      icon={Icon.Gauge}
                      shortcut={{ modifiers: ["cmd", "shift"], key: "p" }}
                      onAction={measure}
                    />
                    <Action.Push
                      title="Rebuild Server Map"
                      icon={Icon.List}
                      target={<RebuildServerMap />}
                    />
                    <Action
                      title="Refresh"
                      icon={Icon.ArrowClockwise}
                      shortcut={{ modifiers: ["cmd"], key: "r" }}
                      onAction={() => refresh(true)}
                    />
                  </ActionPanel>
                }
              />
            );
          })}
        </List.Section>
      ))}

      <List.EmptyView
        icon={Icon.Globe}
        title="No servers"
        description={
          prefs.subscriptionUrl
            ? "The subscription returned nothing and Happ has no configs on disk."
            : "Add the subscription URL in preferences to see every server, or connect once in Happ."
        }
      />
    </List>
  );
}
