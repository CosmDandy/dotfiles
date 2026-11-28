import assert from "node:assert/strict";
import fs from "node:fs";
import fsp from "node:fs/promises";
import { syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { mock } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = fs.realpathSync(fs.mkdtempSync(join(tmpdir(), "pi-hidden-cards-")));
const parent = join(root, "session.jsonl");
const id = i => `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`;
const write = (file, data) => {
  fs.mkdirSync(dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data));
};
const save = (i, state, steps) => write(join(root, "async-subagent-runs", id(i), "status.json"),
  { sessionId: "owner", runId: id(i), state, steps });
process.env.PI_SUBAGENTS_TEMP_ROOT = root;
const paths = [];
const open = fsp.open.bind(fsp);
let onOpen;
mock.method(fsp, "open", async (path, ...args) => {
  if (path.startsWith(root + "/")) { paths.push(path); onOpen?.(); }
  return open(path, ...args);
});
syncBuiltinESMExports();
try {
  const dist = join(process.env.PI_TEST_MODULES, "@earendil-works/pi-coding-agent/dist");
  const load = name => import(pathToFileURL(join(dist, name + ".js")));
  const { loadExtensions } = await load("core/extensions/loader");
  const { createEventBus } = await load("core/event-bus");
  const theme = await load("modes/interactive/theme/theme");
  theme.initTheme("dark", false);
  const events = createEventBus();
  const loaded = await loadExtensions([fileURLToPath(new URL("../extensions/compact-tools.ts", import.meta.url))], root, events);
  assert.deepEqual(loaded.errors, []);
  const ext = loaded.extensions[0], renderer = ext.toolRenderers[0]("subagent", () => undefined);
  const ctx = { mode: "tui", ui: { requestRender() {} }, sessionManager: {
    getSessionId: () => "owner", getSessionFile: () => parent, getBranch: () => [], getEntries: () => [],
  } };
  const lifecycle = async name => { for (const h of ext.handlers.get(name) ?? []) await h({}, ctx); };
  const timers = new Map();
  mock.method(globalThis, "setTimeout", cb => {
    const handle = { unref() {} }; timers.set(handle, cb); return handle;
  });
  mock.method(globalThis, "clearTimeout", key => timers.delete(key));
  const drain = async () => {
    const pending = [...timers.values()]; timers.clear();
    for (const cb of pending) await cb();
  };
  const visible = yes => events.emit("dotfiles:pane-hidden", !yes);
  const burst = () => { for (let i = 0; i < 8; i++) events.emit("subagent:jobs-changed", {}); };
  const rows = Array.from({ length: 4 }, (_, i) => ({ index: i, agent: "child" + i, runId: id(i + 1), status: "running" }));
  const update = tokens => {
    save(0, "running", rows);
    for (const row of rows) save(row.index + 1, "running", [{ ...row, tokens }]);
  };
  await lifecycle("session_start");
  update(100);
  const tc = { args: { tasks: rows }, state: {}, outputPad: 1, executionStarted: true };
  const card = renderer.renderCall(tc.args, theme.theme, tc);
  renderer.renderResult({ details: { asyncId: id(0) }, content: [] }, { isPartial: false }, theme.theme, tc);
  await drain();
  assert.equal(paths.length, 5);
  paths.length = 0; burst(); visible(false); await drain();
  for (let i = 0; i < 3; i++) { burst(); await drain(); }
  assert.deepEqual(paths, [], "a burst, including an already scheduled refresh, does not open hidden files");
  update(700); visible(true); await drain();
  assert.match(card.render(160).join("\n"), /700 tok/);
  assert.equal(paths.length, 5, "one parent and exactly four child snapshots on reveal");
  paths.length = 0; burst();
  onOpen = () => { onOpen = undefined; visible(false); };
  await drain();
  assert.equal(paths.length, 1, "hide during a parent read must not start reading its children");
  paths.length = 0;
  save(0, "failed", rows.map(row => ({ ...row, status: "failed", tokens: 999 })));
  events.emit("subagent:async-complete", { runId: id(0), status: "failed", error: "\x9b1;48:5:123;4:3mhidden failure\x1b[0m at 12:34; [4:3m" });
  const reason = card.render(160).join("\n");
  assert.match(reason, /hidden failure at 12:34; \[4:3m/);
  assert.doesNotMatch(reason, /:5:123|;4:3mhidden/);
  assert.deepEqual(paths, [], "delivery settles the hidden card without disk access");
  visible(true);
  for (let i = 0; i < 200 && !card.render(160).join("").includes("999 tok"); ++i) await new Promise(setImmediate);
  assert.match(card.render(160).join(""), /999 tok/);
  assert.equal(paths.length, 1, "only terminal usage is read on reveal");
  visible(false); paths.length = 0;
  const cold = { ...tc, state: {} }, coldId = id(9);
  const neverPainted = renderer.renderCall(cold.args, theme.theme, cold);
  renderer.renderResult({ details: { asyncId: coldId }, content: [] }, { isPartial: false }, theme.theme, cold);
  save(9, "failed", rows.map(row => ({ ...row, status: "failed", tokens: 999 })));
  events.emit("subagent:async-complete", { runId: coldId, status: "failed", error: "receipt reason" });
  await drain(); assert.deepEqual(paths, []);
  visible(true);
  for (let i = 0; i < 200 && !neverPainted.render(160).join("").includes("999 tok"); ++i) await new Promise(setImmediate);
  const recovered = neverPainted.render(160).join("");
  assert.equal(recovered.match(/999 tok/g)?.length, 4);
  assert.match(recovered, /receipt reason/); assert.equal(paths.length, 1);
  await lifecycle("session_shutdown");
  console.log("PASS: hidden I/O, hide during read, reveal without a producer and terminal receipt");
} finally {
  mock.restoreAll(); syncBuiltinESMExports(); fs.rmSync(root, { recursive: true, force: true });
}
