import { compact, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

const instructions = `Preserve in my words, not a paraphrase:
- the task, what "done" means, and what was still open;
- every decision with the reason for it and the option not taken;
- what failed and the symptom it actually produced — a summary drops this first,
  and it is the most expensive thing to rediscover;
- what worked — the exact invocation, not a description of it;
- files touched and what changed in each.

Drop: file contents, tool output, search results, superseded reasoning.`;

export default function (pi: ExtensionAPI) {
  pi.on("session_before_compact", async (event, ctx) => {
    const { model, modelRegistry } = ctx;
    if (!model) return { cancel: true };
    const focus = [instructions, event.customInstructions].filter(Boolean).join("\n\n");
    try {
      const compaction = await compact(
        event.preparation, model, undefined, undefined, focus, event.signal,
        ctx.thinkingLevel, (model, context, options) => modelRegistry.streamSimple(model, context, options),
      );
      return { compaction };
    } catch (error) {
      // A thrown hook error would fall through to a second, uncustomized compaction.
      if (!event.signal.aborted) ctx.ui.notify(`Compaction failed: ${error instanceof Error ? error.message : error}`, "error");
      return { cancel: true };
    }
  });
}
