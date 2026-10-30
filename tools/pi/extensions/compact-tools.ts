import { stripVTControlCharacters } from "node:util";
import type { ExtensionAPI, ToolRenderers } from "@earendil-works/pi-coding-agent";
import { Text, truncateToWidth } from "@earendil-works/pi-tui";

const frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

function clean(text: string): string {
  return stripVTControlCharacters(text).replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "");
}

function preview(args: Record<string, unknown>): string {
  const value = args.path ?? args.file_path ?? args.command ?? args.pattern ?? args.query ?? args.url;
  return clean(typeof value === "string" ? value : JSON.stringify(args)).replace(/\s+/g, " ").trim();
}

export default function compactTools(pi: ExtensionAPI) {
  const pending = new Map<string, () => void>();
  let timer: ReturnType<typeof setInterval> | undefined;
  let interactive = false;
  let active = false;

  function stop() {
    if (timer) clearInterval(timer);
    timer = undefined;
    pending.clear();
  }

  pi.on("session_start", (_event, ctx) => {
    stop();
    active = false;
    interactive = ctx.mode === "tui";
  });
  pi.on("agent_start", () => { active = true; });
  pi.on("agent_end", () => {
    active = false;
    stop();
  });
  pi.on("session_shutdown", () => {
    interactive = false;
    active = false;
    stop();
  });
  pi.on("tool_execution_end", event => {
    pending.delete(event.toolCallId);
    if (pending.size === 0) stop();
  });

  // Only rendering changes; tool definitions, execution and model-facing results stay intact.
  pi.registerToolRenderer(toolName => {
    const renderers: ToolRenderers = {
      renderShell: "self",
      renderCall(args, theme, context) {
        const running = context.isPartial && context.executionStarted;
        if (running && interactive && active) {
          pending.set(context.toolCallId, context.invalidate);
          timer ??= setInterval(() => {
            for (const invalidate of pending.values()) invalidate();
          }, 100);
          timer.unref();
        } else {
          pending.delete(context.toolCallId);
          if (pending.size === 0) stop();
        }

        const mark = context.isPartial
          ? running ? frames[Math.floor(Date.now() / 100) % frames.length] : "○"
          : context.isError ? "✕" : "✓";
        const color = context.isPartial ? running ? "warning" : "muted" : context.isError ? "error" : "success";
        const prefix = theme.fg(color, mark) + " "
          + theme.fg("toolTitle", theme.bold(clean(toolName))) + " ";
        const expanded = toolName === "bash" ? !context.expanded : context.expanded;
        const suffix = " " + theme.fg("dim", expanded ? "▾" : "▸");
        const stats = toolName === "edit" && !context.isPartial && !context.isError
          ? context.state.diffStats as { added: number; removed: number } | undefined : undefined;
        const summary = theme.fg("toolOutput", preview(args ?? {})) + (stats
          ? ` ${theme.fg("success", `+${stats.added}`)} ${theme.fg("error", `−${stats.removed}`)}` : "");
        const padding = " ".repeat(context.outputPad);
        const argumentsText = expanded ? clean(JSON.stringify(args ?? {}, null, 2)) : "";
        return {
          render(width) {
            const line = truncateToWidth(padding + prefix + summary, Math.max(0, width - 2));
            const header = truncateToWidth(line + suffix, width);
            if (!expanded || toolName === "bash") return [header];
            const body = new Text(theme.fg("muted", argumentsText), 0, 0)
              .render(Math.max(1, width - padding.length - 3));
            return [header, ...body.map(row => truncateToWidth(padding + "   " + row, width))];
          },
          invalidate() {},
        };
      },
      renderResult(result, { expanded, isPartial }, theme, context) {
        const details = result.details as { diff?: unknown } | undefined;
        const diff = typeof details?.diff === "string" ? clean(details.diff) : undefined;
        if (toolName === "edit" && !isPartial && !context.isError && diff && context.state.statsDiff !== diff) {
          const lines = diff.split("\n");
          context.state.diffStats = {
            added: lines.filter(line => /^\+\s*\d+\s/.test(line)).length,
            removed: lines.filter(line => /^-\s*\d+\s/.test(line)).length,
          };
          context.state.statsDiff = diff;
          queueMicrotask(context.invalidate);
        }
        if (!(toolName === "bash" ? !expanded : expanded)) return new Text("", 0, 0);
        const output = result.content.map(block => {
          if (block.type === "text") return clean(block.text);
          if (block.type === "image") return `[image: ${clean(block.mimeType)}]`;
          return `[${clean(block.type)}]`;
        }).join("\n");
        const text = diff ? diff.split("\n").map(line => theme.fg(
          line.startsWith("+") ? "success" : line.startsWith("-") ? "error" : "toolOutput", line,
        )).join("\n") : theme.fg(context.isError ? "error" : "toolOutput", output);
        const padding = " ".repeat(context.outputPad);
        const content = new Text(text, 0, 0);
        return {
          render(width) {
            return content.render(Math.max(1, width - padding.length - 3))
              .map(row => truncateToWidth(padding + "   " + row, width));
          },
          invalidate() { content.invalidate(); },
        };
      },
    };
    return renderers;
  });
}
