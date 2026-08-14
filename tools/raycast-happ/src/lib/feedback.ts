import { Toast, showToast, open } from "@raycast/api";
import { ShortcutMissingError } from "./happ";

/**
 * Every action goes through Shortcuts, and a missing shortcut is the one
 * failure a new user will hit — so it gets an explanation and a way out
 * rather than a raw error string.
 */
export async function reportFailure(error: unknown, action: string) {
  if (error instanceof ShortcutMissingError) {
    await showToast({
      style: Toast.Style.Failure,
      title: `Shortcut "${error.shortcutName}" is missing`,
      message:
        "Create it in Shortcuts, or rename it in this extension's preferences",
      primaryAction: {
        title: "Open Shortcuts",
        onAction: () => {
          open("shortcuts://");
        },
      },
    });
    return;
  }

  await showToast({
    style: Toast.Style.Failure,
    title: `Could not ${action}`,
    message: error instanceof Error ? error.message : String(error),
  });
}
