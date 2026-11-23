import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const agentDir = join(homedir(), ".pi", "agent");
const modules = process.env.PI_TEST_MODULES ?? join(agentDir, "install", "releases",
  readFileSync(join(agentDir, "install", "current-version"), "utf8").trim(), "node_modules");
const load = path => import(pathToFileURL(join(modules, path)).href);
const { loadMcpConfig } = await load("@earendil-works/pi-coding-agent/dist/extensions/mcp/config.js");
const { createDefaultTransport } = await load("@earendil-works/pi-coding-agent/dist/extensions/mcp/runtime.js");
const { resolveHeadersOrThrow } = await load("@earendil-works/pi-coding-agent/dist/core/resolve-config-value.js");
const { McpClient } = await load("@earendil-works/pi-mcp/dist/client.js");
const template = readFileSync(new URL("../mcp.json", import.meta.url), "utf8");
const config = JSON.parse(template).mcpServers.knowledge;
const sandbox = mkdtempSync(join(tmpdir(), "pi-knowledge-"));
const previousTokenFile = process.env.KNOWLEDGE_TOKEN_FILE;
try {
  const testAgentDir = join(sandbox, "agent");
  const cwd = join(sandbox, "project");
  mkdirSync(testAgentDir);
  mkdirSync(cwd);
  writeFileSync(join(testAgentDir, "mcp.json"), template);
  const loaded = loadMcpConfig({ agentDir: testAgentDir, cwd, projectTrusted: false });
  assert.deepEqual(loaded.errors, []);
  const servers = new Map(loaded.servers.map(({ name, config }) => [name, config]));
  assert.deepEqual([...servers.keys()].sort(), ["exa", "knowledge"]);
  assert.equal(servers.get("knowledge").exposure, "deferred");
  assert.equal(servers.get("knowledge").url, "http://100.64.0.1:7234/mcp");
  assert.equal(servers.get("exa").exposure, "direct");

  const tokenFile = join(sandbox, "token with spaces");
  process.env.KNOWLEDGE_TOKEN_FILE = tokenFile;
  writeFileSync(tokenFile, "fixture-token\n", { mode: 0o600 });
  assert.equal(resolveHeadersOrThrow(config.headers, "test").Authorization, "Bearer fixture-token");
  writeFileSync(tokenFile, "rotated-fixture-token\n");
  assert.equal(resolveHeadersOrThrow(config.headers, "test").Authorization, "Bearer rotated-fixture-token");
  writeFileSync(tokenFile, " \n\t");
  assert.throws(() => resolveHeadersOrThrow(config.headers, "test"), /Failed to resolve/);
  rmSync(tokenFile);
  assert.throws(() => resolveHeadersOrThrow(config.headers, "test"), /Failed to resolve/);
  console.log("PASS: native MCP config loader; deferred exposure; external token; rotation on resolution; missing/empty token fails closed");
} finally {
  if (previousTokenFile === undefined) delete process.env.KNOWLEDGE_TOKEN_FILE;
  else process.env.KNOWLEDGE_TOKEN_FILE = previousTokenFile;
  rmSync(sandbox, { recursive: true, force: true });
}

if (process.argv.includes("--live")) {
  const loaded = loadMcpConfig({ agentDir, cwd: process.cwd(), projectTrusted: false });
  assert.deepEqual(loaded.errors, []);
  const entry = loaded.servers.find(server => server.name === "knowledge");
  assert.ok(entry, "knowledge must be configured globally");
  assert.deepEqual(entry.config, config, "live knowledge configuration must match the template");
  const client = new McpClient({ name: "pi-knowledge-verification", version: "1.0.0", requestTimeoutMs: 10000 });
  try {
    await client.connect(createDefaultTransport(entry, process.cwd()));
    const tools = await client.listTools();
    for (const name of ["search", "read", "propose_note", "propose_edit"]) {
      assert.ok(tools.some(tool => tool.name === name), `missing tool: ${name}`);
    }
    const result = await client.callTool("search", { text: "Pi", limit: 1 });
    assert.notEqual(result.isError, true, "read-only search must succeed");
    assert.ok(result.content?.length, "search must return content");
    console.log(`PASS: live native Pi transport; ${tools.length} tools discovered; read-only search succeeded; no vault writes`);
  } finally {
    await client.close();
  }
}
