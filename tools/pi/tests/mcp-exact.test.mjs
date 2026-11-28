import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const dir = mkdtempSync(join(tmpdir(), "pi-mcp-exact-"));
process.env.HOME = process.env.PI_CODING_AGENT_DIR = dir;
const load = (pkg, path) => import(pathToFileURL(join(process.env.PI_TEST_MODULES, "@earendil-works", pkg, "dist", path + ".js")));
const { createMcpExtension } = await load("pi-coding-agent", "extensions/mcp/index");
const { createToolSearchToolDefinition } = await load("pi-coding-agent", "extensions/tool-search/tool");
const { createCodemodeToolDefinition } = await load("pi-coding-agent", "extensions/codemode/tool");
const { createMcpToolName: key, LATEST_PROTOCOL_VERSION: protocolVersion } = await load("pi-mcp", "index");
const { createInMemoryTransportPair } = await load("pi-mcp", "testing/index");
const longTool = "read_" + "x".repeat(70);
const longServer = "n".repeat(61);
const offer = { [longServer]: ["read"], "fast-docs": ["read", longTool, "a-b", "a_b", "v2__read", "secret"], fast_docs__v2: ["read"], slow: ["read"], off: [] };
const gates = new Map(Object.keys(offer).map(name => [name, Promise.withResolvers()]));
const atList = new Map(Object.keys(offer).map(name => [name, Promise.withResolvers()]));
const hooks = new Map(), defs = new Map();
let active = [];
const api = { on: (name, h) => hooks.set(name, h), registerCommand() {}, registerToolRenderer() {},
  getMcpServers: () => [], registerTool: t => defs.set(t.name, t), getAllTools: () => [...defs.values()],
  getActiveTools: () => active, setActiveTools: tools => { active = tools; } };
const ctx = { cwd: dir, ui: { notify() {} } };
const search = createToolSearchToolDefinition({ tools: api });
api.registerTool(search); api.registerTool(createCodemodeToolDefinition());
createMcpExtension({
  logPath: join(dir, "mcp.log"),
  credentials: new Proxy({}, { get: () => assert.fail("unexpected credential read") }),
  loadConfig: () => ({ errors: [], servers: Object.keys(offer).map(name => ({
    name, source: "fixture", config: { command: "never-executed", exposure: "deferred",
      enabled: name !== "off", toolExposure: { secret: "hidden" } },
  })) }),
  createTransport: ({ name }) => {
    assert.notEqual(name, "off");
    const { client, server } = createInMemoryTransportPair();
    server.onMessage(async q => {
      if (!("id" in q) || !("method" in q)) return;
      let result;
      if (q.method === "initialize") result = { protocolVersion, capabilities: { tools: {} }, serverInfo: { name, version: "1" } };
      else if (q.method === "tools/list") {
        atList.get(name).resolve(); await gates.get(name).promise;
        result = { tools: offer[name].map(name => ({ name, inputSchema: { type: "object", properties: {} } })) };
      } else assert.fail(q.method);
      await server.send({ jsonrpc: "2.0", id: q.id, result });
    });
    void server.start(); return client;
  },
})(api);
const tick = () => new Promise(setImmediate);
const wait = (toolName, input) => {
  const state = { done: false };
  state.promise = hooks.get("tool_call")({ toolName, input }, ctx).then(() => { state.done = true; });
  return state;
};
const run = async query => (await search.execute("id", { query })).details.loaded;
const watchdog = setTimeout(() => { throw Error("MCP readiness did not settle"); }, 8000);
try {
  await hooks.get("session_start")({}, ctx);
  await Promise.all(["fast-docs", "fast_docs__v2", "slow", longServer].map(name => atList.get(name).promise));
  const target = key("fast-docs", "read"), nested = key("fast_docs__v2", "read");
  const exact = wait("tool_search", { query: target }), fuzzy = wait("tool_search", { query: "read" });
  const long = wait("tool_search", {query:key("fast-docs",longTool)});
  const truncated = wait("tool_search", {query:key(longServer,"read")});
  assert.equal(key(longServer,"read").length,64);
  const overlap = wait("tool_search", { query: nested }), list = wait("codemode", { code: "return ALL_TOOLS" });
  await tick(); assert.equal(exact.done, false);
  gates.get("fast-docs").resolve(); await tick();
  assert.equal(exact.done, true);
  assert.equal(long.done,true,"slow unrelated server cannot block even a hashed tool");
  assert.deepEqual(await run(key("fast-docs",longTool)),[key("fast-docs",longTool)]);
  assert.equal(truncated.done,false);
  gates.get(longServer).resolve(); await truncated.promise;
  assert.deepEqual(await run(key(longServer,"read")),[key(longServer,"read")]);
  assert.deepEqual(await run(target), [target]);
  assert.deepEqual(await run(target), [], "already active");
  assert.equal(overlap.done, false);
  assert.equal(list.done, false); assert.equal(fuzzy.done, false);
  for (const tool of ["missing", "secret", "a_b"]) assert.deepEqual(await run(key("fast-docs", tool)), []);
  for (const tool of ["a-b", "a_b"]) {
    const assigned = key("fast-docs", tool, () => true);
    assert.deepEqual(await run(assigned), [assigned]);
  }
  gates.get("fast_docs__v2").resolve(); await overlap.promise;
  assert.equal(list.done, false);
  gates.get("slow").resolve(); await Promise.all([list.promise, fuzzy.promise]);
  active = [];
  assert.ok((await run("read")).includes(key("slow", "read")));
  console.log("PASS: exact MCP discovery waits only for possible owners; full/fuzzy discovery waits for all");
} finally {
  for (const gate of gates.values()) gate.resolve();
  await hooks.get("session_shutdown")({}, ctx); clearTimeout(watchdog); rmSync(dir, { recursive: true, force: true });
}
