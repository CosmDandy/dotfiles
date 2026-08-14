import { closeMainWindow, getPreferenceValues, showHUD } from "@raycast/api";
import { readState, runShortcut } from "./lib/happ";
import { reportFailure } from "./lib/feedback";
import { rememberServer } from "./lib/server-map";

type Preferences = {
  shortcutToggle: string;
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
    // The Toggle shortcut takes a boolean, so the desired state is passed
    // explicitly rather than relying on Happ to invert the current one —
    // two rapid invocations would otherwise race each other.
    await runShortcut(prefs.shortcutToggle, state.connected ? "false" : "true");
    await showHUD(
      target === "connect"
        ? `Happ connecting${state.serverName ? ` — ${state.serverName}` : ""}`
        : "Happ disconnecting",
    );
  } catch (error) {
    await reportFailure(error, `${target} the tunnel`);
  }
}
