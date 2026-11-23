import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
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
const { mixColors, rgbColor, visibleWidth } = await load("@earendil-works/pi-tui/dist/index.js");
const { generateDiffString, generateUnifiedPatch } = await load("@earendil-works/pi-coding-agent/dist/core/tools/edit-diff.js");
themes.initTheme("dark", false);
const extensionPath = fileURLToPath(new URL("../extensions/compact-tools.ts", import.meta.url));
const loaded = await loadExtensions([extensionPath], "/tmp");
assert.deepEqual(loaded.errors, []);
const extension = loaded.extensions[0];
assert.equal(extension.tools.size, 0, "rendering must not replace tool execution");
const resolve = extension.toolRenderers[0];
const ctx = { mode: "tui", cwd: "/tmp" };
const timers = new Map();
let now = 0, redraws = 0;
let onRedraw;
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
function tool(name, args, id = name, cwd = "/tmp") {
  const renderers = resolve(name, () => undefined);
  return new ToolExecutionComponent(name, id, args, { outputPad: 1, showImages: false }, renderers,
    { requestRender() { redraws++; onRedraw?.(); } }, cwd);
}
function finish(component, text, isError = false, details, durationMs) {
  component.updateResult({ content: [{ type: "text", text }], details, isError, durationMs }, false);
}
try {
  await emit("session_start");
  await emit("agent_start");
  const read = tool("read", { path: "src/app.ts", offset: 2, limit: 30 });
  assert.equal(rows(read).length, 1);
  assert.match(body(read), /^ *read src\/app.ts$/);
  assert.doesNotMatch(body(read), /[├│]/);
  assert.equal(timers.size, 0, "argument streaming must not start a timer");
  read.markExecutionStarted();
  assert.match(body(read), /^ *read/);
  assert.equal(timers.size, 1);
  const old = read.render(100).join("\n");
  assert.match(old, /\x1b\[38;/, "running pulse colors the title text");
  assert.doesNotMatch(old, /\x1b\[48;/, "running pulse does not paint a background strip");
  now = 1440;
  for (const tick of timers.values()) tick();
  const animated = read.render(100).join("\n");
  assert.notEqual(animated, old, "pulse must animate without new tool output");
  assert.equal(plain(animated), plain(old), "animation does not add characters or cells");
  assert.ok(redraws > 0);
  const shortPulse = tool("bash", { command: "sleep 1" }, "pulse-short");
  const longPulse = tool("bash", { command: "printf 'a much longer command header for comparison'" }, "pulse-long");
  shortPulse.markExecutionStarted();
  longPulse.markExecutionStarted();
  const pulseFrame = component => component.render(100).join("\n");
  const prompt = themes.theme.fg("toolTitle", themes.theme.bold("$")) + " ";
  const pulseRange = frame => {
    const red = [...frame.replace(prompt, "").matchAll(/\x1b\[38;2;(\d+);\d+;\d+m/g)].map(match => Number(match[1]));
    return Math.max(...red) - Math.min(...red);
  };
  const shortStart = pulseFrame(shortPulse), longStart = pulseFrame(longPulse);
  assert.ok(pulseRange(shortStart) >= 50, "a short command starts with a visible contrast range");
  assert.ok(pulseRange(shortStart) > pulseRange(longStart), "long commands use a softer gradient");
  now += 480;
  for (const tick of timers.values()) tick();
  assert.notEqual(pulseFrame(shortPulse), shortStart, "the short sweep crosses the text in under a second");
  for (const frame of [shortStart, pulseFrame(shortPulse)]) assert.ok(frame.includes(prompt));
  assert.equal(plain(pulseFrame(shortPulse)), plain(shortStart));
  now += 480;
  for (const tick of timers.values()) tick();
  assert.equal(pulseFrame(shortPulse), shortStart, "a short command completes a full cycle in 960 ms");
  assert.notEqual(pulseFrame(longPulse), longStart, "a long command has a longer cycle");
  finish(shortPulse, "");
  finish(longPulse, "");
  const bash = tool("bash", { command: "npm test\necho done" });
  bash.setArgsComplete();
  bash.markExecutionStarted();
  assert.equal(rows(bash).length, 1, "a running command has a collapsed header");
  assert.match(body(bash), /^ *\$ npm test.*\+1 lines/);
  assert.doesNotMatch(body(bash), /bash|echo done/);
  bash.setExpanded(true);
  assert.equal(timers.size, 1, "parallel visible tools share one timer");
  assert.ok(bash.render(100).join("").includes(themes.highlightCode("echo done", "bash")[0]));
  finish(read, "const answer = 42;");
  assert.match(body(read), /^ *read/);
  assert.equal(rows(read).length, 1);
  assert.doesNotMatch(body(read), /const answer/);
  assert.doesNotMatch(read.render(100).join(""), /[✓✕○]|\x1b\[48;/);
  assert.equal(timers.size, 1, "the other tool is still running");
  bash.updateResult({ content: [{ type: "text", text: "still running" }], details: undefined }, true);
  assert.match(body(bash), /^ *\$ npm test/);
  assert.match(body(bash), /still running/);
  bash.setExpanded(false);
  assert.match(body(bash), /still running/);
  finish(bash, "log line 1\nFAIL: expected 200, received 500", true);
  assert.equal(timers.size, 0);
  assert.match(body(bash), /^ *\$ npm test.*\+1 lines/);
  assert.doesNotMatch(bash.render(100).join(""), /\x1b\[48;/);
  assert.ok(bash.render(100).join("").includes(themes.theme.fg("error", themes.theme.bold("$")) + " "));
  assert.ok(bash.render(100).join("").includes(themes.theme.fg("error", "npm test")));
  assert.doesNotMatch(body(bash), /FAIL|log line|bash/);
  const bashClick = bash.handleMouse({ type: "click", button: "left", x: 5, y: 1, width: 100, height: 3 });
  assert.equal(bashClick?.handled, true);
  assert.match(body(bash), /^ *\$ npm test/);
  assert.match(body(bash), /^ {2}echo done/m);
  for (const commandLine of ["npm test", "echo done"]) {
    assert.ok(bash.render(100).join("").includes(themes.theme.fg("error", commandLine)));
  }
  assert.match(body(bash), /log line 1/);
  assert.match(body(bash), /FAIL: expected 200/);
  assert.match(body(bash), /npm test[\s\S]*echo done/);
  assert.match(bash.render(100).map(plain).join("\n"), /echo done[^\n]*\n *\n {2}log line 1/);
  assert.ok(bash.render(100)[1].startsWith("\x1b[48;2;10;51;62m"));
  assert.doesNotMatch(body(bash), /[▸▾]/);
  bash.setExpanded(false);
  assert.equal(rows(bash).length, 1);
  assert.doesNotMatch(body(bash), /FAIL/);

  // Exercise Pi's own MouseRegion wrapper, not a simulated expansion callback.
  const click = read.handleMouse({ type: "click", button: "left", x: 5, y: 1, width: 100, height: 3 });
  assert.equal(click?.handled, true);
  assert.match(body(read), /const answer = 42/);
  assert.ok(read.render(100).join("").includes(themes.highlightCode("const answer = 42;", "typescript")[0]));
  assert.doesNotMatch(body(read), /"offset"/);
  assert.doesNotMatch(body(read), /[├│]/);
  read.setExpanded(false);

  const edit = tool("edit", { path: "src/app.ts", edits: [{ oldText: "old", newText: "new" }] });
  const editDiff = ["-1 const count = 1;", "+1 const count = 2;", " 2 // context", ...Array.from({ length: 12 }, (_, i) => `+${i + 3} // line ${i + 3}`)].join("\n");
  finish(edit, "Applied", false, { diff: editDiff });
  await Promise.resolve();
  assert.match(body(edit), /\+13 −1/);
  assert.match(body(edit), /^ {3}1 - const count = 1/m);
  assert.match(body(edit), /^ {3}1 \+ const count = 2/m);
  assert.match(body(edit), /… 3 more lines/);
  assert.doesNotMatch(body(edit), /line 14/);
  const diffAnsi = edit.render(100).join("\n");
  assert.ok(diffAnsi.includes(themes.theme.style("… 3 more lines", { fg: "borderMuted", dim: true })));
  for (const [color, sign, value] of [["toolDiffAdded", "+", "2"], ["toolDiffRemoved", "-", "1"]]) {
    assert.ok(diffAnsi.includes(themes.theme.fg(color, sign) + " const count = " + themes.theme.fg(color, value) + ";"));
  }
  assert.ok(diffAnsi.includes(themes.theme.fg("toolDiffAdded", "+") + " // line 3"));
  edit.setExpanded(true);
  assert.match(body(edit), /line 13/);
  assert.doesNotMatch(body(edit), /more lines|oldText|[├│]/);

  const inline = tool("edit", { path: "items.ts" }, "inline-edit");
  const before = ["far before", "near before 2", "near before 1", "[left, right]", "near after 1", "near after 2", "gap middle 1", "gap middle 2", "near second 2", "near second 1", "version = 1", "after second 1", "after second 2", "far after"].join("\n");
  const after = before.replace("[left, right]", "[left, center, right]").replace("version = 1", "version = 2");
  finish(inline, "Applied", false, generateDiffString(before, after));
  await Promise.resolve();
  assert.match(body(inline), /items\.ts \+1 −1 ~1/);
  assert.match(body(inline), /~ \[left, center, right\]/);
  assert.doesNotMatch(body(inline), /\[left, right\]/);
  assert.ok(inline.render(100).join("\n").includes(themes.theme.fg("toolDiffAdded", "center")));
  for (const text of ["near before 1", "near before 2", "near after 1", "near after 2", "near second 1", "near second 2", "after second 1", "after second 2"]) {
    assert.ok(body(inline).includes(text));
  }
  inline.setExpanded(true);
  assert.doesNotMatch(body(inline), /far before|far after|gap middle/);
  assert.match(body(inline), /11 - version = 1[\s\S]*11 \+ version = 2/);
  assert.match(body(inline), /near after 2[^\n]*\n[^\n]*…[^\n]*\n[^\n]*near second 2/);
  if (spawnSync("delta", ["--version"]).status === 0) for (const appearance of ["dark", "light"]) {
    themes.initTheme(appearance, false);
    const [removed, added] = appearance === "light"
      ? [["48;2;242;223;206", "48;2;230;180;154"], ["48;2;231;236;207", "48;2;206;221;158"]]
      : [["48;2;57;38;32", "48;2;101;55;42"], ["48;2;36;51;33", "48;2;64;87;42"]];
    const deltaEdit = tool("edit", { path: "version.txt" }, "delta-edit");
    const oldText = 'far before\nmore before\nnear before 2\nnear before 1\nversion = "5.6.1"\nnear after 1\nnear after 2\nmore after\nfar after\n';
    const newText = oldText.replace("5.6.1", "6.2").replace("near after 1\n", "near after 1\nextra | line\n");
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("delta did not request a redraw")), 4_000);
      onRedraw = () => {
        if (!deltaEdit.render(100).some(line => line.includes(`\x1b[${added[1]}m`))) return;
        clearTimeout(timeout);
        onRedraw = undefined;
        resolve();
      };
      finish(deltaEdit, "Applied", false, {
        ...generateDiffString(oldText, newText), patch: generateUnifiedPatch("version.txt", oldText, newText),
      });
    });
    const deltaAnsi = deltaEdit.render(100).join("\n");
    const deltaRows = deltaEdit.render(100).filter(line => line.includes("version ="));
    assert.equal(deltaRows.length, 2);
    const [removedText, addedText] = appearance === "light" ? ["115;61;36", "68;88;18"] : ["198;158;137", "166;181;139"];
    for (const [line, colors, fg] of [[deltaRows[0], removed, removedText], [deltaRows[1], added, addedText]]) {
      assert.ok(line.includes(`\x1b[${colors[0]};38;2;${fg}m`), "changed text uses the expected foreground and background");
      assert.ok(line.includes(`\x1b[${colors[1]}m`), "intraline emphasis keeps its stronger background");
    }
    const [red, green] = appearance === "light" ? ["150;46;36", "66;91;22"] : ["239;155;139", "172;202;121"];
    for (const [line, bg, fg] of [[deltaRows[0], removed[0], red], [deltaRows[1], added[0], green]]) {
      assert.ok(line.includes(`\x1b[38;2;${fg}m`) && line.includes(`\x1b[${bg}m 5 `), "changed number uses the row background and a distinct foreground");
    }
    const quiet = { fg: appearance === "light" ? mixColors(themes.theme.colors.borderMuted, rgbColor(255, 249, 234), 0.27, "srgb") : "borderMuted", dim: true };
    assert.ok(deltaAnsi.includes(themes.theme.style(" 3 ", quiet) + themes.theme.fg("toolDiffContext", "  near before 2")));
    assert.doesNotMatch(deltaAnsi, /\x1b\[[0-9]*K/, "delta must not erase terminal cells");
    assert.match(body(deltaEdit), /^ {3}5 - version = "5\.6\.1"/m);
    assert.match(body(deltaEdit), /^ {3}5 \+ version = "6\.2"/m);
    assert.match(body(deltaEdit), /^ {3}3 {3}near before 2/m);
    assert.match(body(deltaEdit), /^ {3}7 \+ extra \| line/m);
    assert.match(body(deltaEdit), /^ {3}8 {3}near after 2/m);
    assert.match(body(deltaEdit), /near before 2[\s\S]*near after 2/);
    assert.doesNotMatch(body(deltaEdit), /\bdelta\b|@@|---|far before|more before|far after/);
    assert.doesNotMatch(rows(deltaEdit)[0], /[▸▾]/);
    deltaEdit.setExpanded(true);
    assert.match(body(deltaEdit), /far before[\s\S]*far after/);
    const expandedDeltaRows = deltaEdit.render(100).filter(line => line.includes("version ="));
    assert.deepEqual(expandedDeltaRows.map(line => plain(line).trimEnd()), deltaRows.map(line => plain(line).trimEnd()));
    assert.ok(expandedDeltaRows[0].includes(`\x1b[${removed[1]}m`));
    assert.ok(expandedDeltaRows[1].includes(`\x1b[${added[1]}m`));
    deltaEdit.setExpanded(false);
    assert.equal(deltaEdit.render(100).join("\n"), deltaAnsi, "collapsing reuses the cached delta preview");
  }
  themes.initTheme("dark", false);
  const fixture = mkdtempSync(join(tmpdir(), "pi-file-scope-"));
  try {
    const project = join(fixture, "project");
    const subdir = join(project, "src");
    mkdirSync(subdir, { recursive: true });
    writeFileSync(join(project, ".git"), "gitdir: ../worktree-meta\n");
    symlinkSync(fixture, join(subdir, "scratch"), "dir");
    const projectRead = tool("read", { path: "../tmp/local.ts" }, "project-read", subdir);
    finish(projectRead, "code");
    assert.ok(projectRead.render(100).join("").includes(themes.theme.fg("accent", "../tmp/local.ts")));
    assert.doesNotMatch(body(projectRead), /\[tmp\]/, "a project inside the system temp directory still wins");
    const tempEdit = tool("edit", { path: "scratch/new.ts" }, "temp-edit", subdir);
    finish(tempEdit, "Applied", false, { diff: "+1 const temporary = true;" });
    await Promise.resolve();
    assert.ok(tempEdit.render(100).join("").includes(themes.theme.fg("muted", "[tmp] scratch/new.ts")));
    assert.doesNotMatch(body(tempEdit), /const temporary/);
    tempEdit.setExpanded(true);
    assert.match(body(tempEdit), /const temporary/);
    tempEdit.setExpanded(false);
    finish(tempEdit, "permission denied", true);
    assert.match(body(tempEdit), /permission denied/);
    assert.ok(tempEdit.render(100).join("").includes(themes.theme.fg("error", themes.theme.bold("edit"))));
    const externalWrite = tool("write", { path: "~/.example.conf" }, "external-write", subdir);
    finish(externalWrite, "Written");
    assert.ok(externalWrite.render(100).join("").includes(themes.theme.fg("warning", "[external] ~/.example.conf")));
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
  const write = tool("write", { path: "new.ts", content: "line one\nline two" });
  finish(write, "Written");
  assert.equal(rows(write).length, 1);
  write.setExpanded(true);
  assert.match(body(write), /line one/);
  assert.doesNotMatch(body(write), /^ +\d+ (?:\+ )?line one/m);
  const grep = tool("grep", { path: "src", pattern: "needle" });
  finish(grep, "a.ts:1: needle\na.ts-2- context\nb.ts:3: needle");
  const find = tool("find", { pattern: "*.ts" });
  finish(find, "a.ts\nb.ts\n\n[limit reached]", false, { resultLimitReached: 2 });
  const ls = tool("ls", { path: "src" });
  finish(ls, "(empty directory)");
  const mcp = tool("mcp__docs__search", { query: "日本語 😀" });
  finish(mcp, '{"results":["first","second"]}');
  await Promise.resolve();
  assert.match(body(grep), /grep needle · src · 2 matches/);
  assert.doesNotMatch(body(grep), /context/);
  grep.setExpanded(true);
  assert.match(body(grep), /a\.ts-2- context/);
  assert.match(body(find), /find \*\.ts · \. · 2 files \(limited\)/);
  assert.match(body(ls), /ls src · 0 entries/);
  assert.match(body(mcp), /^ *search · docs · 2 results/);
  assert.doesNotMatch(body(mcp), /日本語|first/);
  mcp.setExpanded(true);
  assert.match(body(mcp), /日本語 😀/);
  assert.match(body(mcp), /first/);
  const writeFixture = mkdtempSync(join(tmpdir(), "pi-write-preview-"));
  try {
    const existing = join(writeFixture, "old.txt");
    const fresh = join(writeFixture, "new.txt");
    writeFileSync(existing, "old");
    for (const [path, status] of [[existing, "Overwritten"], [fresh, "New file"]]) {
      await emit("tool_call", { toolName: "write", toolCallId: path, input: { path, content: "written" } });
      const call = tool("write", { path, content: "written" }, path, writeFixture);
      finish(call, "Written");
      assert.match(body(call), new RegExp(`· ${status}`));
      assert.equal(rows(call).length, 1, "write stays collapsed without a numbered preview");
    }
  } finally {
    rmSync(writeFixture, { recursive: true, force: true });
  }
  const unknown = tool("custom", { anything: 42 });
  assert.match(body(unknown), /anything/);
  const partialArgs = tool("read", {});
  partialArgs.updateArgs({ path: "file.ts" });
  assert.match(body(partialArgs), /file.ts/);
  const code = tool("codemode", { code: `text('${"long script ".repeat(12)}TAIL');\ntext('second line');` });
  code.updateResult({ content: [{ type: "text", text: "Script completed\nWall time 1.25 seconds\nOutput:\n" },
    { type: "text", text: "script result" }], details: { calls: [] }, durationMs: 1250 }, false);
  assert.equal(rows(code).length, 1);
  assert.match(body(code), /^ codemode text.*\+1 lines +1\.3 s {3}$/);
  for (const component of [bash, code]) {
    assert.ok(component.render(100).join("").includes(themes.theme.style("+1 lines", { fg: "borderMuted", dim: true })));
  }
  assert.doesNotMatch(body(code), /TAIL|second line|script result/);
  assert.ok(rows(code, 24).every(row => visibleWidth(row) <= 24));
  code.setExpanded(true);
  assert.match(body(code), /TAIL[\s\S]*second line[^\n]*\n *\n {2}script result/);
  assert.doesNotMatch(body(code), /Wall time|Output:/);
  const shellGrep = tool("bash", { command: "rg -n 'needle' src", timeout: 20 }, "shell-rg");
  finish(shellGrep, "a.ts:1: needle\nb.ts:3: needle", false, undefined, 1250);
  const shellFind = tool("bash", { command: "find src -name '*.ts'" }, "shell-find");
  finish(shellFind, "src/a.ts\nsrc/b.ts", false, undefined, 32);
  const piped = tool("bash", { command: "rg -n needle src | head" }, "shell-piped");
  finish(piped, "a.ts:1: needle", false, undefined, 25);
  await Promise.resolve();
  assert.match(body(shellGrep), /rg -n 'needle' src \(timeout 20 s\) · src · 2 match lines +1\.3 s {3}$/);
  assert.match(body(shellFind), /src · 2 paths +32 ms {3}$/);
  for (const text of [" (timeout 20 s)", "1.3 s"]) {
    assert.ok(shellGrep.render(100).join("").includes(themes.theme.style(text, { fg: "borderMuted", dim: true })));
  }
  const pending = tool("bash", { command: "sleep 2", timeout: 5 }, "pending-timeout");
  pending.markExecutionStarted();
  assert.match(body(pending), /sleep 2 \(timeout 5 s\)$/);
  assert.ok(pending.render(100).join("").includes(themes.theme.style(" (timeout 5 s)", { fg: "borderMuted", dim: true })));
  finish(pending, "");
  assert.doesNotMatch(body(piped), /match lines|paths|timeout/);
  const long = tool("bash", { command: `printf '%s' '${"very long command ".repeat(8)}TAIL'`, timeout: 30 }, "shell-long");
  long.markExecutionStarted();
  const runningHeader = long.render(100).join("\n");
  assert.ok(new Set(runningHeader.match(/\x1b\[38;2;[\d;]+m/g)).size > 4, "long command has a fine-grained foreground gradient");
  assert.doesNotMatch(runningHeader, /\x1b\[48;/);
  finish(long, "done", false, undefined, 340);
  const header = rows(long, 100)[0];
  assert.match(header, /\.\.\. \(timeout 30 s\) +340 ms {3}$/);
  assert.equal(visibleWidth(header), 100);
  assert.ok(visibleWidth(header.slice(0, header.indexOf("..."))) + 3 <= 70);
  long.setExpanded(true);
  for (const width of [40, 100]) {
    const expanded = rows(long, width).map(row => row.trimEnd());
    const text = expanded.join("\n");
    assert.equal(text.match(/printf/g)?.length, 1, "the wrapped command is not repeated");
    assert.equal(text.match(/very\s+long/g)?.length, 8, "the full command remains visible");
    assert.match(text, /TAIL'[ \n]+\(timeout 30 s\)[ \n]+340 ms[ \n]+done$/);
  }
  const timed = tool("bash", { command: "echo 12345678901234567890", timeout: 30 }, "timed-expanded");
  finish(timed, "done", false, undefined, 340);
  timed.setExpanded(true);
  assert.match(rows(timed, 80)[0], /echo \d+ \(timeout 30 s\) +340 ms {3}$/);
  const narrowTimed = rows(timed, 45).map(row => row.trim());
  assert.deepEqual(narrowTimed.filter(Boolean), ["$ echo 12345678901234567890 (timeout 30 s)", "340 ms", "done"]);
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
    bash.setExpanded(true);
    const background = appearance === "dark" ? "\x1b[48;2;10;51;62m" : "\x1b[48;2;241;234;215m";
    assert.ok(bash.render(100)[1].startsWith(background));
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
  const renderers = resolve("bash", () => undefined);
  const cacheContext = { expanded: true, isPartial: false, isError: false, outputPad: 1, state: {} };
  const result = { content: [{ type: "text", text: "Unicode output: 日本語 😀 repeated words" }] };
  const cachedCall = renderers.renderCall({ command: "printf example" }, themes.theme, cacheContext);
  const cachedResult = renderers.renderResult(result, cacheContext, themes.theme, cacheContext);
  for (const component of [cachedCall, cachedResult]) {
    const wide = component.render(80);
    assert.strictEqual(component.render(80), wide, "unchanged frames must reuse prepared lines");
    const narrow = component.render(12);
    assert.notDeepEqual(narrow, wide, "resizing must reflow the cached lines");
    assert.strictEqual(component.render(12), narrow);
    component.invalidate();
    const rebuilt = component.render(12);
    assert.notStrictEqual(rebuilt, narrow, "invalidation must discard prepared lines");
    assert.deepEqual(rebuilt, narrow);
  }
  const compactArgs = { command: "printf example" };
  const savedCall = renderers.renderCall(compactArgs, themes.theme, cacheContext).render(80);
  const savedResult = renderers.renderResult(result, cacheContext, themes.theme, cacheContext).render(80);
  const closedContext = { ...cacheContext, expanded: false };
  assert.notDeepEqual(renderers.renderCall(compactArgs, themes.theme, closedContext).render(80), savedCall);
  assert.strictEqual(renderers.renderCall(compactArgs, themes.theme, cacheContext).render(80), savedCall);
  assert.strictEqual(renderers.renderResult({ ...result }, cacheContext, themes.theme, cacheContext).render(80), savedResult);
  const changedResult = { content: [{ type: "text", text: "changed output" }] };
  assert.match(plain(renderers.renderResult(changedResult, cacheContext, themes.theme, cacheContext).render(80).join("\n")), /changed output/);
  const live = tool("bash", { command: "ansible-playbook site.yml" }, "live-tail");
  const idleHeight = live.render(100).length;
  live.markExecutionStarted();
  assert.equal(live.render(100).length, idleHeight, "no space reserved before results");
  live.updateResult({ content: [] }, true);
  assert.equal(live.render(100).length, idleHeight, "an empty update adds no rows");
  live.updateResult({ content: [{ type: "text", text: "first line" }] }, true);
  assert.equal(live.render(100).length, idleHeight + 1, "the tail grows with the output");
  assert.match(plain(live.render(100)[idleHeight]), /first line/);
  live.updateResult({ content: [{ type: "text", text: "1\n2\n3\n4\n5" }] }, true);
  assert.deepEqual(rows(live).slice(1).map(line => line.trim()), ["1", "2", "3", "4", "5"]);
  live.updateResult({ content: [{ type: "text", text: "1\n2\n3\n4\n5\n6" }] }, true);
  assert.deepEqual(rows(live).slice(1).map(line => line.trim()), ["… 2 earlier lines", "3", "4", "5", "6"]);
  live.updateResult({ content: [{ type: "text", text: "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\n\x1b[32mok: [host]\x1b[0m\x1b[2J\n" }] }, true);
  assert.deepEqual(rows(live).slice(1).map(line => line.trim()), ["… 3 earlier lines", "line 4", "line 5", "line 6", "ok: [host]"]);
  assert.match(live.render(100).join("\n"), /\x1b\[32mok:/);
  assert.doesNotMatch(live.render(100).join("\n"), /\x1b\[2J/);
  live.updateResult({ content: [{ type: "text", text: "x".repeat(150) + " latest" }] }, true);
  assert.equal(live.render(20).length, idleHeight + 5, "wrapped output also fits the hint inside the cap");
  assert.match(plain(live.render(20)[idleHeight]), /earlier/);
  assert.match(body(live), /latest/);
  assert.doesNotMatch(body(live), /ok: \[host\]/);
  finish(live, "completed");
  assert.equal(live.render(100).length, idleHeight, "the live tail disappears when the call finishes");
  live.setExpanded(true);
  assert.match(body(live), /completed/);
  const cacheStream = tool("bash", { command: "printf example" }, "cache-stream");
  cacheStream.setExpanded(true);
  cacheStream.updateResult({ content: [{ type: "text", text: "intermediate result" }] }, true);
  assert.match(body(cacheStream), /intermediate result/);
  const json = '{"passed":true}';
  finish(cacheStream, json);
  assert.match(body(cacheStream), /"passed":true/);
  assert.ok(cacheStream.render(100).join("").includes(themes.theme.fg("toolOutput", json)), "bash output is not syntax-highlighted");
  assert.doesNotMatch(body(cacheStream), /intermediate result/);
  cacheStream.setExpanded(false);
  assert.equal(rows(cacheStream).length, 1, "a successful command keeps just its header");
  assert.doesNotMatch(body(cacheStream), /"passed"/);

  const interrupted = tool("bash", { command: "sleep 100" }, "interrupted");
  interrupted.setExpanded(true);
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
  headless.setExpanded(true);
  headless.markExecutionStarted();
  assert.equal(timers.size, 0, "non-TUI modes must not start animation");
  console.log("PASS: real Pi loader/components; queued/running/success/error, spinner, parallel tools, expansion, mouse, args/output/diff, MCP, sanitization, themes, narrow widths, cleanup, non-TUI");
} finally {
  await emit("session_shutdown");
  mock.restoreAll();
}
