import { Clipboard, closeMainWindow, showHUD } from "@raycast/api";
import { readState } from "./lib/happ";

/**
 * Happ exposes a local HTTP and SOCKS proxy alongside the tunnel. Handing the
 * address over is useful exactly where the tunnel itself is not: setting
 * HTTPS_PROXY inside a container, or pointing one curl through the VPN while
 * the rest of the machine stays direct.
 */
export default async function Command() {
  const state = await readState();
  const http = state.httpProxyPort;
  const socks = state.socksProxyPort;

  if (!http && !socks) {
    await showHUD("Happ reports no proxy ports");
    return;
  }

  const lines = [
    http ? `http://127.0.0.1:${http}` : undefined,
    socks ? `socks5://127.0.0.1:${socks}` : undefined,
  ].filter(Boolean);

  await Clipboard.copy(lines.join("\n"));
  await closeMainWindow();
  await showHUD(`Copied ${lines.join("  ")}`);
}
