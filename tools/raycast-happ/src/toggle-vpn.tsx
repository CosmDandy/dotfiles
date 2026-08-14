import { closeMainWindow, getPreferenceValues, showHUD } from "@raycast/api";
import { readState, setTunnel } from "./lib/happ";
import { reportFailure } from "./lib/feedback";
import { rememberServer } from "./lib/server-map";

type Preferences = {
  shortcutConnect: string;
  shortcutDisconnect: string;
  shortcutToggle?: string;
};

export default async function Command() {
  const prefs = getPreferenceValues<Preferences>();
  const state = await readState();

  // Remember what is running while we can: after disconnecting, the active
  // config is still recorded but its name may no longer be readable.
  if (state.configId && state.serverName) {
    await rememberServer(state.configId, state.serverName);
  }

  const target = state.connected ? "disconnect" : "connect";

  try {
    await closeMainWindow();
    // The desired state is passed explicitly rather than letting Happ invert
    // the current one — two rapid invocations would otherwise race.
    await setTunnel(!state.connected, prefs);
    await showHUD(
      target === "connect"
        ? `Happ connecting${state.serverName ? ` — ${state.serverName}` : ""}`
        : "Happ disconnecting",
    );
  } catch (error) {
    await reportFailure(error, `${target} the tunnel`);
  }
}
