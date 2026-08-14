import { closeMainWindow, getPreferenceValues, showHUD } from "@raycast/api";
import { runShortcut } from "./lib/happ";
import { reportFailure } from "./lib/feedback";

type Preferences = { shortcutRefresh: string };

export default async function Command() {
  const prefs = getPreferenceValues<Preferences>();
  try {
    await closeMainWindow();
    await runShortcut(prefs.shortcutRefresh);
    await showHUD("Happ refreshed");
  } catch (error) {
    await reportFailure(error, "refresh the subscription");
  }
}
