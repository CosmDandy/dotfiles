import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { setTimeout as delay } from "node:timers/promises";

const source = fileURLToPath(new URL("../", import.meta.url));
const packageDir = process.env.PI_TEST_SUBAGENTS;
assert.ok(packageDir, "PI_TEST_SUBAGENTS must point to the Nix-built lib/node_modules");
const directory = mkdtempSync(join(tmpdir(), "pi-subagents-"));
const agent = join(directory, ".pi", "agent");
const log = join(directory, "requests.jsonl");
const provider = join(agent, "extensions", "provider.ts");
const socket = `pi-subagents-${process.pid}`;
const tmux = (...args) => execFileSync("tmux", ["-f", "/dev/null", "-L", socket, ...args], { encoding: "utf8" });
let pane;
const send = (...keys) => tmux("send-keys", "-t", pane, ...keys);
const prompt = text => { send("-l", text); send("Enter"); };
const frame = () => tmux("capture-pane", "-p", "-t", pane);
const requests = () => existsSync(log) ? readFileSync(log, "utf8").trim().split("\n").filter(Boolean).map(JSON.parse) : [];

async function waitFor(predicate, label) {
  const until = Date.now() + 15000;
  do {
    if (predicate()) return;
    await delay(60);
  } while (Date.now() < until);
  assert.fail(`${label} did not appear:\n${frame()}\n${JSON.stringify(requests())}`);
}

