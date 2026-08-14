import {
  Clipboard,
  Color,
  Icon,
  MenuBarExtra,
  getPreferenceValues,
  launchCommand,
  LaunchType,
  open,
  showHUD,
} from "@raycast/api";
import { useEffect, useState } from "react";
import { HappState, formatUptime, readState, runShortcut } from "./lib/happ";
import { rememberServer } from "./lib/server-map";
import { reportFailure } from "./lib/feedback";

type Preferences = { shortcutToggle: string };

export default function Command() {
  const [state, setState] = useState<HappState | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      const current = await readState();
      if (current.configId && current.serverName) {
        await rememberServer(current.configId, current.serverName);
      }
      setState(current);
      setLoading(false);
    })();
  }, []);

  const prefs = getPreferenceValues<Preferences>();
  const uptime = formatUptime(state?.connectedSince);

  // Only the flag and the tail of the name fit a menu bar; the full string
  // stays in the dropdown.
  const short = state?.serverName?.split("·").pop()?.trim();

  return (
    <MenuBarExtra
      isLoading={loading}
      icon={{
        source: state?.connected ? Icon.Bolt : Icon.BoltDisabled,
        tintColor: state?.connected ? Color.Green : Color.SecondaryText,
      }}
      title={state?.connected ? short : undefined}
      tooltip={state?.serverName ?? "Happ"}
    >
      <MenuBarExtra.Section title={state?.serverName ?? "No active config"}>
        {state?.connected && uptime && (
          <MenuBarExtra.Item icon={Icon.Clock} title={`Up ${uptime}`} />
        )}
        {state?.tcpConnections && (
          <MenuBarExtra.Item
            icon={Icon.Network}
            title={`${state.tcpConnections} TCP connections`}
          />
        )}
      </MenuBarExtra.Section>

      <MenuBarExtra.Section>
        <MenuBarExtra.Item
          icon={state?.connected ? Icon.BoltDisabled : Icon.Bolt}
          title={state?.connected ? "Disconnect" : "Connect"}
          onAction={async () => {
            // Menu bar commands have no error boundary: an unhandled throw
            // surfaces as a crash trace instead of a message, and a missing
            // shortcut is the expected failure on a fresh install.
            try {
              await runShortcut(
                prefs.shortcutToggle,
                state?.connected ? "false" : "true",
              );
              await showHUD(
                state?.connected ? "Happ disconnecting" : "Happ connecting",
              );
            } catch (error) {
              await reportFailure(error, "toggle the tunnel");
            }
          }}
        />
        <MenuBarExtra.Item
          icon={Icon.Globe}
          title="Select Server…"
          onAction={() =>
            launchCommand({
              name: "select-server",
              type: LaunchType.UserInitiated,
            })
          }
        />
      </MenuBarExtra.Section>

      <MenuBarExtra.Section>
        {state?.httpProxyPort && (
          <MenuBarExtra.Item
            icon={Icon.Link}
            title={`Copy http://127.0.0.1:${state.httpProxyPort}`}
            onAction={async () => {
              await Clipboard.copy(`http://127.0.0.1:${state.httpProxyPort}`);
              await showHUD("Proxy URL copied");
            }}
          />
        )}
        <MenuBarExtra.Item
          icon={Icon.AppWindow}
          title="Open Happ"
          onAction={() => open("/Applications/Happ.app")}
        />
      </MenuBarExtra.Section>
    </MenuBarExtra>
  );
}
