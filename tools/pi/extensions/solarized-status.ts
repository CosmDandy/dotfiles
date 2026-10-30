import { CustomEditor, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { sliceByColumn, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

type Window = { used_percentage: number; resets_at: number };
// Only actual subscription-window headers, never requests/minute or tokens/minute.
export function parseLimits(raw: Record<string, string>, now = Date.now() / 1000) {
  const h = Object.fromEntries(Object.entries(raw).map(([k, v]) => [k.toLowerCase(), v]));
  const result: { five_hour?: Window; seven_day?: Window } = {};
  const number = (key: string) => h[key] == null ? NaN : Number(h[key]);
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
  for (const [suffix, key] of [["5h", "five_hour"], ["7d", "seven_day"]] as const) {
    const prefix = `anthropic-ratelimit-unified-${suffix}-`;
    const utilization = number(prefix + "utilization"), reset = number(prefix + "reset");
    if (Number.isFinite(utilization) && utilization >= 0 && Number.isFinite(reset))
      result[key] = { used_percentage: utilization * 100, resets_at: reset };
  }
  return result;
}

export default function (pi: ExtensionAPI) {
  const root = join(homedir(), ".pi", "agent");
  let enabled = true;
  let refresh: (() => void) | undefined;
  let redraw: (() => void) | undefined;
  let busy = false;
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
  const seconds = (value: number) => `${value.toFixed(1).replace(".", ",")} s`;
  function responseStats() {
    if (generatingSince !== undefined) return seconds((performance.now() - generatingSince) / 1000);
    if (!lastResponse) return "— s · — tok/s";
    return seconds(lastResponse.seconds) + (lastResponse.speed === undefined ? " · — tok/s" : ` · ≈${lastResponse.speed.toFixed(1).replace(".", ",")} tok/s`);
  }
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
  // Separate observations per provider, model and session. No credentials read.
  const observations = new Map<string, ReturnType<typeof parseLimits>>();
  let lastDiagnostic: object = { observed: false, note: "No provider response observed since reload" };
  pi.registerCommand("statusline-limits", {
    description: "Show observed subscription-window headers (no credentials)",
    handler: async () => {
      pi.sendMessage({
        customType: "statusline-limits",
        content: "Subscription window transport diagnostic:\n```json\n" + JSON.stringify(lastDiagnostic, null, 2) + "\n```",
        display: true,
      }, { triggerTurn: false });
    },
  });
  const key = (ctx: ExtensionContext) => `${ctx.sessionManager.getSessionId()}:${ctx.model?.provider}:${ctx.model?.id}`;
  function install(ctx: ExtensionContext) {
    if (ctx.mode !== "tui") return;
    if (!enabled) {
      ctx.ui.setEditorComponent(undefined);
      ctx.ui.setWorkingVisible(true);
      ctx.ui.setWidget("statusline-half-edge", undefined);
      ctx.ui.setFooter(undefined);
      refresh = undefined;
      redraw = undefined;
      return;
    }
    ctx.ui.setWorkingVisible(false);
    ctx.ui.setFooter((tui, _theme, data) => {
      let width = 100, line = "", identity = "", footerHints = "", pending = false, dirty = false, disposed = false;
      const stripeColor = () => {
        const theme = ctx.ui.theme;
        return activeTools.size ? theme.colors.warning : generatingSince !== undefined
          ? phase === "Thinking" ? theme.colors.thinkingHigh : phase === "Generating" ? theme.colors.thinkingMedium : phase === "Preparing" ? theme.colors.warning : theme.colors.thinkingLow
          : theme.colors.dim;
      };
      ctx.ui.setWidget("statusline-half-edge", () => ({
        invalidate() {},
        render(columns: number) {
          if (columns < 6) return [" ".repeat(columns)];
          const theme = ctx.ui.theme;
          return ["\x1b[49m " + theme.style("╻", { fg: stripeColor(), dim: true }) +
            theme.style("▄".repeat(columns - 3), { fg: theme.colors.customMessageBg }) + " "];
        },
      }));
      const paintCard = (text: string, columns: number) => {
        if (columns < 6) return truncateToWidth(text, columns);
        const theme = ctx.ui.theme;
        const background = theme.getBgAnsi("customMessageBg");
        // Centered box-drawing strokes join ╻/╹; a left-aligned ▎ cannot.
        const stripe = theme.style("┃", { fg: stripeColor(), dim: true });
        const content = sliceByColumn(text, 2, columns - 3);
        return "\x1b[49m " + stripe + background + content.replace(/\x1b\[(?:0|49)?m/g, escape => escape + background) + "\x1b[49m ";
      };
      let child: ReturnType<typeof spawn> | undefined;
      function update() {
        if (disposed) return;
        if (pending) { dirty = true; return; }
        pending = true;
        const tmp = join(root, "cache", "statusline", encodeURIComponent(ctx.model?.provider ?? "unknown"));
        mkdirSync(tmp, { recursive: true, mode: 0o700 });
        let cost = 0;
        let current: { input: number; cacheRead: number; cacheWrite: number } | undefined;
        for (const entry of ctx.sessionManager.getBranch()) {
          if (entry.type === "message" && entry.message.role === "assistant") {
            cost += entry.message.usage.cost.total;
            current = entry.message.usage;
          }
        }
        const usage = ctx.getContextUsage();
        const limits = { ...observations.get(key(ctx)) };
        const now = Date.now() / 1000;
        for (const k of ["five_hour", "seven_day"] as const)
          if (limits[k] && limits[k]!.resets_at <= now) delete limits[k];
        const payload = {
          model: { display_name: ctx.model?.name ?? ctx.model?.id ?? "No model", id: ctx.model?.id },
          context_window: {
            used_percentage: usage?.percent ?? 0,
            context_window_size: usage?.contextWindow ?? ctx.model?.contextWindow,
            current_usage: current ? { input_tokens: current.input, cache_read_input_tokens: current.cacheRead, cache_creation_input_tokens: current.cacheWrite } : {},
          },
          thinking: { enabled: pi.getThinkingLevel() !== "off" },
          effort: { level: pi.getThinkingLevel() },
          cost: { total_cost_usd: cost }, rate_limits: limits,
        };
        child = spawn(join(root, "bin", "solarized-statusline"), [], {
          env: { ...process.env, TMPDIR: tmp, COLUMNS: String(Math.max(1, width - (width >= 79 && footerHints ? visibleWidth(footerHints) + 3 : 0))), CLAUDE_STATUSLINE_MARGIN: "0", PI_STATUSLINE_LAYOUT: "split" },
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
          if (code === 0) {
            try {
              const rendered = JSON.parse(output);
              identity = rendered.identity;
              line = rendered.info;
            } catch {
              line = "Status line unavailable: check pi-statusline installation (see tools/pi/README.md)";
            }
          } else line = "Status line unavailable: check pi-statusline installation (see tools/pi/README.md)";
          tui.requestRender();
          if (dirty) { dirty = false; update(); }
        });
      }
      refresh = update;
      const requestRender = () => tui.requestRender();
      redraw = requestRender;
      const timer = setInterval(update, 15000);
      // Queue state can change without a model or tool event.
      let queued = ctx.hasPendingMessages();
      const clock = setInterval(() => {
        const nextQueued = ctx.hasPendingMessages();
        if (busy || generatingSince !== undefined || queued !== nextQueued) requestRender();
        queued = nextQueued;
      }, 100);
      ctx.ui.setEditorComponent((editorTui, editorTheme, keybindings) => {
        const hint = (action: "app.model.select" | "app.thinking.cycle", label: string) => {
          const keys = keybindings.getKeys(action);
          return keys.length ? `${keys[0]} ${label}` : "";
        };
        footerHints = [hint("app.model.select", "model"), hint("app.thinking.cycle", "effort")].filter(Boolean).join(" · ");
        class StatusEditor extends CustomEditor {
          // Pi reapplies stock editor padding after installing a custom editor.
          setPaddingX(_padding: number): void { super.setPaddingX(3); }
          render(columns: number): string[] {
            const lines = super.render(columns);
            if (columns < 6) return lines;
            // Keep row/column geometry intact for cursor placement and autocomplete clicks.
            return lines.map(text => paintCard(text, columns));
          }
          private fit(columns: number, left: string, right = "") {
            const innerWidth = Math.max(0, columns - 6);
            if (columns < 6) return " ".repeat(columns);
            const rightText = truncateToWidth(right, Math.max(0, innerWidth - 4));
            const leftText = truncateToWidth(left, Math.max(0, innerWidth - visibleWidth(rightText) - (rightText ? 2 : 0)));
            const gap = Math.max(0, innerWidth - visibleWidth(leftText) - visibleWidth(rightText));
            return "   " + leftText + " ".repeat(gap) + rightText + "   ";
          }
          protected renderTopBorder(columns: number, hiddenLineCount: number): string {
            const innerWidth = Math.max(0, columns - 6);
            if (innerWidth !== width) { width = innerWidth; update(); }
            const theme = ctx.ui.theme;
            const state = activeTools.size ? "Running" : generatingSince !== undefined ? phase : busy ? "Active" : interrupted ? "Interrupted" : "Ready";
            const phases = {
              Waiting: { frames: ["⠂", "⠒", "⠲", "⠴", "⠤", "⠠"], color: theme.colors.thinkingLow },
              Thinking: { frames: thinkingFrames, color: theme.colors.thinkingHigh },
              Generating: { frames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"], color: theme.colors.thinkingMedium },
              Preparing: { frames: ["·", "•", "●", "•"], color: theme.colors.warning },
              Running: { frames: ["⠁", "⠂", "⠄", "⡀", "⢀", "⠠", "⠐", "⠈"], color: theme.colors.warning },
              Active: { frames: ["⠂", "⠒", "⠲", "⠴", "⠤", "⠠"], color: theme.colors.dim },
            };
            const animation = state in phases ? phases[state as keyof typeof phases] : undefined;
            const frame = animation?.frames[Math.floor(performance.now() / 150) % animation.frames.length];
            const stateLabel = animation ? theme.style(`${frame} ${state}`, { fg: animation.color, dim: true }) : theme.fg("muted", `${interrupted ? "■" : "·"} ${state}`);
            const toolNames = activeTools.size ? theme.fg("dim", [...new Set(activeTools.values())].join(", ")) : "";
            const badges = [error ? theme.fg("error", "error") : "", ctx.hasPendingMessages() ? theme.fg("warning", "queued") : "", hiddenLineCount ? `↑ ${hiddenLineCount} more` : ""].filter(Boolean);
            const statuses = [...data.getExtensionStatuses().values()];
            const left = [stateLabel, toolNames, ...badges, ...statuses].filter(Boolean).join(theme.fg("dim", " · "));
            return this.fit(columns, left, theme.fg("muted", responseStats()));
          }
          protected renderBottomBorder(columns: number, hiddenLineCount: number): string {
            const innerWidth = Math.max(0, columns - 6);
            const bottom = truncateToWidth(identity, innerWidth);
            return this.fit(columns, bottom, hiddenLineCount ? `↓ ${hiddenLineCount} more` : "");
          }
        }
        return new StatusEditor(editorTui, editorTheme, keybindings, { paddingX: 3 });
      });
      update();
      return {
        invalidate() {},
        render(columns: number) {
          const innerWidth = Math.max(0, columns - 6);
          const hints = columns >= 85 ? footerHints : "";
          const reserved = visibleWidth(hints) + (hints ? 3 : 0);
          // Resize and hint visibility affect the Go renderer's right-hand budget.
          if (width !== innerWidth) { width = innerWidth; update(); }
          const info = truncateToWidth(line, Math.max(0, innerWidth - reserved));
          const general = ctx.ui.theme.fg("dim", hints) + (hints ? "   " : "") + info;
          const theme = ctx.ui.theme;
          // Upper-half blocks extend the panel by half a cell without painting a full row.
          const edge = columns < 6 ? " ".repeat(columns) : " " +
            theme.style("╹", { fg: stripeColor(), dim: true }) +
            theme.style("▀".repeat(columns - 3), { fg: theme.colors.customMessageBg }) + " ";
          return [
            "\x1b[49m" + edge,
            truncateToWidth("   " + general + "   ", columns),
          ];
        },
        dispose() {
          disposed = true;
          ctx.ui.setWidget("statusline-half-edge", undefined);
          clearInterval(timer);
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
    error = false;
    interrupted = false;
    activeTools.clear();
    install(ctx);
  });
  pi.on("agent_start", () => {
    busy = true;
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
    activeTools.set(event.toolCallId, event.toolName);
    redraw?.();
  });
  pi.on("tool_execution_end", event => {
    activeTools.delete(event.toolCallId);
    if (event.isError) error = true;
    redraw?.();
  });
  pi.on("agent_settled", event => {
    busy = false;
    generatingSince = undefined;
    interrupted = event.aborted;
    activeTools.clear();
    redraw?.();
  });
  pi.on("after_provider_response", async (event, ctx) => {
    const next = parseLimits(event.headers);
    const safeHeaders = Object.fromEntries(Object.entries(event.headers).filter(([name]) =>
      /^x-codex-(primary|secondary)-(used-percent|window-minutes|reset-at|reset-after-seconds)$/i.test(name) ||
      /^anthropic-ratelimit-unified-(5h|7d)-(utilization|reset)$/i.test(name)));
    lastDiagnostic = { observed: true, at: new Date().toISOString(), provider: ctx.model?.provider,
      model: ctx.model?.id, status: event.status, subscriptionHeaders: safeHeaders, parsed: next };
    mkdirSync(join(root, "cache", "statusline"), { recursive: true, mode: 0o700 });
    writeFileSync(join(root, "cache", "statusline", "transport-diagnostic.json"), JSON.stringify(lastDiagnostic, null, 2), { mode: 0o600 });
    if (Object.keys(next).length) observations.set(key(ctx), { ...observations.get(key(ctx)), ...next });
    refresh?.();
  });
  pi.on("message_end", event => {
    if (event.message.role === "assistant") {
      const message = event.message;
      const started = generatingSince;
      const elapsed = message.durationMs ?? (started === undefined ? undefined : performance.now() - started);
      generatingSince = undefined;
      const failed = message.stopReason === "error" || message.stopReason === "aborted";
      if (message.stopReason === "error") error = true;
      if (elapsed !== undefined && elapsed > 0) {
        const reasoning = message.usage.reasoning;
        const hasTools = stream.toolCall || message.content.some(block => block.type === "toolCall");
        const textTokens = reasoning === undefined || hasTools ? undefined : message.usage.output - reasoning;
        const textSeconds = stream.firstText !== undefined && stream.lastText !== undefined ? (stream.lastText - stream.firstText) / 1000 : undefined;
        const unavailable = failed ? "Response failed or was aborted" : hasTools ? "Output includes tool-call tokens" : reasoning === undefined ? "Provider did not separate reasoning tokens" : !textTokens ? "No text tokens" : stream.textChunks < 2 || !textSeconds ? "Text arrived in fewer than two timed chunks" : undefined;
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
  pi.on("model_select", () => { refresh?.(); redraw?.(); });
  pi.on("thinking_level_select", () => { refresh?.(); redraw?.(); });
  pi.registerCommand("statusline", {
    description: "Toggle the original dotfiles status line adapted for Pi",
    handler: async (_args, ctx) => { enabled = !enabled; install(ctx); },
  });
}
