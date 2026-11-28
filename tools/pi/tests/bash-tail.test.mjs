import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { mock } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

const agent = join(homedir(), ".pi", "agent");
const modules = process.env.PI_TEST_MODULES ?? join(agent, "install/releases",
  readFileSync(join(agent, "install/current-version"), "utf8").trim(), "node_modules");
const load = path => import(pathToFileURL(join(modules, "@earendil-works", path)));
const { loadExtensions } = await load("pi-coding-agent/dist/core/extensions/loader.js");
const { createEventBus } = await load("pi-coding-agent/dist/core/event-bus.js");
const { ToolExecutionComponent } = await load("pi-coding-agent/dist/modes/interactive/components/tool-execution.js");
const themes = await load("pi-coding-agent/dist/modes/interactive/theme/theme.js");
const { wrapTextWithAnsi } = await load("pi-tui/dist/index.js");
themes.initTheme("dark", false);
const ext = process.argv[2] ?? fileURLToPath(new URL("../extensions/compact-tools.ts", import.meta.url));
const loaded = await loadExtensions([ext], "/tmp", createEventBus());
assert.deepEqual(loaded.errors, []);
const extension = loaded.extensions[0];
const ctx = { mode: "tui", cwd: "/tmp", ui: { requestRender() {} }, sessionManager: {
  getEntries: () => [], getBranch: () => [], getSessionId: () => "test", getSessionFile: () => undefined,
} };
let now = 0;
const timers = new Set();
mock.method(Date, "now", () => now);
mock.method(globalThis, "setInterval", callback => { timers.add(callback); return { unref() {} }; });
const emit = async type => {
  for (const handler of extension.handlers.get(type) ?? []) await handler({ type }, ctx);
};
const plain = line => line.replace(/\x1b\[[0-9:;]*m/g, "").trim();
await emit("session_start");
await emit("agent_start");
for (const [label, unit] of [["ASCII", "a".repeat(19)], ["Cyrillic", "я".repeat(9) + "x"], ["CJK", "界".repeat(6) + "a"]]) {
  const c = new ToolExecutionComponent("bash", label, { command: "printf example" }, { outputPad: 1, showImages: false },
    extension.toolRenderers[0]("bash", () => undefined), { requestRender() {} }, "/tmp");
  const result = { content: [{ type: "text", text: Array.from({ length: 1600 }, (_, i) => unit + String(i).padStart(4, "0") + "\n").join("") + "tail" }] };
  c.markExecutionStarted();
  c.updateResult(result, true);
  const tick = () => { now += 100; for (const callback of timers) callback(); };
  now += 601;
  tick();
  function tail(width) { return c.render(width).map(plain).filter(Boolean).slice(1); }
  function expected(width) {
    const rows = wrapTextWithAnsi(result.content[0].text, width - 2);
    return rows.length > 5 ? [`… ${rows.length - 4} earlier lines`, ...rows.slice(-4)] : rows;
  }
  const check = width => assert.deepEqual(tail(width), expected(width));
  check(80);
  const saved = c.rendererState.bashTail;
  const samples = [];
  for (let i = 0; i < 35; i++) {
    const start = performance.now();
    tick(); c.render(80);
    if (i >= 5) samples.push(performance.now() - start);
  }
  check(80);
  if (!process.argv[2]) {
    assert.ok(saved?.rows.length);
    assert.strictEqual(c.rendererState.bashTail.rows, saved.rows, "spinner ticks reuse the wrap result");
  }
  console.log(`${label}: ${Buffer.byteLength(result.content[0].text)} bytes, median tick + render ${samples.sort((a,b) => a-b)[15].toFixed(3)} ms (n=30)`);
  check(22);
  result.content[0].text += "\nещё";
  c.updateResult(result, true);
  check(80);
  result.content[0].text = "замена\n短い";
  c.updateResult(result, true);
  check(80);
  result.content[0].text = "строка\n漢字";
  c.updateResult(result, true);
  check(80);
  c.setExpanded(true);
  assert.ok(c.render(80).map(plain).includes("строка"));
  c.setExpanded(false);
  check(80);
  c.updateResult({ content: [{ type: "text", text: "aborted" }], isError: true }, false);
  assert.doesNotMatch(c.render(80).join(""), /строка|漢字/);
}
await emit("agent_end");
mock.restoreAll();
