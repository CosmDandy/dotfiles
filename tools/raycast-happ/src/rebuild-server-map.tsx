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
import { useEffect, useRef, useState } from "react";
import { listConfigIds, readState, runShortcut } from "./lib/happ";
import { reportFailure } from "./lib/feedback";
import { ServerMap, loadServerMap, saveServerMap } from "./lib/server-map";

type Preferences = { shortcutSelect: string; shortcutToggle: string };

type Phase = "idle" | "probing" | "running" | "done" | "aborted";

/** How long Happ needs to publish the newly selected config. */
const SETTLE_MS = 1200;

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Learn which config UUID carries which server name.
 *
 * There is no way to read this: Happ encrypts every stored config, and the
 * only place a name appears in the clear is `connectedConfigJson`, describing
 * whatever is active right now. So the map is built by selecting each config
 * in turn and reading back what became active.
 *
 * The run starts with a probe: select one config *without* connecting and see
 * whether the published config changes anyway. If it does, the whole
 * calibration is silent and never touches the tunnel. If it does not, naming
 * every server means connecting to each of them, and that is the user's call.
 */
export default function RebuildServerMap() {
  const [phase, setPhase] = useState<Phase>("idle");
  const [ids, setIds] = useState<string[]>([]);
  const [map, setMap] = useState<ServerMap>({});
  const [done, setDone] = useState(0);
  const [silent, setSilent] = useState<boolean | null>(null);
  const abort = useRef(false);

  useEffect(() => {
    (async () => {
      const [configIds, known] = await Promise.all([
        listConfigIds(),
        loadServerMap(),
      ]);
      setIds(configIds);
      setMap(known);
    })();
    return () => {
      abort.current = true;
    };
  }, []);

  const prefs = getPreferenceValues<Preferences>();

  /** Does selecting without connecting change what Happ reports as active? */
  async function probe(): Promise<boolean> {
    const before = await readState();
    const other = ids.find((id) => id !== before.configId);
    if (!other) return false;

    await runShortcut(prefs.shortcutSelect, other);
    await sleep(SETTLE_MS);
    const after = await readState();

    const changed =
      after.configId === other ||
      (after.serverName !== undefined &&
        after.serverName !== before.serverName);

    // Put the original config back whatever the answer is.
    if (before.configId) {
      await runShortcut(prefs.shortcutSelect, before.configId);
      await sleep(SETTLE_MS);
    }
    return changed;
  }

  async function calibrate(connectEach: boolean) {
    abort.current = false;
    setPhase("running");
    setDone(0);
    const learned: ServerMap = { ...map };
    const start = await readState();

    try {
      for (const id of ids) {
        if (abort.current) {
          setPhase("aborted");
          return;
        }
        await runShortcut(prefs.shortcutSelect, id);
        if (connectEach) await runShortcut(prefs.shortcutToggle, "true");
        await sleep(SETTLE_MS);

        const now = await readState();
        if (now.serverName) {
          learned[id] = now.serverName;
          setMap({ ...learned });
        }
        setDone((n) => n + 1);
      }

      await saveServerMap(learned);

      // Leave the machine as it was found.
      if (start.configId) {
        await runShortcut(prefs.shortcutSelect, start.configId);
        if (connectEach && start.connected) {
          await runShortcut(prefs.shortcutToggle, "true");
        }
      }

      setPhase("done");
      await showToast({
        style: Toast.Style.Success,
        title: `Named ${Object.keys(learned).length} of ${ids.length} configs`,
      });
    } catch (error) {
      setPhase("idle");
      await reportFailure(error, "rebuild the server map");
    }
  }

  async function start() {
    setPhase("probing");
    try {
      const quiet = await probe();
      setSilent(quiet);
      await calibrate(!quiet);
    } catch (error) {
      setPhase("idle");
      await reportFailure(error, "probe Happ");
    }
  }

  const named = Object.keys(map).filter((id) => ids.includes(id)).length;

  return (
    <List isLoading={phase === "probing" || phase === "running"}>
      <List.Section title="Calibration">
        <List.Item
          icon={
            phase === "done"
              ? { source: Icon.CheckCircle, tintColor: Color.Green }
              : Icon.List
          }
          title={
            phase === "running"
              ? `Naming servers — ${done} of ${ids.length}`
              : phase === "probing"
                ? "Checking whether this can be done without connecting…"
                : phase === "done"
                  ? `Done — ${named} of ${ids.length} named`
                  : `${ids.length} configs, ${named} already named`
          }
          subtitle={
            silent === null
              ? "selects every config once to learn its name"
              : silent
                ? "runs without touching the tunnel"
                : "connects to each server in turn — the tunnel will flap"
          }
          actions={
            <ActionPanel>
              {phase === "idle" || phase === "done" || phase === "aborted" ? (
                <Action
                  title="Start Calibration"
                  icon={Icon.Play}
                  onAction={start}
                />
              ) : (
                <Action
                  title="Stop"
                  icon={Icon.Stop}
                  onAction={() => {
                    abort.current = true;
                  }}
                />
              )}
            </ActionPanel>
          }
        />
      </List.Section>

      <List.Section title="Known names">
        {ids
          .filter((id) => map[id])
          .map((id) => (
            <List.Item
              key={id}
              icon={Icon.Globe}
              title={map[id]}
              subtitle={id.slice(0, 8)}
            />
          ))}
      </List.Section>
    </List>
  );
}
