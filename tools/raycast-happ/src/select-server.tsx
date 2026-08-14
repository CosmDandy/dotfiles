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
  HAPP_APP,
  HappState,
  formatUptime,
  readState,
  setTunnel,
  splitServerName,
} from "./lib/happ";
import { reportFailure } from "./lib/feedback";
import { rememberServer } from "./lib/server-map";
import {
  SubscriptionInfo,
  formatBytes,
  getSubscription,
} from "./lib/subscription";
import { pingAll } from "./lib/ping";

type Preferences = {
  subscriptionUrl?: string;
  shortcutConnect: string;
  shortcutDisconnect: string;
  shortcutToggle?: string;
};

type Row = {
  name: string;
  location: string;
  transport?: string;
  protocol: string;
  host: string;
  port: number;
  latency?: number;
};

/**
 * Servers with their latency, and which one is live.
 *
 * There is deliberately no "connect to this one" action: Happ marks
 * SelectServerIntent as `isDiscoverable: false`, so it never reaches Shortcuts
 * and no automation can reach it either. Switching stays inside the app —
 * ⌘↵ opens it. What this list does give is the comparison the app itself
 * does not: every endpoint probed at once.
 */
export default function Command() {
  const [loading, setLoading] = useState(true);
  const [state, setState] = useState<HappState | null>(null);
  const [rows, setRows] = useState<Row[]>([]);
  const [sub, setSub] = useState<SubscriptionInfo | undefined>();
  const [pinging, setPinging] = useState(false);

  const prefs = getPreferenceValues<Preferences>();

  async function refresh(forceSubscription = false) {
    setLoading(true);
    const [current, subscription] = await Promise.all([
      readState(),
      getSubscription(prefs.subscriptionUrl, forceSubscription),
    ]);

    if (current.configId && current.serverName) {
      await rememberServer(current.configId, current.serverName);
    }

    setState(current);
    setSub(subscription);
    setRows(
      (subscription?.servers ?? []).map((server) => {
        const { location, transport } = splitServerName(server.name);
        return {
          name: server.name,
          location,
          transport,
          protocol: server.protocol,
          host: server.host,
          port: server.port,
        };
      }),
    );
    setLoading(false);
  }

  useEffect(() => {
    refresh();
  }, []);

  async function measure() {
    if (rows.length === 0) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Nothing to probe",
        message: "Add the subscription URL in preferences",
      });
      return;
    }
    setPinging(true);
    const results = await pingAll(rows);
    setRows((previous) =>
      previous.map((row) => ({
        ...row,
        latency: results.get(`${row.host}:${row.port}`),
      })),
    );
    setPinging(false);
  }

  async function toggle() {
    try {
      await setTunnel(!state?.connected, prefs);
      await showToast({
        style: Toast.Style.Success,
        title: state?.connected ? "Disconnecting" : "Connecting",
      });
      setTimeout(() => refresh(), 1500);
    } catch (error) {
      await reportFailure(error, "toggle the tunnel");
    }
  }

  const groups = new Map<string, Row[]>();
  for (const row of rows) {
    const list = groups.get(row.location) ?? [];
    list.push(row);
    groups.set(row.location, list);
  }

  const quota =
    sub?.download !== undefined ? formatBytes(sub.download) : undefined;

  return (
    <List isLoading={loading || pinging} searchBarPlaceholder="Search servers…">
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
                <Action
                  title={state.connected ? "Disconnect" : "Connect"}
                  icon={state.connected ? Icon.BoltDisabled : Icon.Bolt}
                  onAction={toggle}
                />
                <Action
                  title="Measure Latency"
                  icon={Icon.Gauge}
                  shortcut={{ modifiers: ["cmd"], key: "p" }}
                  onAction={measure}
                />
                <Action.Open
                  title="Switch Server in Happ"
                  icon={Icon.AppWindow}
                  target={HAPP_APP}
                  shortcut={{ modifiers: ["cmd"], key: "return" }}
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
            const active = row.name === state?.serverName;
            return (
              <List.Item
                key={row.name}
                icon={
                  active
                    ? { source: Icon.CircleFilled, tintColor: Color.Green }
                    : Icon.Circle
                }
                title={row.transport ?? row.name}
                accessories={[
                  ...(row.latency !== undefined
                    ? [
                        {
                          text: `${row.latency} ms`,
                          tooltip: "TCP handshake to the endpoint",
                        },
                      ]
                    : []),
                  // Hysteria2 carries traffic over QUIC, so the TCP number next
                  // to it says the port is reachable — not that the transport
                  // works. Measured: all twelve answer TCP anyway, which is
                  // exactly why the distinction has to be visible.
                  ...(row.protocol.startsWith("hysteria")
                    ? [
                        {
                          text: "UDP",
                          tooltip:
                            "Carries traffic over QUIC; the number is a TCP reachability check, not the real path",
                        },
                      ]
                    : []),
                  ...(active ? [{ text: "active" }] : []),
                ]}
                actions={
                  <ActionPanel>
                    <Action.Open
                      title="Switch Server in Happ"
                      icon={Icon.AppWindow}
                      target={HAPP_APP}
                    />
                    <Action
                      title="Measure Latency"
                      icon={Icon.Gauge}
                      shortcut={{ modifiers: ["cmd"], key: "p" }}
                      onAction={measure}
                    />
                    <Action.CopyToClipboard
                      title="Copy Server Name"
                      content={row.name}
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
        description="Add the subscription URL in preferences — it is the only source of server names and addresses."
      />
    </List>
  );
}
