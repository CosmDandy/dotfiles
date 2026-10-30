import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { mock } from "node:test";

const agentDir = join(homedir(), ".pi", "agent");
const modules = process.env.PI_TEST_MODULES ?? join(agentDir, "install", "releases",
  readFileSync(join(agentDir, "install", "current-version"), "utf8").trim(), "node_modules");
const load = path => import(pathToFileURL(join(modules, path)).href);
const { loadExtensions } = await load("@earendil-works/pi-coding-agent/dist/core/extensions/loader.js");
const { ToolExecutionComponent } = await load("@earendil-works/pi-coding-agent/dist/modes/interactive/components/tool-execution.js");
const themes = await load("@earendil-works/pi-coding-agent/dist/modes/interactive/theme/theme.js");
const { visibleWidth } = await load("@earendil-works/pi-tui/dist/index.js");
themes.initTheme("dark", false);
const extensionPath = fileURLToPath(new URL("../extensions/compact-tools.ts", import.meta.url));
const loaded = await loadExtensions([extensionPath], "/tmp");
assert.deepEqual(loaded.errors, []);
const extension = loaded.extensions[0];
assert.equal(extension.tools.size, 0, "rendering must not replace tool execution");
const resolve = extension.toolRenderers[0];
const ctx = { mode: "tui" };
const timers = new Map();
let now = 0, redraws = 0;
mock.method(Date, "now", () => now);
mock.method(globalThis, "setInterval", callback => {
  const handle = { unref() {} };
  timers.set(handle, callback);
  return handle;
});
mock.method(globalThis, "clearInterval", handle => timers.delete(handle));
async function emit(type, event = {}) {
  for (const handler of extension.handlers.get(type) ?? []) await handler({ type, ...event }, ctx);
}
const plain = text => text.replace(/\x1b\[[0-9;]*m/g, "");
const rows = (component, width = 100) => component.render(width).map(plain).filter(Boolean);
const body = component => rows(component).join("\n");
function tool(name, args, id = name) {
  const renderers = resolve(name, () => undefined);
  return new ToolExecutionComponent(name, id, args, { outputPad: 1, showImages: false }, renderers,
    { requestRender() { redraws++; } }, "/tmp");
}
function finish(component, text, isError = false, details) {
  component.updateResult({ content: [{ type: "text", text }], details, isError }, false);
}
try {
  await emit("session_start");
  await emit("agent_start");
  const read = tool("read", { path: "src/app.ts", offset: 2, limit: 30 });
  assert.equal(rows(read).length, 1);
  assert.match(body(read), /├─ ○ read src\/app.ts ▸/);
  assert.equal(timers.size, 0, "argument streaming must not start a timer");
  read.markExecutionStarted();
  assert.match(body(read), /⠋ read/);
  assert.equal(timers.size, 1);
  const old = body(read);
  now = 200;
  for (const tick of timers.values()) tick();
  assert.notEqual(body(read), old, "spinner must animate without new tool output");
  assert.ok(redraws > 0);
  const bash = tool("bash", { command: "npm test\necho done" });
  bash.markExecutionStarted();
  assert.equal(timers.size, 1, "parallel tools share one timer");
  assert.match(body(bash), /npm test echo done/);
  finish(read, "PRIVATE OUTPUT");
  assert.match(body(read), /✓ read/);
  assert.equal(rows(read).length, 1);
  assert.doesNotMatch(body(read), /PRIVATE OUTPUT/);
  assert.ok(read.render(100).join("").includes(themes.theme.fg("success", "✓")));
  assert.equal(timers.size, 1, "the other tool is still running");
  bash.updateResult({ content: [{ type: "text", text: "still running" }], details: undefined }, true);
  assert.match(body(bash), /⠹ bash/);
  assert.match(body(bash), /still running/);
  finish(bash, "FAIL: expected 200, received 500", true);
  assert.match(body(bash), /✕ bash/);
  assert.ok(bash.render(100).join("").includes(themes.theme.fg("error", "✕")));
  assert.equal(timers.size, 0);
  assert.match(body(bash), /▾/);
  assert.match(body(bash), /FAIL: expected 200/);
  bash.setExpanded(true);
  assert.equal(rows(bash).length, 1);
  assert.match(body(bash), /▸/);
  bash.setExpanded(false);
  assert.match(body(bash), /FAIL: expected 200/);

  // Exercise Pi's own MouseRegion wrapper, not a simulated expansion callback.
  const click = read.handleMouse({ type: "click", button: "left", x: 5, y: 1, width: 100, height: 3 });
  assert.equal(click?.handled, true);
  assert.match(body(read), /PRIVATE OUTPUT/);
  assert.match(body(read), /"offset": 2/);
  read.setExpanded(false);

  const edit = tool("edit", { path: "src/app.ts", edits: [{ oldText: "old", newText: "new" }] });
  finish(edit, "Applied", false, { diff: "-1 old\n+1 new\n+2 extra" });
  await Promise.resolve();
  assert.match(body(edit), /\+2 −1/);
  edit.setExpanded(true);
  assert.match(body(edit), /-1 old/);
  assert.match(body(edit), /\+1 new/);
  assert.ok(edit.render(100).join("").includes(themes.theme.fg("success", "+1 new")));
  const write = tool("write", { path: "new.ts", content: "line one\nline two" });
  finish(write, "Written");
  assert.equal(rows(write).length, 1);
  write.setExpanded(true);
  assert.match(body(write), /line one/);
  const mcp = tool("mcp__docs__search", { query: "日本語 😀" });
  finish(mcp, "Found");
  assert.match(body(mcp), /✓ mcp__docs__search 日本語 😀/);
  const unknown = tool("custom", { anything: 42 });
  assert.match(body(unknown), /anything/);
  const partialArgs = tool("read", {});
  partialArgs.updateArgs({ path: "file.ts" });
  assert.match(body(partialArgs), /file.ts/);
  const unsafe = tool("bash", { command: "echo \x1b[31mred\x1b[0m\x07" });
  finish(unsafe, "output\x1b[2J\x07");
  unsafe.setExpanded(true);
  assert.doesNotMatch(unsafe.render(100).join(""), /\x07|\x1b\[2J/);
  const image = tool("read", { path: "picture.png" });
  image.updateResult({ content: [{ type: "image", mimeType: "image/png", data: "" }], isError: false }, false);
  image.setExpanded(true);
  assert.match(body(image), /image: image\/png/);

  for (const appearance of ["light", "dark"]) {
    themes.initTheme(appearance, false);
    for (const component of [read, bash, edit, write, mcp, unsafe]) {
      component.invalidate();
      for (const expanded of [false, true]) {
        component.setExpanded(expanded);
        for (const width of [1, 2, 3, 4, 5, 8, 12, 40, 80, 100, 160]) {
          for (const line of component.render(width)) {
            assert.ok(visibleWidth(line) <= width, `${appearance}: overflow at ${width}: ${plain(line)}`);
          }
        }
      }
    }
  }
  const interrupted = tool("bash", { command: "sleep 100" }, "interrupted");
  interrupted.markExecutionStarted();
  assert.equal(timers.size, 1);
  await emit("agent_end");
  assert.equal(timers.size, 0, "abort must clean up animation");
  interrupted.invalidate();
  assert.equal(timers.size, 0, "resizing an interrupted row must not restart animation");
  await emit("session_shutdown");
  interrupted.invalidate();
  assert.equal(timers.size, 0, "disposed extensions must not restart animation");
  ctx.mode = "json";
  await emit("session_start");
  await emit("agent_start");
  const headless = tool("bash", { command: "true" });
  headless.markExecutionStarted();
  assert.equal(timers.size, 0, "non-TUI modes must not start animation");
  console.log("PASS: real Pi loader/components; queued/running/success/error, spinner, parallel tools, expansion, mouse, args/output/diff, MCP, sanitization, themes, narrow widths, cleanup, non-TUI");
} finally {
  await emit("session_shutdown");
  mock.restoreAll();
}
