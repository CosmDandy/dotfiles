import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, globSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
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
  const git = (...args) => execFileSync("git", ["-C", directory, "-c", "user.name=Probe", "-c", "user.email=probe@example.invalid", "-c", "core.hooksPath=/dev/null", ...args], { encoding: "utf8" });
  git("init", "-q");
  const workFile = join(directory, "work.txt");
  writeFileSync(workFile, "initial\n");
  git("add", "--", "work.txt");
  git("commit", "-qm", "Fixture", "--no-gpg-sign");
  mkdirSync(join(agent, "extensions", "subagent"), { recursive: true });
  symlinkSync(packageDir, join(agent, "subagent-package"));
  const statusline = process.env.PI_TEST_STATUSLINE ?? join(homedir(), ".pi", "agent", "bin", "solarized-statusline");
  assert.ok(existsSync(statusline), "set PI_TEST_STATUSLINE to the built statusline renderer");
  mkdirSync(join(agent, "bin"));
  symlinkSync(statusline, join(agent, "bin", "solarized-statusline"));
  symlinkSync(join(source, "agents"), join(agent, "agents"));
  symlinkSync(join(source, "themes"), join(agent, "themes"));
  symlinkSync(join(source, "keybindings.json"), join(agent, "keybindings.json"));
  for (const name of ["work-mode", "compact-tools", "solarized-status"]) {
    symlinkSync(join(source, "extensions", `${name}.ts`), join(agent, "extensions", `${name}.ts`));
  }
  symlinkSync(join(source, "subagents", "config.json"), join(agent, "extensions", "subagent", "config.json"));
  const settings = JSON.parse(readFileSync(join(source, "settings.json"), "utf8"));
  const scope = settings.subagents.modelScope;
  assert.deepEqual(scope.allow, settings.enabledModels.map(model => model.split(":")[0]));
  const fixture = {
    quietStartup: true,
    theme: "solarized-dark",
    enabledModels: ["probe/main:xhigh", "probe/quick:medium", "probe/other:xhigh"],
    subagents: {
      ...settings.subagents,
      defaultExtensions: [provider],
      defaultModel: "probe/quick:medium",
      agentOverrides: {
        ...settings.subagents.agentOverrides,
        scout: { ...settings.subagents.agentOverrides.scout, acceptanceRole: "read-only" },
        "code-reviewer": { acceptanceRole: "read-only" },
      },
      modelScope: { ...scope, allow: ["probe/main", "probe/quick", "probe/other"] },
    },
  };
  writeFileSync(join(agent, "settings.json"), JSON.stringify(fixture));
  writeFileSync(provider, `import { appendFileSync } from "node:fs";
import { createAssistantMessageEventStream, getCurrentTools } from "@earendil-works/pi-ai";
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
      const [id, name, args] = ["child_fresh_sentinel", "child_bg_sentinel", "child_specialist_sentinel"].includes(key)
        ? [key, "bash", { command: key === "child_fresh_sentinel" ? "sleep 3; printf '%s%s' pi_shell _ok" : "printf '%s%s' pi_shell _ok" }] : {
        parallel_probe: ["parallel-probe", "subagent", { tasks: [
          { agent: "scout", task: "child_batch_one_sentinel" },
          { agent: "reviewer", task: "child_batch_two_sentinel" },
        ], async: false }],
        child_batch_one_sentinel: ["foreground-shell", "bash", { command: "sleep 3; printf '%s%s' foreground_ stdout" }],
        background_card_probe: ["background-card", "subagent", { async: true, tasks: [
          { agent: "scout", task: "child_card_first_sentinel" },
          { agent: "reviewer", task: "child_card_second_sentinel" },
        ] }],
        child_card_first_sentinel: ["card-shell", "bash", { command: "sleep 12; printf '%s%s' private_ stdout" }],
        foreman_first: ["foreman-first", "foreman_worker", { action: "start", message: "child_foreman_first_sentinel" }],
        foreman_duplicate: ["foreman-duplicate", "foreman_worker", { action: "start", message: "child_foreman_duplicate_sentinel" }],
        foreman_resume: ["foreman-resume", "foreman_worker", { action: "resume", message: "child_foreman_resume_sentinel" }],
        foreman_direct_write: ["foreman-direct", "write", { path: "not-allowed", content: "blocked" }],
        execute_after_foreman: ["execute-after-foreman", "write", { path: "execute-restored", content: "restored" }],
        foreman_check_diff: ["foreman-check", "foreman_diff", {}],
        child_foreman_first_sentinel: ["child-write", "edit", { path: "work.txt", edits: [{ oldText: "initial", newText: "first" }] }],
        child_foreman_resume_sentinel: ["child-follow-up", "edit", { path: "work.txt", edits: [{ oldText: "first", newText: "resumed" }] }],
      }[key] ?? [];
      const call = id && !context.messages.some(m => m.role === "toolResult" && m.toolCallId === id)
        ? { type: "toolCall", id, name, arguments: args } : undefined;
      const input = key === "child_card_first_sentinel" ? 30 : key === "child_card_second_sentinel" ? 20 : 10;
      const response = {
        role: "assistant", content: [call ?? { type: "text", text }], api: model.api, provider: model.provider, model: model.id,
        usage: { input, output: 10, cacheRead: 0, cacheWrite: 0, totalTokens: input + 10, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
        timestamp: Date.now(), stopReason: call ? "toolUse" : "stop",
      };
      const trace = data => appendFileSync(process.env.PROBE_LOG, JSON.stringify({ key, model: model.id, time: Date.now(), ...data }) + "\\n");
      trace({ phase: "start", reasoning: options?.reasoning, inherited: messages.includes("parent_history_sentinel"),
        workerContext: messages.some(text => text?.includes("child_foreman_first_sentinel")),
        tools: getCurrentTools(context.messages).map(t => t.name),
        result: id && context.messages.find(m => m.role === "toolResult" && m.toolCallId === id)?.content });
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
      }, key === "child_batch_two_sentinel" ? 1800 : key === "child_card_second_sentinel" ? 7000 : key === "child_foreman_first_sentinel" && call ? 6500 : 0);
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
    `PROBE_LOG=${log}`, `PI_SUBAGENTS_TEMP_ROOT=${join(directory, "subagent-runs")}`, "TERM=xterm-256color", "COLORTERM=truecolor", "PI_TELEMETRY=0", process.env.PI_TEST_BIN ?? "pi",
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
  await waitFor(() => /\bAGENTS\b/.test(frame()), "Agents status");
  send("BTab");
  await waitFor(() => frame().includes("EXPLORE"), "Explore mode");
  prompt("/run scout child_explore_sentinel");
  await waitFor(() => frame().includes("Switch to Execute before launching a subagent"), "Explore launch guard");
  send("BTab");
  await waitFor(() => /\bAGENTS\b/.test(frame()) && !frame().includes("EXPLORE"), "return to Execute");
  prompt("/run scout child_fresh_sentinel");
  await waitFor(() => /^ subagents · scout *$/m.test(frame()) && /^ {5}└ shell · sleep 3\s*;/m.test(frame()), "aligned inline slash shell preview");
  await waitFor(() => requests().some(r => r.key === "child_fresh_sentinel" && r.result) && /^ subagents · scout 40 tok +\d+ s *$/m.test(frame()), "fresh run with default virtual model");
  prompt("/run code-reviewer[model=probe/main] child_specialist_sentinel");
  await waitFor(() => requests().some(r => r.key === "child_specialist_sentinel" && r.result) && /^ subagents · code-reviewer 40 tok +\d+ s *$/m.test(frame()), "specialist with no tool allowlist");
  prompt("/run reviewer[model=probe/main:xhigh] child_fork_sentinel --fork");
  await waitFor(() => requests().some(r => r.key === "child_fork_sentinel" && r.phase === "end") && /^ subagents · reviewer 20 tok +\d+ s *$/m.test(frame()), "fork run with a per-run override");
  prompt("/run scout[model=probe/outside] child_outside_sentinel");
  await waitFor(() => frame().includes("outside the configured subagent model scope"), "model-scope rejection");
  prompt("parallel_probe");
  await waitFor(() => /^ subagents · scout, reviewer *$/m.test(frame()) && /└ shell · .*foreground_ stdout/.test(frame()), "parallel live card and command preview");
  await waitFor(() => /^ {5}reviewer\b/m.test(frame()) && /^ {3}● scout\b/m.test(frame())
    && /└ shell · .*foreground_ stdout/.test(frame()), "only the running child has a dot");
  await waitFor(() => frame().includes("DONE parallel_probe") && /^ subagents · scout 40 tok, reviewer 20 tok +\d+ s *$/m.test(frame()), "parallel result with final token counts");
  prompt("background_card_probe");
  const liveCard = () => /^ {5}└ shell · sleep 12\s*;.*$/m.test(frame());
  await waitFor(liveCard, "background shell preview after the parent returned");
  assert.match(frame(), /DONE background_card_probe/);
  assert.match(frame(), /scout .*medium.*fresh.*tok/);
  send("C-o");
  assert.ok(liveCard());
  assert.doesNotMatch(frame(), /Run fan-out:|for full output/);
  const footerAgents = count => new RegExp(`^ {3}main · xhigh · [\\d.]+% · ${count} agents? ↓`, "mi").test(frame());
  await waitFor(() => footerAgents(2), "two agents in the footer's left group");
  assert.match(frame(), /^ {3}AGENTS\b/m);
  assert.doesNotMatch(frame(), /↓\/← to inspect/);
  send("Down");
  const roster = () => frame().includes("↑↓/jk select · enter inspect · esc back");
  await waitFor(() => roster() && !footerAgents(2), "Down opens the native roster");
  send("Escape");
  await waitFor(() => !roster() && footerAgents(2), "Escape restores the merged footer");
  const checkLiveDot = async count => {
    const colors = new Set();
    const until = Date.now() + 1600;
    let row;
    do {
      if (!footerAgents(count)) break;
      row = tmux("capture-pane", "-e", "-p", "-t", pane).split("\n").find(line => line.includes("●") && line.includes("scout"));
      const paint = row?.match(/\x1b\[38;2;(\d+;\d+;\d+)m●/u);
      if (paint) colors.add(paint[1]);
      await delay(60);
    } while (Date.now() < until);
    assert.ok(colors.size >= 8, `RGB pulse with ${count} active agents in the footer: ${[...colors].join(", ")} (last row: ${JSON.stringify(row)})`);
  };
  await checkLiveDot(2);
  await waitFor(() => liveCard() && footerAgents(1), "footer updates as the first child finishes");
  await checkLiveDot(1);
  await waitFor(() => requests().some(r => r.key === "child_card_first_sentinel" && r.result?.some(x => x.text === "private_stdout")), "background shell completed");
  const settledCard = () => !liveCard() && /^ subagents · scout 80 tok, reviewer 30 tok +\d+ s *$/m.test(frame());
  await waitFor(settledCard, "background compact history");
  await waitFor(() => !/agents? ↓/.test(frame()), "footer label clears after the last child finishes");
  assert.doesNotMatch(frame(), /private_stdout|Run fan-out:/);
  const sessions = join(agent, "sessions");
  await waitFor(() => globSync("**/*.jsonl", { cwd: sessions }).some(file =>
    readFileSync(join(sessions, file), "utf8").split("\n").some(line => {
      if (!line.includes('"customType":"subagent-notify"')) return false;
      return JSON.parse(line).details?.runs?.some(run => run.childOutputs?.some(child => child.agent === "scout"));
    })), "background completion receipt persisted");
  await waitFor(() => /^ {3}AGENTS +· Ready *$/m.test(frame()) &&
    requests().some(r => r.key === "child_card_second_sentinel" && r.model === "main" && r.phase === "end"), "parent idle after the completion notice");
  prompt("/reload");
  await waitFor(() => /reloaded/i.test(frame()) && settledCard(), "compact history survives reload");
  if (!/^ {3}AGENTS\b/m.test(frame())) {
    send("M-g");
    await waitFor(() => /^ {3}AGENTS\b/m.test(frame()), "restore Agents after reload");
  }
  prompt("/run scout child_bg_sentinel --bg");
  await waitFor(() => requests().some(r => r.key === "child_bg_sentinel" && r.model === "other" && r.result?.some(item => item.text.trim() === "pi_shell_ok")), "background child Bash result");
  const results = requests();
  for (const key of ["child_fresh_sentinel", "child_bg_sentinel", "child_specialist_sentinel"]) {
    const child = results.filter(r => r.key === key && r.phase === "start");
    assert.ok(child.some(r => r.result?.some(item => item.text.trim() === "pi_shell_ok")), `${key} did not run bash`);
    assert.ok(child[0].tools.includes("bash"));
    for (const tool of ["edit", "write"]) assert.ok(!child[0].tools.includes(tool), `${key} has ${tool}`);
  }
  const batch = results.filter(r => r.key?.startsWith("child_batch_") && r.model === "other");
  assert.equal(new Set(batch.map(r => r.key)).size, 2);
  assert.ok(batch.filter(r => r.phase === "start").every(r => r.tools.includes("bash")));
  const seen = (key, phase) => batch.filter(r => r.key === key && r.phase === phase);
  assert.ok(Math.max(...["child_batch_one_sentinel", "child_batch_two_sentinel"].map(key => seen(key, "start")[0].time)) <
    Math.min(...["child_batch_one_sentinel", "child_batch_two_sentinel"].map(key => seen(key, "end").at(-1).time)), "the children actually overlapped");
  assert.ok(results.some(r => r.key === "child_fresh_sentinel" && r.model === "other" && r.reasoning === "medium" && !r.inherited));
  assert.ok(results.some(r => r.key === "child_fork_sentinel" && r.model === "main" && r.reasoning === "xhigh" && r.inherited));
  assert.ok(!results.some(r => r.model === "outside" || r.key === "child_denied_sentinel" || r.key === "child_explore_sentinel"));
  prompt("/foreman");
  await waitFor(() => /\bFOREMAN\b/.test(frame()), "Foreman mode");
  prompt("foreman_direct_write");
  await waitFor(() => frame().includes("DONE foreman_direct_write"), "parent write rejection");
  assert.ok(!existsSync(join(directory, "not-allowed")), "the parent cannot write in Foreman");
  const parent = requests().find(r => r.key === "foreman_direct_write" && r.phase === "start");
  assert.ok(parent.tools.includes("foreman_worker"));
  for (const tool of ["bash", "edit", "write", "codemode", "subagent"]) assert.ok(!parent.tools.includes(tool), tool);

  prompt("foreman_first");
  await waitFor(() => requests().some(r => r.key === "child_foreman_first_sentinel" && r.phase === "start"), "Foreman worker start");
  await waitFor(() => frame().includes("DONE foreman_first"), "parent returns control while worker runs");
  prompt("/foreman");
  await waitFor(() => frame().includes("Wait for the Foreman worker to stop"), "cannot exit while worker writes");
  prompt("foreman_duplicate");
  await waitFor(() => requests().some(r => r.key === "foreman_duplicate" && JSON.stringify(r.result)?.includes("already exists")), "duplicate worker rejection");
  prompt("/reload");
  await waitFor(() => /\bFOREMAN\b/.test(frame()) && /reloaded/i.test(frame()), "Foreman restored on reload");
  assert.equal(readFileSync(workFile, "utf8"), "initial\n", "the worker was still running during reload");
  await waitFor(() => readFileSync(workFile, "utf8") === "first\n", "worker edits the current working copy");
  await waitFor(() => frame().includes("DONE child_foreman_first_sentinel"), "worker completion surfaces after reload");
  prompt("foreman_resume");
  await waitFor(() => readFileSync(workFile, "utf8") === "resumed\n", "continued worker edits the same file");
  assert.ok(requests().some(r => r.key === "child_foreman_resume_sentinel" && r.model === "other" && r.workerContext), "resume preserves worker context");
  assert.ok(!requests().some(r => r.key === "child_foreman_duplicate_sentinel"), "a fresh second worker did not run");
  await waitFor(() => frame().includes("DONE child_foreman_resume_sentinel"), "resumed completion surfaces in parent");
  prompt("foreman_check_diff");
  await waitFor(() => requests().some(r => r.key === "foreman_check_diff" && JSON.stringify(r.result)?.includes("+resumed")), "Foreman sees the real diff");
  await waitFor(() => frame().includes("DONE foreman_check_diff"), "Foreman diff turn completes");
  prompt("/foreman");
  await waitFor(() => !/\bFOREMAN\b/.test(frame().split("\n").slice(-5).join("\n")), "exit Foreman after worker completion");
  prompt("execute_after_foreman");
  await waitFor(() => existsSync(join(directory, "execute-restored")), "Execute write tools are restored");
  console.log("PASS: linked roles, /agents, Option+G, Execute bash, Explore, model scope, live slash/parallel/background cards, FleetView footer and navigation, reload, and a single resumed Foreman writer");
} finally {
  try { tmux("kill-server"); } catch {}
  rmSync(directory, { recursive: true, force: true, maxRetries: 5 });
}
