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
import {
  ServerMap,
  loadServerMap,
  rememberServer,
  staleIds,
  unknownIds,
} from "./lib/server-map";
import RebuildServerMap from "./rebuild-server-map";

type Preferences = {
  shortcutSelect: string;
  shortcutConnect: string;
  shortcutDisconnect: string;
};

type Row = { id: string; name?: string };

export default function Command() {
  const [loading, setLoading] = useState(true);
  const [state, setState] = useState<HappState | null>(null);
  const [rows, setRows] = useState<Row[]>([]);
  const [map, setMap] = useState<ServerMap>({});
  const [stale, setStale] = useState<string[]>([]);

  async function refresh() {
    setLoading(true);
    const [current, ids, known] = await Promise.all([
      readState(),
      listConfigIds(),
      loadServerMap(),
    ]);

    // The running config names itself, so every visit teaches one more entry
    // even when the user never runs a full calibration.
    if (current.configId && current.serverName) {
      await rememberServer(current.configId, current.serverName);
      known[current.configId] = current.serverName;
    }

    setState(current);
    setMap(known);
    setStale(staleIds(known, ids));
    setRows(ids.map((id) => ({ id, name: known[id] })));
    setLoading(false);
  }

  useEffect(() => {
    refresh();
  }, []);

  const prefs = getPreferenceValues<Preferences>();

  async function connectTo(row: Row) {
    const toast = await showToast({
      style: Toast.Style.Animated,
      title: `Switching to ${row.name ?? row.id.slice(0, 8)}`,
    });
    try {
      await runShortcut(prefs.shortcutSelect, row.id);
      await runShortcut(prefs.shortcutConnect);
      toast.style = Toast.Style.Success;
      toast.title = `Connected to ${row.name ?? row.id.slice(0, 8)}`;
      // Give Happ a moment to publish the new config, then learn its name.
      setTimeout(refresh, 1500);
    } catch (error) {
      await toast.hide();
      await reportFailure(error, "switch servers");
    }
  }

  async function disconnect() {
    try {
      await runShortcut(prefs.shortcutDisconnect);
      await showToast({ style: Toast.Style.Success, title: "Disconnected" });
      setTimeout(refresh, 1000);
    } catch (error) {
      await reportFailure(error, "disconnect");
    }
  }

  const unnamed = unknownIds(
    map,
    rows.map((r) => r.id),
  );

  // Group by the flag that starts every remark; anything unnamed lands in its
  // own section so the calibration hint stays visible instead of scattering.
  const groups = new Map<string, Row[]>();
  for (const row of rows) {
    if (!row.name) continue;
    const { flag } = splitServerName(row.name);
    const key = flag ?? "Other";
    const list = groups.get(key) ?? [];
    list.push(row);
    groups.set(key, list);
  }

  return (
    <List isLoading={loading} searchBarPlaceholder="Search servers…">
      {state && (
        <List.Section title="Connection">
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
            accessories={
              state.tcpConnections
                ? [{ text: `${state.tcpConnections} tcp` }]
                : undefined
            }
            actions={
              <ActionPanel>
                {state.connected && (
                  <Action
                    title="Disconnect"
                    icon={Icon.BoltDisabled}
                    onAction={disconnect}
                  />
                )}
                <Action
                  title="Refresh"
                  icon={Icon.ArrowClockwise}
                  shortcut={{ modifiers: ["cmd"], key: "r" }}
                  onAction={refresh}
                />
              </ActionPanel>
            }
          />
        </List.Section>
      )}

      {[...groups.entries()].map(([flag, list]) => (
        <List.Section key={flag} title={flag === "Other" ? "Servers" : flag}>
          {list.map((row) => {
            const { label } = splitServerName(row.name ?? "");
            const active = row.id === state?.configId;
            return (
              <List.Item
                key={row.id}
                icon={
                  active
                    ? { source: Icon.CircleFilled, tintColor: Color.Green }
                    : Icon.Circle
                }
                title={label}
                accessories={
                  active && state?.connected ? [{ text: "active" }] : undefined
                }
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
                    <Action.CopyToClipboard
                      title="Copy Config Id"
                      content={row.id}
                    />
                    <Action
                      title="Refresh"
                      icon={Icon.ArrowClockwise}
                      shortcut={{ modifiers: ["cmd"], key: "r" }}
                      onAction={refresh}
                    />
                  </ActionPanel>
                }
              />
            );
          })}
        </List.Section>
      ))}

      {unnamed.length > 0 && (
        <List.Section
          title="Not identified yet"
          subtitle={`${unnamed.length} of ${rows.length}`}
        >
          {unnamed.map((id) => (
            <List.Item
              key={id}
              icon={Icon.QuestionMark}
              title={id.slice(0, 8)}
              subtitle="name unknown — Happ encrypts stored configs"
              actions={
                <ActionPanel>
                  <Action
                    title="Connect and Learn Its Name"
                    icon={Icon.Bolt}
                    onAction={() => connectTo({ id })}
                  />
                  <Action.Push
                    title="Rebuild Server Map"
                    icon={Icon.List}
                    target={<RebuildServerMap />}
                  />
                </ActionPanel>
              }
            />
          ))}
        </List.Section>
      )}

      {stale.length > 0 && (
        <List.Section title="Stale entries">
          <List.Item
            icon={{ source: Icon.Warning, tintColor: Color.Orange }}
            title={`${stale.length} remembered server${stale.length > 1 ? "s" : ""} no longer exist`}
            subtitle="the subscription was refreshed — rebuild the map"
            actions={
              <ActionPanel>
                <Action.Push
                  title="Rebuild Server Map"
                  icon={Icon.List}
                  target={<RebuildServerMap />}
                />
              </ActionPanel>
            }
          />
        </List.Section>
      )}

      <List.EmptyView
        icon={Icon.Globe}
        title="No configs found"
        description="Happ has no subscription configs on disk, or its storage layout changed."
      />
    </List>
  );
}
