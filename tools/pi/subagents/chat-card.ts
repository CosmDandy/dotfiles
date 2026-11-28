import { open, realpath } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve, sep } from "node:path";
import { stripVTControlCharacters } from "node:util";
import type { ExtensionAPI, Theme, ToolRenderers } from "@earendil-works/pi-coding-agent";
import { mixColors, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { toolStatusStyle } from "../tool-status.ts";

const tickMs = 40;
const pulseMs = 5600;
const maxRows = 8;
const runId = /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i;
const effortTones = new Map<string, Parameters<Theme["fg"]>[0]>([
  ["low", "thinkingMedium"], ["medium", "thinkingLow"], ["high", "warning"], ["xhigh", "error"], ["max", "error"],
]);
const tones = { queued: "muted", running: "accent", completed: "success", failed: "error", stopped: "warning", paused: "warning", unavailable: "muted" } as const;

type State = keyof typeof tones;
type Activity = {
  currentTool?: string; currentToolArgs?: string; currentPath?: string; currentToolStartedAt?: number;
  recentTools?: { tool: string; args: string }[];
  durationMs?: number; tokens?: number | { total?: number };
};
type Source = Activity & {
  agent?: string; index?: number; childId?: string; workflowKey?: string; state?: string; status?: string;
  model?: string; thinking?: string; context?: string; runId?: string; sessionFile?: string;
  startedAt?: number; endedAt?: number; exitCode?: number; success?: boolean; stopped?: boolean; timedOut?: boolean;
  detached?: boolean; interrupted?: boolean; error?: string; acceptance?: { status?: string };
  progress?: Source; activity?: Activity; usage?: { input: number; output: number };
};
type Details = {
  mode?: string; context?: string; asyncId?: string; progress?: Source[]; results?: Source[];
  workflowChildren?: { children: Source[] }; workflow?: { trace?: { key: string; error?: string }[] };
};
type Result = { details?: Details; content?: { type: string; text?: string }[]; isError?: boolean };
type Completion = { runId?: string; workflowRunId?: string; status?: string; state?: string; durationMs?: number; error?: string;
  results?: Source[]; childRuns?: Source[]; childOutputs?: Source[] };
type DiskRun = { runId: string; sessionId?: string; state: string; startedAt?: number; endedAt?: number; error?: string; steps?: Source[] };
type Row = { key: number | string; name: string; state: State; model?: string; effort?: string; context?: string;
  tokens?: number; duration?: number; started?: number; file?: string; runId?: string; error?: string; tool?: string; args?: string; target?: string; toolStarted?: number };
type Card = { planned: Row[]; rows: Row[]; active: boolean; state?: State; error?: string; duration?: number; asyncId?: string; started?: number; historical?: boolean; workflow?: boolean };
type PreviewTool = (tool: string, args: string | undefined, target: string | undefined, theme: Theme, width: number) => string;
type TimedLine = (left: string, time: string, width: number, theme: Theme) => string;
type QuietMetadata = (theme: Theme, text: string) => string;

const clean = (s: string | undefined) => typeof s === "string" ? stripVTControlCharacters(s.slice(0, 1024)).replace(/[\p{Cc}\p{Cf}]+/gu, " ").trim() : "";
const firstLine = (s: string | undefined) => clean(s?.trimStart().split("\n", 1)[0]);
const elapsed = (ms: number) => ms < 60_000 ? `${Math.floor(ms / 1000)} s` : `${Math.floor(ms / 60_000)} m ${Math.floor(ms / 1000) % 60} s`;
const tokenText = (n: number) => n < 1000 ? `${n} tok` : `${(n / 1000).toFixed(1).replace(/\.0$/, "")}k tok`;
const durationOf = (v: { startedAt?: number; endedAt?: number }) => v.startedAt !== undefined && v.endedAt !== undefined ? Math.max(0, v.endedAt - v.startedAt) : undefined;
const textOf = (result: Result) => firstLine(result.content?.find(c => c.type === "text")?.text
  ?.split("\n").find(line => line.trim() && !line.startsWith("Run fan-out:")));
const isActive = (s: State) => s === "queued" || s === "running";

function stateOf(source: Source, active = false): State {
  if (source.timedOut) return "failed";
  if (source.stopped || source.state === "stopped" || source.status === "stopped") return "stopped";
  if (source.detached || source.interrupted) return "paused";
  if (!active && (source.exitCode || source.success === false || source.acceptance?.status === "rejected")) return "failed";
  switch (source.status ?? source.state ?? source.progress?.status) {
    case "running": case "started": return "running";
    case "pending": case "queued": return "queued";
    case "paused": case "detached": return "paused";
    case "partial": case "failed": case "rejected": return "failed";
  }
  if (source.exitCode || source.success === false || source.acceptance?.status === "rejected") return "failed";
  return active && !source.status && !source.state && !source.progress?.status ? "queued" : "completed";
}

function modelLabel(id: string | undefined) {
  const name = clean(id).split("/").at(-1) ?? "";
  return /(?:^|[- ])sol(?:-medium)?$/i.test(name) ? "Sol" : /(?:^|[- ])astra$/i.test(name) ? "Astra" : name;
}

function plannedRows(args: { agent?: string; model?: string; tasks?: { agent?: string; model?: string }[];
  chain?: { agent?: string; model?: string; parallel?: { agent?: string; model?: string }[] }[];
  options?: { context?: string }; context?: string }): Row[] {
  const children = args.tasks ?? args.chain?.flatMap(step => step.parallel ?? [step]) ?? [args];
  return children.filter(child => typeof child.agent === "string" && child.agent).map((child, key) => ({
    key, name: child.agent!, state: "queued", context: args.options?.context ?? args.context ?? "fresh",
    model: child.model ?? args.model,
  }));
}

function tokensOf(source: Source) {
  const raw = (source.progress ?? source.activity)?.tokens ?? source.tokens;
  const count = (typeof raw === "number" ? raw : raw?.total) ?? (source.usage && source.usage.input + source.usage.output);
  return typeof count === "number" && Number.isFinite(count) && count >= 0 ? count : undefined;
}

function projectRow(source: Source, key: Row["key"], previous: Row | undefined, fallback: Row | undefined, context?: string, active?: boolean): Row {
  const progress = source.progress ?? source.activity ?? source;
  const model = source.progress?.model ?? source.model ?? previous?.model ?? fallback?.model;
  const tokens = tokensOf(source) ?? previous?.tokens;
  const lastTool = progress.recentTools?.at(-1);
  const tool = progress.currentTool ?? lastTool?.tool ?? previous?.tool;
  const toolStarted = progress.currentToolStartedAt;
  const args = progress.currentTool ? progress.currentToolArgs ??
    (tool === previous?.tool && toolStarted === previous?.toolStarted ? previous?.args : undefined) : lastTool?.args ?? previous?.args;
  const duration = durationOf(source) ?? progress.durationMs ?? source.durationMs ?? previous?.duration;
  const state = stateOf(source, active);
  return {
    key, name: source.agent ?? previous?.name ?? fallback?.name ?? "agent", state, model,
    effort: source.progress?.thinking ?? source.thinking ?? previous?.effort,
    context: source.context ?? context ?? previous?.context ?? fallback?.context,
    tokens, duration, started: source.startedAt ?? previous?.started ?? (state === "running" ? Date.now() - (duration ?? 0) : undefined),
    file: source.sessionFile ?? previous?.file, runId: source.runId ?? previous?.runId, tool, args, target: progress.currentPath ?? (tool === previous?.tool ? previous?.target : undefined),
    toolStarted, error: firstLine(source.error ?? source.progress?.error ?? previous?.error)
      || (source.timedOut ? "timed out" : source.acceptance?.status === "rejected" ? "acceptance rejected" : undefined),
  };
}

const rowKey = (source: Source, index: number) => source.workflowKey ?? source.childId ?? source.index ?? index;

function setRows(card: Card, sources: Source[], context?: string) {
  const previous = new Map(card.rows.map(row => [row.key, row]));
  card.rows = sources.map((source, i) => {
    const key = rowKey(source, i);
    const old = previous.get(key);
    if (card.active && source.runId && old?.runId === source.runId && !isActive(old.state) && isActive(stateOf(source, true))) return old;
    return projectRow(source, key, old, card.planned[i], context, card.active);
  });
}

function settle(card: Card, state: State, error?: string, duration?: number) {
  card.active = false;
  card.state = state;
  card.duration = duration ?? card.duration ?? card.rows.reduce<number | undefined>((max, row) =>
    row.duration === undefined ? max : Math.max(max ?? 0, row.duration), undefined);
  card.error = firstLine(error) || undefined;
}

function runningDot(theme: Theme): string {
  const phase = (Date.now() % pulseMs) / pulseMs;
  const strength = (1 - Math.cos(phase * 2 * Math.PI)) / 2;
  const dim = mixColors(theme.colors.toolPendingBg, theme.colors.accent, 0.16, "srgb");
  return theme.style("●", { fg: mixColors(dim, theme.colors.error, strength, "srgb") });
}

function cardLines(card: Card, theme: Theme, width: number, padding: string, preview: PreviewTool, timedLine: TimedLine, quietMetadata: QuietMetadata): string[] {
  const title = padding + theme.fg("toolOutput", theme.bold("subagents"));
  const separator = quietMetadata(theme, " · ");
  const rows = card.rows.length ? card.rows : card.planned;
  const shown = rows.slice(0, maxRows);
  const rest = rows.length > maxRows ? `, +${rows.length - maxRows}` : "";
  const names = shown.map(row => clean(row.name));
  const nameTone = (name: string, state: State) => isActive(state) ? theme.fg("toolTitle", name)
    : theme.style(name, state === "completed" || state === "failed" ? toolStatusStyle(theme, tones[state])
      : { fg: mixColors(theme.colors.toolOutput, theme.colors[tones[state]], 0.58) });
  const count = (row: Row) => row.tokens === undefined ? "" : quietMetadata(theme, tokenText(row.tokens));
  const list = (labels: string[]) => labels.join(theme.fg("toolOutput", ", ")) + (rest ? theme.fg("toolOutput", rest) : "");
  const fit = (s: string) => truncateToWidth(s, width);
  if (card.state && !card.active) {
    const state = card.state;
    const reason = card.error ?? shown.find(row => row.error && row.state !== "completed")?.error ?? (state === "failed" ? "failed" : undefined);
    const end = card.duration !== undefined ? elapsed(card.duration) : "";
    const summary = list(shown.map((row, i) =>
      [nameTone(names[i], isActive(row.state) ? state : row.state), count(row)].filter(Boolean).join(" ")));
    const outcome = state !== "completed" && state !== "failed" ? nameTone(state, state) : "";
    const status = [summary, outcome].filter(Boolean).join("  ");
    const detail = !reason ? "" : state === "failed" ? theme.style(` — ${clean(reason)}`, toolStatusStyle(theme, "error"))
      : theme.fg("toolOutput", ` — ${clean(reason)}`);
    return [timedLine(title + (status ? separator + status : "") + detail, end, width, theme)];
  }
  const lines = [fit(title + (names.length ? separator + list(shown.map((row, i) => nameTone(names[i], row.state))) : ""))];
  if (!card.active) return lines;
  const nameWidths = names.map(visibleWidth);
  const nameColumn = Math.max(0, ...nameWidths);
  for (const [i, row] of shown.entries()) {
    const [model, suffix] = clean(row.model).split(/:(?=[a-z]+$)/);
    const label = modelLabel(model);
    const effort = clean(row.effort) || suffix || "";
    const tone = effortTones.get(effort);
    const effortLabel = effort && (tone ? theme.style(effort, { fg: mixColors(theme.colors.muted, theme.colors[tone], 0.35, "srgb") })
      : theme.fg("muted", effort));
    const profile = [label && theme.fg("muted", label), effortLabel].filter(Boolean).join(" ");
    const total = row.started !== undefined && row.state === "running" ? Math.max(row.duration ?? 0, Date.now() - row.started) : row.duration;
    const context = row.context === "fresh" ? theme.fg("muted", "fresh") : row.context === "fork" ? theme.fg("toolTitle", "fork") : "";
    const meta = [profile, context, count(row)].filter(Boolean).join(separator);
    const marker = row.state === "queued" ? theme.fg("muted", "◌") : row.state === "running" ? runningDot(theme) : " ";
    const name = nameTone(names[i], row.state);
    const columns = meta ? " ".repeat(nameColumn - nameWidths[i]) + separator + meta : "";
    const left = `${padding}  ${marker} ${name}${columns}`;
    lines.push(timedLine(left, total === undefined ? "" : elapsed(total), width, theme));
    const branch = padding + theme.fg("dim", "    └ ");
    if (row.error && !isActive(row.state)) lines.push(fit(branch + theme.style(row.error, toolStatusStyle(theme, "error"))));
    else if (row.tool && row.state === "running" && width > padding.length + 8)
      lines.push(fit(branch + preview(row.tool, row.args, row.target, theme, width - padding.length - 6)));
  }
  return lines;
}

async function readBounded(path: string, max: number, tail: boolean) {
  try {
    const file = await open(path, "r");
    try {
      const stat = await file.stat();
      if (!stat.isFile() || (!tail && stat.size > max)) return;
      const size = Math.min(stat.size, max);
      const bytes = Buffer.allocUnsafe(size);
      const { bytesRead } = await file.read(bytes, 0, size, stat.size - size);
      return bytes.toString("utf8", 0, bytesRead);
    } finally { await file.close(); }
  } catch { /* The run may have moved or finished between the event and this read. */ }
}

async function diskRun(root: string, id: string, owners: ReadonlySet<string>) {
  if (!root || !runId.test(id)) return;
  try {
    const text = await readBounded(join(root, id, "status.json"), 2 * 1024 * 1024, false);
    const data = text ? JSON.parse(text) as DiskRun : undefined;
    if (data?.runId === id && data.sessionId && owners.has(data.sessionId) && typeof data.state === "string" &&
        (data.steps === undefined || (Array.isArray(data.steps) && data.steps.every(step => step && typeof step.agent === "string")))) return data;
  } catch { /* Retention or an incomplete publication leaves the last observed state intact. */ }
}

async function transcriptArgs(file: string, root: string, tool: string, started: number | undefined) {
  try {
    const canonical = await realpath(file);
    if (!canonical.startsWith(root + sep)) return;
    const tail = await readBounded(canonical, 64 * 1024, true);
    const finished = new Set<string>();
    for (const line of (tail ?? "").trimEnd().split("\n").reverse()) {
      let entry;
      try { entry = JSON.parse(line); } catch { continue; }
      const message = entry?.type === "message" ? entry.message : undefined;
      if (message?.role === "toolResult") finished.add(message.toolCallId);
      if (message?.role !== "assistant" || !Array.isArray(message.content)) continue;
      if (started !== undefined && typeof message.timestamp === "number" && message.timestamp + 30_000 < started) return;
      const call = message.content.findLast((item: { type?: string; name?: string; id: string; arguments?: unknown }) =>
        item?.type === "toolCall" && item.name === tool && !finished.has(item.id));
      if (call && typeof call.arguments === "object" && call.arguments !== null) return JSON.stringify(call.arguments);
    }
  } catch { /* A child does not have a persisted transcript until it writes its first entry. */ }
}

export function registerSubagentChat(pi: ExtensionAPI, preview: PreviewTool, timedLine: TimedLine, quietMetadata: QuietMetadata) {
  let owners: ReadonlySet<string> = new Set(), transcriptRoot = "", asyncRoot = "";
  let redraw: (() => void) | undefined, hidden = false;
  let spin: ReturnType<typeof setInterval> | undefined, refresh: ReturnType<typeof setTimeout> | undefined;
  let reading = false, dirty = false, generation = 0;
  let listeners: (() => void)[] = [];
  const active = new Set<Card>(), asyncCards = new Map<string, Card>(), slashCards = new Map<string, Card>();
  const endings = new Map<string, Completion>();
  const historyCalls = new Set<string>();
  const commands = new WeakSet<Row>();

  function repaint() { if (!hidden) redraw?.(); }
  function track(card: Card) {
    if (card.active) active.add(card); else active.delete(card);
    if (active.size && redraw && !spin) {
      spin = setInterval(repaint, tickMs);
      spin.unref();
    } else if (!active.size && spin) { clearInterval(spin); spin = undefined; }
  }
  function fillCommands(card: Card) {
    if (!transcriptRoot || !card.active) return;
    for (const row of card.rows) {
      if (row.state !== "running" || !row.file || !row.tool || row.args || commands.has(row)) continue;
      commands.add(row);
      const epoch = generation;
      void transcriptArgs(row.file, transcriptRoot, row.tool, row.toolStarted).then(args => {
        if (!args || generation !== epoch) return;
        const current = card.rows.find(item => item.key === row.key);
        if (current && current.tool === row.tool && current.toolStarted === row.toolStarted && !current.args) {
          current.args = args;
          repaint();
        }
      });
    }
  }
  async function fillFinalTokens(card: Card, id: string) {
    const epoch = generation;
    const status = await diskRun(asyncRoot, id, owners);
    if (generation !== epoch || !status || isActive(stateOf(status))) return;
    let changed = false;
    for (const [i, step] of (status.steps ?? []).slice(0, maxRows).entries()) {
      const row = card.rows.find(row => step.runId ? row.runId === step.runId : row.key === rowKey(step, i));
      const count = tokensOf(step);
      if (row && count !== undefined && row.tokens !== count) {
        row.tokens = count;
        changed = true;
      }
    }
    if (changed) repaint();
  }
  function endAsync(id: string, completion: Completion) {
    const state = stateOf(completion);
    const rows = completion.results?.length ? completion.results : completion.childOutputs?.length ? completion.childOutputs : completion.childRuns;
    endings.set(id, { state, durationMs: completion.durationMs, error: firstLine(completion.error),
      results: rows?.map(({ agent, runId, workflowKey, childId, index, ...row }) =>
        ({ agent, runId, workflowKey, childId, index, state: stateOf(row), error: firstLine(row.error), tokens: tokensOf(row) })) });
    const card = asyncCards.get(id);
    if (!card) return;
    if (rows?.length) setRows(card, rows);
    settle(card, state, completion.error, completion.durationMs);
    asyncCards.delete(id);
    track(card);
    repaint();
    // Persisted notification receipts omit usage. Recover it from the terminal snapshot.
    if (!rows?.length || rows.some(row => tokensOf(row) === undefined)) return fillFinalTokens(card, id);
  }
  async function childStep(id: string) {
    const child = await diskRun(asyncRoot, id, owners);
    const step = child?.steps?.[0];
    return step && { ...step, startedAt: step.startedAt ?? child?.startedAt, endedAt: step.endedAt ?? child?.endedAt };
  }
  function refreshAsync() {
    dirty = true;
    const foreground = [...active].filter(card => card.workflow && !card.asyncId && card.rows.some(row => row.runId && isActive(row.state)));
    if (!redraw || (!asyncCards.size && !foreground.length) || refresh || reading) return;
    refresh = setTimeout(async () => {
      refresh = undefined;
      reading = true;
      dirty = false;
      const epoch = generation;
      try {
        const foregroundUpdates = foreground.flatMap(card => card.rows.filter(row => row.runId && isActive(row.state)).map(async row => {
          const step = await childStep(row.runId!);
          if (!step || generation !== epoch || !active.has(card)) return;
          const index = card.rows.findIndex(current => current.key === row.key && current.runId === row.runId && isActive(current.state));
          if (index < 0) return;
          card.rows[index] = projectRow({ ...step, runId: row.runId }, row.key, card.rows[index], undefined, undefined, true);
          repaint();
        }));
        await Promise.all([...foregroundUpdates, ...[...asyncCards].map(async ([id, card]) => {
          const status = await diskRun(asyncRoot, id, owners);
          if (generation !== epoch || asyncCards.get(id) !== card) return;
          if (!status) {
            if (card.historical) {
              settle(card, "unavailable");
              asyncCards.delete(id);
              track(card);
              repaint();
            }
            return;
          }
          const steps = (status.steps ?? []).slice(0, maxRows);
          const rows = await Promise.all(steps.map(async step => {
            if (!step.runId || step.runId === id) return step;
            const live = await childStep(step.runId);
            return live ? { ...step, ...live } : step;
          }));
          if (generation !== epoch || asyncCards.get(id) !== card) return;
          if (rows.length) setRows(card, rows);
          const state = stateOf(status);
          if (!isActive(state)) {
            settle(card, state, status.error, durationOf(status));
            asyncCards.delete(id);
          } else card.active = true;
          track(card);
          fillCommands(card);
          repaint();
        })]);
      } finally {
        if (epoch === generation) {
          reading = false;
          if (dirty) refreshAsync();
        }
      }
    }, 150);
    refresh.unref();
  }
  function update(card: Card, result: Result, partial: boolean, duration?: number) {
    const d = result.details;
    const resultRows = d?.results ?? [];
    const progress = d?.progress ?? [];
    card.active = partial;
    card.workflow ||= d?.mode === "workflow";
    if (partial) card.started ??= Date.now();
    if (resultRows.length) {
      const byIndex = new Map(progress.map(row => [row.index, row]));
      setRows(card, resultRows.map(row => ({ ...row, progress: byIndex.get(row.index) ?? row.progress })), d?.context);
    } else if (d?.workflowChildren?.children.length) {
      const errors = new Map(d.workflow?.trace?.filter(row => row.error).map(row => [row.key, row.error]));
      setRows(card, d.workflowChildren.children.map(row => ({ ...row, error: errors.get(row.childId ?? "") })), d.context);
    } else if (progress.length) setRows(card, progress, d?.context);
    if (d?.asyncId && !result.isError && runId.test(d.asyncId) && !partial) {
      card.asyncId = d.asyncId;
      const ended = endings.get(d.asyncId);
      if (ended || !card.state) {
        card.active = true;
        asyncCards.set(d.asyncId, card);
        if (ended) endAsync(d.asyncId, ended); else refreshAsync();
      }
    } else if (!partial) {
      const failed = result.isError || card.rows.some(row => row.state === "failed");
      const state = failed ? "failed" : card.rows.find(row => row.state === "paused" || row.state === "stopped")?.state ?? "completed";
      const elapsed = duration ?? (card.started !== undefined ? Date.now() - card.started : undefined);
      settle(card, state, result.isError && !card.rows.some(row => row.error) ? textOf(result) : undefined, elapsed);
    }
    track(card);
    if (partial && card.workflow) refreshAsync();
    fillCommands(card);
  }
  function reset() {
    generation++;
    for (const off of listeners) off();
    listeners = [];
    active.clear(); asyncCards.clear(); slashCards.clear(); endings.clear(); historyCalls.clear();
    if (spin) clearInterval(spin);
    if (refresh) clearTimeout(refresh);
    spin = refresh = undefined;
    reading = dirty = hidden = false;
    redraw = undefined;
  }
  pi.on("session_start", async (_event, ctx) => {
    // Pi can render restored tool results before emitting session_start on reload.
    const restored = redraw ? [] : [...asyncCards];
    reset();
    if (ctx.mode !== "tui") return;
    const parent = ctx.sessionManager.getSessionFile();
    owners = new Set([ctx.sessionManager.getSessionId(), parent].filter((value): value is string => !!value));
    const epoch = generation;
    transcriptRoot = "";
    asyncRoot = process.getuid ? join(resolve(process.env.PI_SUBAGENTS_TEMP_ROOT?.trim() || join(tmpdir(), `pi-subagents-uid-${process.getuid()}`)), "async-subagent-runs") : "";
    // Acquire the TUI without coupling card redraws to the footer's refresh cadence.
    ctx.ui.setWidget("dotfiles:subagent-chat-redraw", tui => {
      redraw = () => tui.requestRender();
      return { render: () => [], invalidate() {} };
    }, { placement: "belowEditor" });
    const historySlash = new Map<string, Result>();
    for (const entry of ctx.sessionManager.getBranch()) {
      if (entry.type === "message" && entry.message.role === "toolResult" && entry.message.toolName === "subagent")
        historyCalls.add(entry.message.toolCallId);
      if (entry.type !== "custom_message") continue;
      if (entry.customType === "subagent-notify") {
        for (const run of (entry.details as { runs?: Completion[] })?.runs ?? []) {
          const id = run.workflowRunId ?? run.runId;
          if (id) endings.set(id, run);
        }
      }
      if (entry.customType === "subagent-slash-result") {
        const details = entry.details as { requestId?: string; result?: Result };
        if (!details?.requestId || !details.result) continue;
        if (entry.display) historySlash.set(details.requestId, details.result);
        else {
          historySlash.delete(details.requestId);
          const card: Card = { rows: [], planned: [], active: false, historical: true };
          slashCards.set(details.requestId, card);
          update(card, details.result, false);
        }
      }
    }
    for (const [id, result] of historySlash) {
      const card: Card = { rows: [], planned: [], active: false };
      setRows(card, result.details?.results ?? []);
      settle(card, "unavailable");
      slashCards.set(id, card);
    }
    listeners = [
      pi.events.on("dotfiles:pane-hidden", value => { hidden = value === true; if (!hidden) repaint(); }),
      pi.events.on("subagent:jobs-changed", refreshAsync),
      pi.events.on("subagent:async-complete", data => {
        const completion = data as Completion;
        const id = completion?.workflowRunId ?? completion?.runId;
        if (id && (asyncCards.has(id) || !endings.has(id))) endAsync(id, completion);
      }),
      pi.events.on("subagent:slash:update", data => {
        const event = data as { requestId: string; progress?: Source[] };
        const card = slashCards.get(event.requestId);
        if (card && event.progress) { update(card, { details: { progress: event.progress } }, true); repaint(); }
      }),
      pi.events.on("subagent:slash:response", data => {
        const event = data as { requestId: string; result: Result; isError?: boolean };
        const card = slashCards.get(event.requestId);
        if (card) { update(card, { ...event.result, isError: event.isError }, false); repaint(); }
      }),
      pi.events.on("subagent:slash:cancel", data => {
        const card = slashCards.get((data as { requestId: string }).requestId);
        if (card) { settle(card, "stopped"); track(card); repaint(); }
      }),
    ];
    await Promise.all(restored.map(([id, card]) => {
      card.historical = true;
      asyncCards.set(id, card);
      const ended = endings.get(id);
      if (ended) return endAsync(id, ended);
      track(card);
    }));
    if (restored.length) refreshAsync();
    if (parent?.endsWith(".jsonl")) {
      try {
        const home = await realpath(resolve(parent, ".."));
        if (epoch === generation) transcriptRoot = join(home, parent.split(sep).at(-1)!.slice(0, -6));
      } catch { /* Ephemeral Pi sessions have no persisted child transcripts. */ }
    }
  });
  pi.on("session_shutdown", reset);

  const component = (card: Card, theme: Theme, outputPad: number) => {
    const padding = " ".repeat(outputPad);
    return { render: (width: number) => cardLines(card, theme, width, padding, preview, timedLine, quietMetadata), invalidate() {} };
  };
  pi.registerMessageRenderer("subagent-slash-result", (message, options, theme) => {
    const details = message.details as { requestId?: string; result?: Result };
    if (!details?.requestId || !details.result) return undefined;
    let card = slashCards.get(details.requestId);
    if (!card) {
      card = { rows: [], planned: (details.result.details?.results ?? []).map((row, key) => ({
        key, name: row.agent ?? "agent", state: "queued", context: row.context ?? details.result!.details?.context ?? "fresh",
      })), active: false };
      slashCards.set(details.requestId, card);
      update(card, details.result, message.display === true);
    }
    return component(card, theme, options.outputPad);
  });
  return (native: ToolRenderers | undefined): ToolRenderers => ({
    renderShell: "self",
    renderCall(args, theme, ctx) {
      if (args?.action) return native?.renderCall?.(args, theme, ctx);
      const card = (ctx.state.subagentChat ??= { rows: [], planned: [], active: false }) as Card;
      card.planned = plannedRows(args ?? {});
      if (ctx.executionStarted && ctx.isPartial && !card.state) {
        card.active = true;
        card.started ??= Date.now();
        track(card);
      }
      return component(card, theme, ctx.outputPad);
    },
    renderResult(result, options, theme, ctx) {
      if (ctx.args?.action || result.details?.mode === "management") return native?.renderResult?.(result, options, theme, ctx);
      const card = (ctx.state.subagentChat ??= { rows: [], planned: [], active: false }) as Card;
      // A detached tool result is rendered again on expansion and must not restore its launch snapshot.
      if (!card.asyncId && !card.state) {
        card.historical = historyCalls.has(ctx.toolCallId);
        update(card, { ...result, isError: ctx.isError }, options.isPartial, ctx.durationMs);
      }
      return { render: () => [], invalidate() {} };
    },
  });
}