try {
  mkdirSync(join(agent, "extensions", "subagent"), { recursive: true });
  symlinkSync(packageDir, join(agent, "subagent-package"));
  symlinkSync(join(source, "agents"), join(agent, "agents"));
  symlinkSync(join(source, "keybindings.json"), join(agent, "keybindings.json"));
  symlinkSync(join(source, "extensions", "work-mode.ts"), join(agent, "extensions", "work-mode.ts"));
  symlinkSync(join(source, "subagents", "config.json"), join(agent, "extensions", "subagent", "config.json"));
  const settings = JSON.parse(readFileSync(join(source, "settings.json"), "utf8"));
  const scope = settings.subagents.modelScope;
  assert.deepEqual(scope.allow, settings.enabledModels.map(model => model.split(":")[0]));
  const fixture = {
    quietStartup: true,
    enabledModels: ["probe/main:xhigh", "probe/quick:medium", "probe/other:xhigh"],
    subagents: {
      ...settings.subagents,
      defaultExtensions: [provider],
      defaultModel: "probe/quick:medium",
      modelScope: { ...scope, allow: ["probe/main", "probe/quick", "probe/other"] },
    },
  };
  writeFileSync(join(agent, "settings.json"), JSON.stringify(fixture));
  writeFileSync(provider, `import { appendFileSync } from "node:fs";
import { createAssistantMessageEventStream } from "@earendil-works/pi-ai";
export default pi => {
  pi.registerProvider("probe", {
    baseUrl: "http://127.0.0.1:1", apiKey: "fake", api: "probe",
    models: ["main", "other", "outside"].map(id => ({
      id, name: id, reasoning: true, thinkingLevelMap: { xhigh: "xhigh" }, input: ["text"], contextWindow: 100_000,
      maxTokens: 1000, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    })),
    streamSimple(model, context, options) {
      const stream = createAssistantMessageEventStream();
      const messages = context.messages.filter(m => m.role === "user").map(m => typeof m.content === "string"
        ? m.content : m.content.filter(c => c.type === "text").map(c => c.text).join(""));
      const last = messages.at(-1);
      const key = last?.match(/child_[a-z_]+_sentinel/g)?.at(-1) ?? last;
      const text = "DONE " + key;
      const call = key === "parallel_probe" && !context.messages.some(m => m.role === "toolResult" && m.toolCallId === "parallel-probe") ? {
        type: "toolCall", id: "parallel-probe", name: "subagent",
        arguments: { tasks: [
          { agent: "scout", task: "child_batch_one_sentinel" },
          { agent: "reviewer", task: "child_batch_two_sentinel" },
        ], async: false },
      } : undefined;
      const response = {
        role: "assistant", content: [call ?? { type: "text", text }], api: model.api, provider: model.provider, model: model.id,
        usage: { input: 10, output: 10, cacheRead: 0, cacheWrite: 0, totalTokens: 20, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
        timestamp: Date.now(), stopReason: call ? "toolUse" : "stop",
      };
      const trace = data => appendFileSync(process.env.PROBE_LOG, JSON.stringify({ key, model: model.id, time: Date.now(), ...data }) + "\\n");
      trace({ phase: "start", reasoning: options?.reasoning, inherited: messages.includes("parent_history_sentinel") });
      setTimeout(() => {
        stream.push({ type: "start", partial: response });
        if (call) {
          stream.push({ type: "toolcall_start", contentIndex: 0, partial: response });
          stream.push({ type: "toolcall_end", contentIndex: 0, toolCall: call, partial: response });
        } else {
          stream.push({ type: "text_start", contentIndex: 0, partial: response });
          stream.push({ type: "text_delta", contentIndex: 0, delta: text, partial: response });
          stream.push({ type: "text_end", contentIndex: 0, content: text, partial: response });
        }
        stream.push({ type: "done", reason: response.stopReason, message: response });
        stream.end();
        trace({ phase: "end" });
      }, key?.startsWith("child_batch_") ? 1800 : 0);
      return stream;
    },
  });
  pi.registerVirtualModel({
    provider: "probe", id: "quick", name: "Quick probe", thinkingLevels: ["medium"],
    route(_request, ctx) { return { model: ctx.modelRegistry.find("probe", "other"), thinkingLevel: "medium" }; },
  });
};
`);

  pane = tmux("new-session", "-d", "-P", "-F", "#{pane_id}", "-c", directory, "-x", "115", "-y", "45",
    "env", "-i", `PATH=${process.env.PATH}`, `HOME=${directory}`, `PI_CODING_AGENT_DIR=${agent}`,
    `PROBE_LOG=${log}`, "TERM=xterm-256color", "PI_TELEMETRY=0", process.env.PI_TEST_BIN ?? "pi",
    "--offline", "--no-approve", "--no-mcp", "--tui-mode", "regular", "--model", "probe/main:xhigh", "parent_history_sentinel").trim();
  await waitFor(() => frame().includes("DONE parent_history_sentinel"), "parent prompt");
  prompt("/subagents");
  const roles = ["code-reviewer", "compliance-audit", "devils-advocate", "performance-audit", "skeptic", "ux-audit"];
  await waitFor(() => frame().includes("ux-audit [user]"), "managed role list");
  const roleList = frame();
  for (const role of roles) {
    assert.ok(roleList.includes(`${role} [user] · openai-codex/gpt-6.2-astra:xhigh`), `missing managed Astra role: ${role}`);
  }
  send("Escape");
  await waitFor(() => !frame().includes("ux-audit [user]"), "close role list");
  prompt("/run scout child_denied_sentinel");
  await waitFor(() => frame().includes("Enable Agents with Option+G in Execute"), "disabled launch guard");
  prompt("/agents");
  await waitFor(() => frame().includes("Subagent fleet inspector"), "fleet menu");
  send("Escape");
  await waitFor(() => !frame().includes("Subagent fleet inspector"), "close fleet menu");
  prompt("/subagents reviewer model");
  await waitFor(() => frame().includes("Select model for reviewer"), "model picker");
  assert.match(frame(), /main/);
  assert.match(frame(), /quick/);
  assert.match(frame(), /other/);
  assert.doesNotMatch(frame(), /outside/);
  send("Escape");
  await waitFor(() => !frame().includes("Select model for reviewer"), "close model picker");
  send("M-g");
  await waitFor(() => /EXECUTE.*AGENTS/.test(frame()), "Agents status");
  send("BTab");
  await waitFor(() => frame().includes("EXPLORE"), "Explore mode");
  prompt("/run scout child_explore_sentinel");
  await waitFor(() => frame().includes("Switch to Execute before launching a subagent"), "Explore launch guard");
  send("BTab");
  await waitFor(() => /EXECUTE.*AGENTS/.test(frame()), "return to Execute");
  prompt("/run scout child_fresh_sentinel");
  await waitFor(() => frame().includes("DONE child_fresh_sentinel"), "fresh run with default virtual model");
  prompt("/run reviewer[model=probe/main:xhigh] child_fork_sentinel --fork");
  await waitFor(() => frame().includes("DONE child_fork_sentinel"), "fork run with a per-run override");
  prompt("/run scout[model=probe/outside] child_outside_sentinel");
  await waitFor(() => frame().includes("outside the configured subagent model scope"), "model-scope rejection");
  prompt("parallel_probe");
  await waitFor(() => frame().includes("DONE parallel_probe"), "parallel result");
  prompt("/run scout child_bg_sentinel --bg");
  await waitFor(() => requests().some(r => r.key === "child_bg_sentinel" && r.model === "other" && r.phase === "end"), "background child");
  const results = requests();
  const batch = results.filter(r => r.key?.startsWith("child_batch_") && r.model === "other");
  assert.equal(new Set(batch.map(r => r.key)).size, 2);
  assert.equal(batch.filter(r => r.phase === "end").length, 2);
  assert.ok(Math.max(...batch.filter(r => r.phase === "start").map(r => r.time)) < Math.min(...batch.filter(r => r.phase === "end").map(r => r.time)), "the children actually overlapped");
  assert.ok(results.some(r => r.key === "child_fresh_sentinel" && r.model === "other" && r.reasoning === "medium" && !r.inherited));
  assert.ok(results.some(r => r.key === "child_fork_sentinel" && r.model === "main" && r.reasoning === "xhigh" && r.inherited));
  assert.ok(!results.some(r => r.model === "outside" || r.key === "child_denied_sentinel" || r.key === "child_explore_sentinel"));
  console.log("PASS: linked roles, /agents, Option+G, Explore, strict model scope, fresh, fork, parallel and background");
} finally {
  try { tmux("kill-server"); } catch {}
  rmSync(directory, { recursive: true, force: true });
}
