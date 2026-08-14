import { closeMainWindow, open, showHUD } from "@raycast/api";
import { readState } from "./lib/happ";

export default async function Command() {
  const state = await readState();
  if (!state.logFile) {
    await showHUD("Happ has no current log file");
    return;
  }

  // The value is stored as a file URL; open() handles both that and a bare path.
  await closeMainWindow();
  await open(state.logFile);
}
