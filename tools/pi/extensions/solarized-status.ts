import { CustomEditor, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Marked, mixColors, rgbColor, Text, truncateToWidth, visibleWidth, wrapTextWithAnsi, type TuiMouseEvent } from "@earendil-works/pi-tui";
import { execFile, spawn } from "node:child_process";
import { mkdirSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { stripVTControlCharacters } from "node:util";

const lightReady = rgbColor(152, 161, 106);
const lightBackground = rgbColor(253, 246, 227);
type TurnPhase = "wait" | "generation" | "bash" | "tools";
type TurnSpan = { phase: TurnPhase; from: number; to: number };
type TurnTiming = { started: number; spans: TurnSpan[]; tokens: number; textSeconds: number };

function summarizeTurn(turn: TurnTiming, ended: number, aborted: boolean) {
  const breakdown = { wait: 0, generation: 0, bash: 0, tools: 0, parallel: 0, other: 0 };
  const active = { wait: 0, generation: 0, bash: 0, tools: 0 };
  const edges = turn.spans.flatMap(({ phase, from, to }) => {
    const start = Math.max(turn.started, from);
    const end = Math.min(ended, to);
    return start < end ? [{ at: start, phase, delta: 1 }, { at: end, phase, delta: -1 }] : [];
  }).sort((a, b) => a.at - b.at);
  let previous = turn.started;
  for (const { at, phase, delta } of edges) {
    // Overlapping calls consume a single wall-clock interval, not one interval per call.
    const bucket = active.bash ? active.tools ? "parallel" : "bash" : active.tools ? "tools"
      : active.generation ? "generation" : active.wait ? "wait" : "other";
    breakdown[bucket] += at - previous;
    active[phase] += delta;
    previous = at;
  }
  breakdown.other += ended - previous;
  return { total: ended - turn.started, ...breakdown, aborted,
    speed: turn.textSeconds > 0 ? turn.tokens / turn.textSeconds : undefined };
}

const frameInset = (columns: number): number => columns >= 10 ? 3 : 0;

type Window = { used_percentage: number; resets_at: number };
type WindowName = "five_hour" | "seven_day";
const windowNames = ["five_hour", "seven_day"] as const;
// Only actual subscription-window headers, never requests/minute or tokens/minute.
export function parseLimits(raw: Record<string, string>, now = Date.now() / 1000) {
  const h = Object.fromEntries(Object.entries(raw).map(([k, v]) => [k.toLowerCase(), v]));
  const result: Partial<Record<WindowName, Window | null>> = {};
  const number = (key: string) => h[key]?.trim() ? Number(h[key]) : NaN;
  for (const name of ["primary", "secondary"]) {
    const prefix = `x-codex-${name}-`;
    const used = number(prefix + "used-percent");
    const minutes = number(prefix + "window-minutes");
    const resetAt = number(prefix + "reset-at");
    const after = number(prefix + "reset-after-seconds");
    const reset = Number.isFinite(resetAt) ? resetAt : now + after;
    if (!Number.isFinite(used) || used < 0 || !Number.isFinite(reset)) continue;
    const key = minutes === 300 ? "five_hour" : minutes === 10080 ? "seven_day" : undefined;
    if (key) result[key] = { used_percentage: used, resets_at: reset };
  }
  // A zero-length slot beside a valid weekly window explicitly disables the short window.
  if (result.seven_day && !result.five_hour &&
    (number("x-codex-primary-window-minutes") === 0 || number("x-codex-secondary-window-minutes") === 0))
    result.five_hour = null;
  for (const [suffix, key] of [["5h", "five_hour"], ["7d", "seven_day"]] as const) {
    const prefix = `anthropic-ratelimit-unified-${suffix}-`;
    const utilization = number(prefix + "utilization"), reset = number(prefix + "reset");
    if (Number.isFinite(utilization) && utilization >= 0 && Number.isFinite(reset))
      result[key] = { used_percentage: utilization * 100, resets_at: reset };
  }
  return result;
}

type Observation = { observedAt: number } & (Window | { absent: true });
type ObservedLimits = Partial<Record<WindowName, Observation>>;

function observe(parsed: ReturnType<typeof parseLimits>, observedAt: number): ObservedLimits {
  const record: ObservedLimits = {};
  for (const name of windowNames) {
    const window = parsed[name];
    if (window !== undefined) record[name] = window === null ? { observedAt, absent: true } : { ...window, observedAt };
  }
  return record;
}

// Select the newest observation before checking expiry, so an older window cannot resurface.
function loadSharedObservations(cache: string, provider: string, now: number) {
  const latest: ObservedLimits = {};
  const merge = (record: ObservedLimits) => {
    for (const name of windowNames) {
      const window = record[name];
      if (!window || !Number.isFinite(window.observedAt) || window.observedAt > now) continue;
      if ("absent" in window ? window.absent !== true :
        !Number.isFinite(window.used_percentage) || window.used_percentage < 0 || !Number.isFinite(window.resets_at)) continue;
      const previous = latest[name];
      // A millisecond tie must not let a parallel snapshot resurrect a disabled window.
      if (!previous || window.observedAt > previous.observedAt ||
        (window.observedAt === previous.observedAt && "absent" in window)) latest[name] = window;
    }
  };
  const directory = join(cache, encodeURIComponent(provider));
  let files: string[] = [];
  try { files = readdirSync(directory); } catch { /* No observation for this provider yet. */ }
  for (const name of files) {
    if (!/^limits-\d+\.json$/.test(name)) continue;
    try { merge(JSON.parse(readFileSync(join(directory, name), "utf8"))); } catch { /* Ignore incomplete or corrupt cache files. */ }
  }
  // Older loaded runtimes publish this diagnostic but do not have shared snapshots yet.
  try {
    const diagnostic = JSON.parse(readFileSync(join(cache, "transport-diagnostic.json"), "utf8"));
    if (diagnostic.provider === provider) {
      const observedAt = diagnostic.observedAt ?? Date.parse(diagnostic.at);
      const parsed = parseLimits(diagnostic.subscriptionHeaders ?? {}, observedAt / 1000);
      merge(observe(parsed, observedAt));
    }
  } catch { /* Diagnostics are optional; provider snapshots remain authoritative. */ }
  return latest;
}

export function loadSharedLimits(cache: string, provider: string, now = Date.now()) {
  const latest = loadSharedObservations(cache, provider, now);
  const active: Partial<Record<WindowName, Window & { observedAt: number }>> = {};
  for (const name of windowNames) {
    const window = latest[name];
    if (window && !("absent" in window) && window.resets_at > now / 1000) active[name] = window;
  }
  return active;
}

// Show the total number of working runtimes, including this one, only from two onward.
export function countSessions(directory: string, now = Date.now()) {
  let running = 0;
  for (const name of readdirSync(directory)) {
    if (!/^\d+\.json$/.test(name)) continue;
    try {
      const entry = JSON.parse(readFileSync(join(directory, name), "utf8"));
      if (entry.pid !== Number(name.slice(0, -5)) || !Number.isFinite(entry.at) || now - entry.at > 90000) continue;
      process.kill(entry.pid, 0);
      if (entry.state === "running") running++;
    } catch { /* A crashed or concurrently closing runtime is not a live session. */ }
  }
  return { running: running > 1 ? running : 0, waiting: 0 };
}

export default function (pi: ExtensionAPI) {
  const markdownParser = new Marked();
  const subheading = /^ {0,3}#{3,6}(?=[ \t]|$)/m;
  const reportColors = { "✔": "success", "✘": "error", "!": "accent", "?": "warning", "»": "mdLink" } as const;
  const reportOpener = /^ {0,3}(?:\*\*|__)?([✔✘!?»])(?=\s|$|\*\*|__)/m;
  pi.registerMarkdownTransformer((markdown, { isStreaming, messageType }) => {
    const theme = messageType === "assistant" ? sessionContext?.ui.theme : undefined;
    if (isStreaming || (!subheading.test(markdown) && !(theme && reportOpener.test(markdown)))) return markdown;
    const source = markdown.replace(/\r\n?/g, "\n");
    let cursor = 0, copied = 0, output = "";
    for (const token of markdownParser.lexer(source)) {
      const start = source.indexOf(token.raw, cursor);
      if (start === -1) return markdown;
      cursor = start + token.raw.length;
      let replacement: string;
      if (token.type === "heading" && /^ {0,3}#{3,6}(?=[ \t]|\n|$)/.test(token.raw)) {
        // Pi displays the literal prefix at level three and deeper, but not at level two.
        replacement = token.raw.replace(/^( {0,3})#{3,6}/, "$1##");
      } else if (theme && token.type === "paragraph" && token.tokens && !token.text.includes("\n")) {
        const glyph = reportOpener.exec(token.text)?.[1] as keyof typeof reportColors | undefined;
        if (!glyph) continue;
        // The whole label is bold; redundant Markdown delimiters next to ANSI escapes can render literally.
        const label = token.tokens.map(t => t.type === "strong" ? t.text : t.raw).join("");
        replacement = theme.style(label, { fg: reportColors[glyph], bold: true }) + token.raw.slice(token.text.length);
      } else continue;
      output += source.slice(copied, start) + replacement;
      copied = cursor;
    }
    return copied ? output + source.slice(copied) : markdown;
  }, { messageTypes: ["assistant", "user"] });

  const root = join(homedir(), ".pi", "agent");
  const cache = join(root, "cache", "statusline");
  let enabled = true;
  let refresh: (() => void) | undefined;
  let redraw: (() => void) | undefined;
  let busy = false;
  let waitingForUser = false;
  let sessionTimer: ReturnType<typeof setInterval> | undefined;
  const sessionsDir = join(root, "cache", "statusline", "sessions");
  const sessionFile = join(sessionsDir, `${process.pid}.json`);
  let sessionContext: ExtensionContext | undefined;
  function publishSession() {
    if (!sessionContext) return;
    writeFileSync(sessionFile + ".tmp", JSON.stringify({
      pid: process.pid, at: Date.now(),
      state: waitingForUser ? "waiting" : busy ? "running" : "idle",
    }), { mode: 0o600 });
    renameSync(sessionFile + ".tmp", sessionFile);
  }
  let generatingSince: number | undefined;
  let phase: "Waiting" | "Thinking" | "Generating" | "Preparing" = "Waiting";
  let stream: { firstOutput?: number; firstText?: number; lastText?: number; textChunks: number; toolCall: boolean } = { textChunks: 0, toolCall: false };
  let lastResponse: {
    seconds: number; speed?: number; firstOutputSeconds?: number; firstTextSeconds?: number;
    textSeconds?: number; outputTokens: number; reasoningTokens?: number; textTokens?: number;
    textChunks: number; speedUnavailableReason?: string;
  } | undefined;
  let error = false;
  let interrupted = false;
  const activeTools = new Map<string, string>();
  const stars = ["·", "✢", "*", "✶", "✻", "✽"];
  const thinkingFrames = [...stars, ...stars.toReversed()];
  let turnTiming: TurnTiming | undefined;
  const toolStarts = new Map<string, { from: number; phase: "bash" | "tools" }>();
  const decimal = (value: number) => value.toFixed(1).replace(".", ",");
  const seconds = (ms: number) => `${decimal(ms / 1000)} s`;
  const startTiming = () => { turnTiming ??= { started: performance.now(), spans: [], tokens: 0, textSeconds: 0 }; };
  pi.registerEntryRenderer<ReturnType<typeof summarizeTurn>>("turn-timing", (entry, { expanded }, theme) => {
    const timing = entry.data;
    if (!timing) return;
    const toolTime = timing.bash + timing.tools + timing.parallel;
    const phases = [[timing.wait, "wait"], [timing.generation, "gen"], [toolTime, "tools"], [timing.other, "other"]] as const;
    const parts = [`${seconds(timing.total)}${timing.aborted ? " (interrupted)" : ""}`];
    for (const [ms, label] of phases) {
      const percent = timing.total > 0 ? Math.round(100 * ms / timing.total) : 0;
      if (percent > 0) parts.push(`${label} ${percent}%`);
    }
    if (timing.speed !== undefined) parts.push(`≈${decimal(timing.speed)} tok/s`);
    const lines = [parts.join(" · ")];
    if (expanded) {
      const elapsed = phases.filter(([ms]) => ms >= 50).map(([ms, label]) => `${label} ${seconds(ms)}`);
      if (elapsed.length) lines.push(elapsed.join(" · "));
      if (toolTime >= 50) {
        lines.push(`bash ${seconds(timing.bash)} · other tools ${seconds(timing.tools)}`
          + (timing.parallel >= 50 ? ` · overlap ${seconds(timing.parallel)}` : ""));
      }
    }
    const light = theme.appearance === "light";
    const fg = light ? mixColors(theme.colors.borderMuted, rgbColor(255, 249, 234), 0.20, "srgb") : rgbColor(89, 102, 106);
    const text = lines.map((line, i) => (i ? "  " : "") + theme.style(line, { fg, dim: light })).join("\n");
    return new Text(text, 2, 0);
  });
  pi.registerCommand("statusline-metrics", {
    description: "Show client-side response latency, text throughput and token accounting",
    handler: async () => {
      pi.sendMessage({
        customType: "statusline-metrics",
        content: "Latest completed model request:\n```json\n" + JSON.stringify(lastResponse ?? { observed: false }, null, 2) + "\n```\n" +
          "seconds: complete request, excluding tools. firstOutputSeconds: first visible text/thinking/tool-argument chunk. " +
          "firstTextSeconds: first visible text chunk. textSeconds: first-to-last text chunk. " +
          "speed: approximate text tokens/s; reasoning and tool-call responses are excluded. " +
          "Chunk timestamps are client observations, not server token timestamps.",
        display: true,
      }, { triggerTurn: false });
    },
  });
  let lastDiagnostic: object = { observed: false, note: "No provider response observed since reload" };
  pi.registerCommand("statusline-limits", {
    description: "Show observed subscription-window headers and shared provider limits (no credentials)",
    handler: async (_args, ctx) => {
      pi.sendMessage({
        customType: "statusline-limits",
        content: "Subscription window transport diagnostic:\n```json\n" + JSON.stringify({
          lastResponse: lastDiagnostic,
          sharedLimits: loadSharedLimits(cache, ctx.model?.provider ?? "unknown"),
        }, null, 2) + "\n```",
        display: true,
      }, { triggerTurn: false });
    },
  });
  function install(ctx: ExtensionContext) {
    if (ctx.mode !== "tui") return;
    if (!enabled) {
      ctx.ui.setEditorComponent(undefined);
      ctx.ui.setWorkingVisible(true);
      ctx.ui.setFooter(undefined);
      refresh = undefined;
      redraw = undefined;
      return;
    }
    ctx.ui.setWorkingVisible(false);
    ctx.ui.setFooter((tui, _theme, data) => {
      let width = 100, line = "", pending = false, dirty = false, disposed = false;
      let child: ReturnType<typeof spawn> | undefined;
      function update() {
        if (disposed) return;
        if (pending) { dirty = true; return; }
        pending = true;
        const tmp = join(root, "cache", "statusline", encodeURIComponent(ctx.model?.provider ?? "unknown"));
        mkdirSync(tmp, { recursive: true, mode: 0o700 });
        let current: { input: number; cacheRead: number; cacheWrite: number } | undefined;
        for (const entry of ctx.sessionManager.getBranch()) {
          if (entry.type === "message" && entry.message.role === "assistant") {
            current = entry.message.usage;
          }
        }
        const usage = ctx.getContextUsage();
        const limits = loadSharedLimits(cache, ctx.model?.provider ?? "unknown");
        const effort = pi.getThinkingLevel();
        const payload = {
          model: { display_name: ctx.model?.name ?? ctx.model?.id ?? "No model", id: ctx.model?.id },
          context_window: {
            used_percentage: usage?.percent ?? 0,
            context_window_size: usage?.contextWindow ?? ctx.model?.contextWindow,
            current_usage: current ? { input_tokens: current.input, cache_read_input_tokens: current.cacheRead, cache_creation_input_tokens: current.cacheWrite } : {},
          },
          thinking: { enabled: pi.getThinkingLevel() !== "off" },
          // The statusline renderer normalizes unstyled labels to lowercase and uses the model's neutral gray.
          effort: { level: effort === "medium" ? "MEDIUM" : effort },
          rate_limits: limits,
          sessions: countSessions(sessionsDir),
        };
        child = spawn(join(root, "bin", "solarized-statusline"), [], {
          env: { ...process.env, TMPDIR: tmp, COLUMNS: String(Math.max(1, width)) },
          stdio: ["pipe", "pipe", "ignore"],
        });
        let output = "";
        const timeout = setTimeout(() => child?.kill(), 2000);
        child.stdout!.on("data", chunk => { output += chunk.toString(); });
        child.stdin!.on("error", () => {});
        child.stdin!.end(JSON.stringify(payload));
        child.on("error", () => {});
        child.on("close", code => {
          clearTimeout(timeout); pending = false; child = undefined;
          if (disposed) return;
          line = code === 0 ? output : "Status line unavailable: check pi-statusline installation (see tools/pi/README.md)";
          tui.requestRender();
          if (dirty) { dirty = false; update(); }
        });
      }
      refresh = update;
      const requestRender = () => tui.requestRender();
      redraw = requestRender;
      // Queue state can change without a model or tool event.
      let queued = ctx.hasPendingMessages();
      const pane = process.env.TMUX && process.env.TMUX_PANE;
      let hidden = false, checking = false, nextProbe = 0, nextFrame = 0;
      const clock = setInterval(() => {
        const nextQueued = ctx.hasPendingMessages();
        const animating = busy || generatingSince !== undefined;
        const now = Date.now();
        if (animating && pane && /^%\d+$/.test(pane) && !checking && now >= nextProbe) {
          checking = true;
          nextProbe = now + 2000;
          execFile("tmux", ["display-message", "-p", "-t", pane, "#{window_id}", ";", "list-clients", "-F", "#{window_id} #{window_zoomed_flag} #{pane_id}"], { timeout: 800 }, (error, stdout) => {
            checking = false;
            if (disposed) return;
            const [win, ...clients] = stdout.trim().split("\n");
            const nextHidden = !error && /^@\d+$/.test(win) && clients.every(row => {
              const match = /^(@\d+) ([01]) (%\d+)$/.exec(row);
              return match && (match[1] !== win || (match[2] === "1" && match[3] !== pane));
            });
            if (hidden !== nextHidden) {
              hidden = nextHidden;
              pi.events.emit("dotfiles:pane-hidden", hidden);
              if (!hidden) requestRender();
            }
          });
        }
        if (queued !== nextQueued || (animating && (!hidden || now >= nextFrame))) {
          if (hidden) {
            nextFrame = now + 1000;
            pi.events.emit("dotfiles:animation-tick", undefined);
          }
          requestRender();
        }
        queued = nextQueued;
      }, 100);
      ctx.ui.setEditorComponent((editorTui, editorTheme, keybindings) => {
        class StatusEditor extends CustomEditor {
          private hiddenAbove = 0;
          private bottomBorder = "";

          private renderStatus(columns: number, modeLabel: string): string {
            const theme = ctx.ui.theme;
            const light = theme.appearance === "light";
            const secondary = light ? "thinkingText" : "dim";
            const state = activeTools.size ? "Running" : generatingSince !== undefined ? phase : busy ? "Active" : interrupted ? "Interrupted" : "Ready";
            const phases = {
              Waiting: { frames: ["⠂", "⠒", "⠲", "⠴", "⠤", "⠠"], color: theme.colors.thinkingLow },
              Thinking: { frames: thinkingFrames, color: theme.colors.thinkingText },
              // Leave the top Braille dot row empty so the spinner sits closer to the text baseline.
              Generating: { frames: ["⠖", "⠲", "⢲", "⢰", "⣰", "⣠", "⣄", "⣆", "⡆", "⡖"], color: theme.colors.thinkingMedium },
              Preparing: { frames: ["·", "•", "●", "•"], color: theme.colors.warning },
              Running: { frames: ["⠁", "⠂", "⠄", "⡀", "⢀", "⠠", "⠐", "⠈"], color: theme.colors.warning },
              Active: { frames: ["⠂", "⠒", "⠲", "⠴", "⠤", "⠠"], color: theme.colors[secondary] },
            };
            const animation = state in phases ? phases[state as keyof typeof phases] : undefined;
            const frame = animation?.frames[Math.floor(performance.now() / 150) % animation.frames.length];
            const phaseColor = animation?.color ?? (interrupted ? theme.colors.warning : light ? lightReady : theme.colors.success);
            const stateLabel = theme.style(animation ? `${frame} ${state}` : `${interrupted ? "■" : "·"} ${state}`, {
              fg: light && !["Ready", "Thinking", "Active"].includes(state) ? mixColors(phaseColor, lightBackground, 0.23, "srgb") : phaseColor,
              dim: !light,
            });
            const toolNames = activeTools.size ? theme.fg(secondary, [...new Set(activeTools.values())].join(", ")) : "";
            const badges = [error ? theme.style("error", { fg: "error", dim: !light }) : "", ctx.hasPendingMessages() ? theme.style("queued", { fg: "warning", dim: !light }) : "", this.hiddenAbove ? `↑ ${this.hiddenAbove} more` : ""].filter(Boolean);
            const statuses = data.getExtensionStatuses();
            const otherStatuses = [...statuses].filter(([key]) => key !== "work-mode").map(([, value]) => value);
            const left = [modeLabel, toolNames, ...badges, ...otherStatuses].filter(Boolean).join(theme.fg("dim", " · "));
            const right = truncateToWidth(stateLabel, columns, "");
            const gap = columns - visibleWidth(right);
            return truncateToWidth(left, Math.max(0, gap - 1), "", true) + (gap ? " " : "") + right;
          }
          protected renderTopBorder(columns: number, hiddenLineCount: number): string {
            this.hiddenAbove = hiddenLineCount;
            return "─".repeat(columns);
          }

          protected renderBottomBorder(columns: number, hiddenLineCount: number): string {
            this.bottomBorder = stripVTControlCharacters(super.renderBottomBorder(columns, hiddenLineCount));
            return this.bottomBorder;
          }

          render(columns: number): string[] {
            const margin = frameInset(columns);
            const inset = " ".repeat(margin);
            const innerWidth = columns - 2 * margin;
            const lines = super.render(innerWidth);
            const bottom = lines.indexOf(this.bottomBorder, 1);
            const theme = ctx.ui.theme;
            const [mode, profile, agents] = (data.getExtensionStatuses().get("work-mode") ?? "").split(" · ");
            const light = theme.appearance === "light";
            const coral = light ? rgbColor(170, 72, 66) : rgbColor(217, 126, 116);
            const blue = light ? rgbColor(43, 108, 150) : rgbColor(111, 172, 207);
            const modeColor = mode === "EXPLORE" ? blue : mode === "EXECUTE" ? coral : undefined;
            const profileColor = profile === "AUTONOMOUS" ? coral : mixColors(theme.colors.muted, theme.colors.dim, 0.65, "srgb");
            const modeLabel = modeColor ? [
              theme.style(mode, { fg: modeColor }),
              profile ? theme.style(profile, { fg: profileColor }) : "",
              agents ? theme.fg("accent", agents) : "",
            ].filter(Boolean).join(theme.fg("dim", " · ")) : "";
            const borderColor = modeColor ? mixColors(theme.colors.borderMuted, modeColor, 0.5, "srgb") : undefined;
            const border = (text: string) => borderColor ? theme.style(text, { fg: borderColor }) : theme.fg("borderMuted", text);
            const frame = lines.map((line, i) => {
              if (i === 0) return margin ? ` ${border(`╭─${line}─╮`)} ` : border(line);
              if (i === bottom) return margin ? ` ${border(`╰─${line}─╯`)} ` : border(line);
              if (!margin) return line;
              return i < bottom ? ` ${border("│")} ${line} ${border("│")} ` : inset + line + inset;
            });
            return [inset + this.renderStatus(innerWidth, modeLabel) + inset, ...frame];
          }

          handleMouse(event: TuiMouseEvent) {
            const margin = frameInset(event.width);
            return super.handleMouse({ ...event, x: event.x - margin, y: event.y - 1,
              width: event.width - 2 * margin, height: event.height - 1 });
          }
        }
        return new StatusEditor(editorTui, editorTheme, keybindings);
      });
      update();
      let layout: { line: string; columns: number; lightColor?: string; rows: string[] } | undefined;
      return {
        invalidate() { layout = undefined; },
        render(columns: number) {
          const margin = frameInset(columns);
          const inset = " ".repeat(margin);
          const innerWidth = Math.max(1, columns - margin * 2);
          if (width !== innerWidth) { width = innerWidth; update(); }
          const theme = ctx.ui.theme;
          // On light backgrounds the ribbon's ANSI gray plus faint loses too much contrast.
          const lightColor = theme.appearance === "light" ? theme.getFgAnsi("thinkingText") : undefined;
          if (layout && layout.line === line && layout.columns === columns && layout.lightColor === lightColor) return layout.rows;
          const output = lightColor !== undefined
            ? line.replaceAll("\x1b[2;38;5;11m", lightColor).replaceAll("\x1b[2;", "\x1b[")
            : line;
          const rows = output.split("\n");
          if (rows.length === 1) {
            // The Go renderer and TUI can count Nerd Font glyphs differently. Correct its inter-block gap in terminal columns.
            const row = rows[0];
            const gap = [...row.matchAll(/ {2,}/g)].reduce<RegExpMatchArray | undefined>((longest, match) =>
              !longest || match[0].length > longest[0].length ? match : longest, undefined);
            if (gap && gap.index !== undefined) {
              const size = gap[0].length + innerWidth - visibleWidth(row);
              if (size > 0) rows[0] = row.slice(0, gap.index) + " ".repeat(size) + row.slice(gap.index + gap[0].length);
            }
          }
          const rendered = rows.flatMap(row => wrapTextWithAnsi(row, innerWidth))
            .map(row => inset + truncateToWidth(row, innerWidth, "", true) + inset);
          layout = { line, columns, lightColor, rows: rendered };
          return rendered;
        },
        dispose() {
          disposed = true;
          if (hidden) pi.events.emit("dotfiles:pane-hidden", false);
          clearInterval(clock);
          child?.kill();
          if (refresh === update) refresh = undefined;
          if (redraw === requestRender) redraw = undefined;
        },
      };
    });
  }
  pi.on("session_start", async (_event, ctx) => {
    busy = false;
    generatingSince = undefined;
    phase = "Waiting";
    stream = { textChunks: 0, toolCall: false };
    lastResponse = undefined;
    turnTiming = undefined;
    toolStarts.clear();
    error = false;
    interrupted = false;
    activeTools.clear();
    waitingForUser = false;
    sessionContext = ctx;
    if (ctx.mode === "tui") ctx.ui.setHiddenThinkingLabel("");
    mkdirSync(sessionsDir, { recursive: true, mode: 0o700 });
    publishSession();
    sessionTimer = setInterval(() => { publishSession(); refresh?.(); }, 15000);
    sessionTimer.unref();
    install(ctx);
  });
  pi.on("before_agent_start", startTiming);
  pi.on("agent_start", () => {
    startTiming();
    busy = true;
    publishSession();
    error = false;
    interrupted = false;
    redraw?.();
  });
  pi.on("before_provider_request", () => {
    if (!busy || activeTools.size) return;
    generatingSince = performance.now();
    phase = "Waiting";
    redraw?.();
  });
  pi.on("message_start", event => {
    if (event.message.role !== "assistant") return;
    // Provider timestamps include server wait before the stream's start event.
    const beforeStart = Math.max(0, Date.now() - event.message.timestamp);
    generatingSince = performance.now() - beforeStart;
    phase = "Waiting";
    stream = { textChunks: 0, toolCall: false };
    redraw?.();
  });
  pi.on("message_update", event => {
    if (generatingSince === undefined) return;
    const update = event.assistantMessageEvent;
    const now = performance.now();
    if ((update.type === "text_delta" || update.type === "thinking_delta" || update.type === "toolcall_delta") && update.delta.length > 0) {
      stream.firstOutput ??= now;
      if (update.type === "text_delta") {
        stream.firstText ??= now;
        stream.lastText = now;
        stream.textChunks++;
        phase = "Generating";
      } else if (update.type === "thinking_delta") phase = "Thinking";
      else { stream.toolCall = true; phase = "Preparing"; }
    } else if (update.type === "thinking_start") phase = "Thinking";
    else if (update.type === "toolcall_start") { stream.toolCall = true; phase = "Preparing"; }
    redraw?.();
  });
  pi.on("tool_execution_start", event => {
    if (turnTiming && !event.parentToolCallId) {
      toolStarts.set(event.toolCallId, { from: performance.now(), phase: event.toolName === "bash" ? "bash" : "tools" });
    }
    activeTools.set(event.toolCallId, event.toolName);
    redraw?.();
  });
  pi.on("tool_execution_end", event => {
    const started = toolStarts.get(event.toolCallId);
    if (started) turnTiming?.spans.push({ ...started, to: performance.now() });
    toolStarts.delete(event.toolCallId);
    activeTools.delete(event.toolCallId);
    redraw?.();
  });
  pi.on("agent_settled", (event, ctx) => {
    const ended = performance.now();
    if (ctx.mode === "tui" && turnTiming && ended > turnTiming.started) {
      for (const started of toolStarts.values()) turnTiming.spans.push({ ...started, to: ended });
      pi.appendEntry("turn-timing", summarizeTurn(turnTiming, ended, event.aborted));
    }
    turnTiming = undefined;
    toolStarts.clear();
    busy = false;
    generatingSince = undefined;
    interrupted = event.aborted;
    activeTools.clear();
    publishSession();
    redraw?.();
  });
  pi.on("after_provider_response", async (event, ctx) => {
    const next = parseLimits(event.headers);
    const safeHeaders = Object.fromEntries(Object.entries(event.headers).filter(([name]) =>
      /^x-codex-(primary|secondary)-(used-percent|window-minutes|reset-at|reset-after-seconds)$/i.test(name) ||
      /^anthropic-ratelimit-unified-(5h|7d)-(utilization|reset)$/i.test(name)));
    const observedAt = Date.now();
    const provider = ctx.model?.provider ?? "unknown";
    const directory = join(cache, encodeURIComponent(provider));
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    const snapshot = { ...loadSharedObservations(cache, provider, observedAt), ...observe(next, observedAt) };
    if (Object.keys(snapshot).length) {
      // Each process owns one atomic snapshot, so parallel writers cannot overwrite each other.
      const path = join(directory, `limits-${process.pid}.json`);
      writeFileSync(path + ".tmp", JSON.stringify(snapshot), { mode: 0o600 });
      renameSync(path + ".tmp", path);
    }
    lastDiagnostic = { observed: true, at: new Date().toISOString(), observedAt, provider,
      model: ctx.model?.id, status: event.status, subscriptionHeaders: safeHeaders, parsed: next };
    const diagnosticPath = join(cache, "transport-diagnostic.json");
    const diagnosticTemp = diagnosticPath + `.${process.pid}.tmp`;
    writeFileSync(diagnosticTemp, JSON.stringify(lastDiagnostic, null, 2), { mode: 0o600 });
    renameSync(diagnosticTemp, diagnosticPath);
    refresh?.();
  });
  pi.on("message_end", event => {
    if (event.message.role === "assistant") {
      const message = event.message;
      const started = generatingSince;
      const ended = performance.now();
      const elapsed = message.durationMs ?? (started === undefined ? undefined : ended - started);
      if (turnTiming && started !== undefined) {
        const split = Math.min(ended, Math.max(started, stream.firstOutput ?? ended));
        turnTiming.spans.push({ phase: "wait", from: started, to: split }, { phase: "generation", from: split, to: ended });
      }
      generatingSince = undefined;
      const failed = message.stopReason === "error" || message.stopReason === "aborted";
      if (message.stopReason === "error") error = true;
      if (elapsed !== undefined && elapsed > 0) {
        const reasoning = message.usage.reasoning;
        const hasTools = stream.toolCall || message.content.some(block => block.type === "toolCall");
        const textTokens = reasoning === undefined || hasTools ? undefined : message.usage.output - reasoning;
        const textSeconds = stream.firstText !== undefined && stream.lastText !== undefined ? (stream.lastText - stream.firstText) / 1000 : undefined;
        const unavailable = failed ? "Response failed or was aborted" : hasTools ? "Output includes tool-call tokens" : reasoning === undefined ? "Provider did not separate reasoning tokens" : !textTokens ? "No text tokens" : stream.textChunks < 2 || !textSeconds ? "Text arrived in fewer than two timed chunks" : undefined;
        if (turnTiming && unavailable === undefined && textTokens !== undefined && textSeconds !== undefined) {
          turnTiming.tokens += textTokens;
          turnTiming.textSeconds += textSeconds;
        }
        lastResponse = {
          seconds: elapsed / 1000,
          firstOutputSeconds: started !== undefined && stream.firstOutput !== undefined ? (stream.firstOutput - started) / 1000 : undefined,
          firstTextSeconds: started !== undefined && stream.firstText !== undefined ? (stream.firstText - started) / 1000 : undefined,
          textSeconds, textChunks: stream.textChunks, outputTokens: message.usage.output,
          reasoningTokens: reasoning, textTokens,
          speed: unavailable === undefined && textTokens !== undefined && textSeconds !== undefined ? textTokens / textSeconds : undefined,
          speedUnavailableReason: unavailable,
        };
      } else lastResponse = undefined;
    }
    refresh?.();
    redraw?.();
  });
  pi.on("ui_prompt_start", () => { waitingForUser = true; publishSession(); });
  pi.on("ui_prompt_end", () => { waitingForUser = false; publishSession(); });
  pi.on("session_shutdown", () => {
    clearInterval(sessionTimer);
    sessionContext = undefined;
    rmSync(sessionFile, { force: true });
  });
  pi.on("model_select", () => { refresh?.(); redraw?.(); });
  pi.on("thinking_level_select", () => { refresh?.(); redraw?.(); });
  pi.registerCommand("statusline", {
    description: "Toggle the original dotfiles status line adapted for Pi",
    handler: async (_args, ctx) => { enabled = !enabled; install(ctx); },
  });
}
