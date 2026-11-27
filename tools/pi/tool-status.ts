import type { Theme } from "@earendil-works/pi-coding-agent";
import { mixColors, rgbColor } from "@earendil-works/pi-tui";

const black = rgbColor(0, 0, 0);

export function toolStatusStyle(theme: Theme, status: "error" | "success", bold = false) {
  // OKLCH interpolation from Solarized's blue-gray to red can cross yellow or violet.
  const fg = status === "error" ? mixColors(theme.colors.toolOutput, theme.colors.error, 0.58, "srgb")
    : mixColors(theme.colors.success, black, theme.appearance === "dark" ? 0.12 : 0.25, "srgb");
  return { fg, bold };
}
