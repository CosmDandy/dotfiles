// Local provider for the tmux key-to-frame benchmark. Children stream until the harness releases them.
import { appendFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { createAssistantMessageEventStream } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  const home = process.env.HOME!, n = Number(process.env.PANE_CHILDREN);
  const trace = (s: string) => appendFileSync(join(home, "trace"), s + "\n");
  const cost = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
  pi.events.on("dotfiles:pane-hidden", hidden => trace("hidden " + hidden));
  pi.registerProvider("pane-fixture", {
    api: "pane-fixture", baseUrl: "http://127.0.0.1:1", apiKey: "fake",
    models: [{ id: "local", name: "Pane fixture", input: ["text"], contextWindow: 100000, maxTokens: 1000, reasoning: false, cost }],
    streamSimple(model, ctx, options) {
      const stream = createAssistantMessageEventStream();
      const users = ctx.messages.filter(m => m.role === "user");
      const child = JSON.stringify(users.at(-1)?.content).match(/LATENCY_CHILD_[0-9]+/)?.[0];
      const call = !child && n > 0 && !ctx.messages.some(m => m.role === "toolResult" && m.toolCallId === "fleet")
        ? { type: "toolCall" as const, id: "fleet", name: "subagent", arguments: { async: true,
          tasks: Array.from({ length: n }, (_,i) => ({ agent: "scout", task: "LATENCY_CHILD_" + i })) } } : undefined;
      const text = { type: "text" as const, text: child ? "" : "MOCK_BOOT_DONE" };
      const message = { role: "assistant" as const, api: model.api, provider: model.provider, model: model.id, timestamp: Date.now(),
        content: [call ?? text], stopReason: call ? "toolUse" as const : "stop" as const,
        usage: { input: 3, output: 4, totalTokens: 7, cacheRead: 0, cacheWrite: 0, cost: { ...cost, total: 0 } } };
      stream.push({ type: "start", partial: message });
      const finish = () => { stream.push({type:"done",reason:message.stopReason,message});stream.end(); };
      if (call) {
        stream.push({type:"toolcall_start",contentIndex:0,partial:message});
        stream.push({type:"toolcall_end",contentIndex:0,toolCall:call,partial:message}); finish();
      } else {
        stream.push({type:"text_start",contentIndex:0,partial:message});
        if (child) {
          trace("start " + child);
          const clock = setInterval(() => {
            if (existsSync(join(home,"release")) || options?.signal?.aborted) {
              clearInterval(clock);stream.push({type:"text_end",contentIndex:0,content:text.text,partial:message});
              finish();trace("end " + child);
            } else {
              text.text += ".";stream.push({type:"text_delta",contentIndex:0,delta:".",partial:message});trace("tick " + child);
            }
          },250);
        } else {
          stream.push({type:"text_delta",contentIndex:0,delta:text.text,partial:message});
          stream.push({type:"text_end",contentIndex:0,content:text.text,partial:message});finish();
        }
      }
      return stream;
    },
  });
}
