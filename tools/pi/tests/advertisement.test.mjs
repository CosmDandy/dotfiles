import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const dir = mkdtempSync(join(tmpdir(), "pi-catalog-"));
const pkg = join(process.env.PI_TEST_SUBAGENTS, "pi-subagents", "bundle/index.js");
const agent = join(dir, "agent");
try {
  mkdirSync(join(agent, "agents"), { recursive: true });
  writeFileSync(join(agent, "agents", "catalog-fixture.md"), "---\nname: catalog-fixture\ndescription: Fixture\nadvertise: true\n---\nFixture");
  // Gate a local fake npm on the disabled turn's completion, not on a latency threshold.
  writeFileSync(join(dir, "npm"), `#!/bin/sh
touch "$HOME/started"
while [ ! -f "$HOME/release" ]; do sleep .02; done
touch "$HOME/finished"
printf '%s\\n' "$HOME"
`, { mode: 0o755 });
  const extension = join(dir, "probe.ts");
  writeFileSync(extension, `import { existsSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { createAssistantMessageEventStream } from "@earendil-works/pi-ai";
import register from ${JSON.stringify(pathToFileURL(pkg).href)};
export default function(pi) {
  const path = name => join(process.env.HOME, name);
  pi.registerProvider("fixture", { baseUrl: "http://127.0.0.1:1", apiKey: "fake", api: "fixture",
    models: [{ id: "local", name: "Local", reasoning: false, input: ["text"], contextWindow: 100000,
      maxTokens: 1000, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }],
    streamSimple() {
      const s = createAssistantMessageEventStream();
      s.push({type:"done",reason:"stop",message:{role:"assistant",content:[],api:"fixture",provider:"fixture",model:"local",timestamp:Date.now(),stopReason:"stop",usage:{input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}}}}); s.end(); return s;
    } });
  // Core is already offline; exercise the package's local npm lookup without a real registry.
  pi.on("session_start", () => { delete process.env.PI_OFFLINE; });
  pi.on("before_agent_start", async e => {
    e.systemPromptOptions.selectedTools = process.env.ENABLED === "yes" ? ["subagent"] : [];
    while (!existsSync(path("started"))) await delay(5);
    if (process.env.ENABLED === "yes") setTimeout(() => writeFileSync(path("release"), ""), 80);
  });
  if (process.env.INVALID_SETTINGS) {
    register(new Proxy(pi, { get(target, key) {
      if (key !== "on") return target[key];
      return (name, handler) => pi.on(name, name !== "before_agent_start" ? handler : async (event, ctx) => {
        try { return await handler(event, ctx); }
        catch (error) {
          if (!String(error).includes("disableBuiltins")) throw error;
          try { await handler(event, ctx); }
          catch (again) { writeFileSync(path("repeated"), String(again)); }
        }
      });
    }}));
  } else register(pi);
  pi.on("session_start", () => { process.env.PI_OFFLINE = "1"; });
  pi.on("before_agent_start", async e => {
    const result = { finished: existsSync(path("finished")), sections: e.systemPromptOptions.sections };
    writeFileSync(path("release"), "");
    const deadline = Date.now() + 2000;
    while (!existsSync(path("finished")) && Date.now() < deadline) await delay(10);
    result.lookupSurvived = existsSync(path("finished"));
    writeFileSync(path("result"), JSON.stringify(result));
  });
}
`);
  for (const state of ["off", "on", "invalid"]) {
    const enabled = state === "off" ? "no" : "yes";
    if (state === "invalid") writeFileSync(join(agent, "settings.json"), '{"subagents":{"disableBuiltins":"invalid"}}');
    for (const file of ["started", "finished", "release", "result"]) rmSync(join(dir, file), { force: true });
    const child = spawnSync(process.env.PI_TEST_BIN ?? "pi", ["--offline", "--no-mcp", "--no-session", "--no-extensions",
      "-e", extension, "--model", "fixture/local", "-p", "test"], { cwd: dir, timeout: 12000, encoding: "utf8",
      env: { HOME: dir, PATH: dir + ":" + process.env.PATH, PI_CODING_AGENT_DIR: agent, PI_TELEMETRY: "0",
        PI_SUBAGENTS_TEMP_ROOT: join(dir, "runs"), ENABLED: enabled, INVALID_SETTINGS: state === "invalid" ? "1" : "" } });
    assert.equal(child.status, 0, child.error?.message ?? child.stderr);
    const result = JSON.parse(readFileSync(join(dir, "result"), "utf8"));
    assert.equal(result.lookupSurvived, true, "the optional lookup timed out before the turn could release it");
    assert.equal(result.finished, enabled === "yes");
    if (state === "invalid") assert.match(readFileSync(join(dir, "repeated"), "utf8"), /invalid 'disableBuiltins'/);
    else if (enabled === "yes") assert.match(JSON.stringify(result.sections.advertised_subagents), /catalog-fixture/);
    else assert.equal(result.sections.advertised_subagents, undefined);
  }
  console.log("PASS: first turn skips pending discovery only when subagent is unselected; enabled turn gets its catalog");
} finally { rmSync(dir, { recursive: true, force: true }); }
