import assert from "node:assert/strict";
import { stripVTControlCharacters } from "node:util";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { spawn } from "node:child_process";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { setTimeout as delay } from "node:timers/promises";
import { mock } from "node:test";

const installedAgentDir = join(homedir(), ".pi", "agent");
const modules = process.env.PI_TEST_MODULES ?? join(installedAgentDir, "install", "releases",
  readFileSync(join(installedAgentDir, "install", "current-version"), "utf8").trim(), "node_modules");
const testHome = mkdtempSync(join(tmpdir(), "pi-frame-"));
const originalHome = process.env.HOME;
const agentDir = join(testHome, ".pi", "agent");
mkdirSync(join(agentDir, "bin"), { recursive: true });
symlinkSync(realpathSync(process.env.PI_TEST_STATUSLINE ?? join(installedAgentDir, "bin", "solarized-statusline")),
  join(agentDir, "bin", "solarized-statusline"));
process.env.HOME = testHome;
const extensionPath = fileURLToPath(new URL("../extensions/solarized-status.ts", import.meta.url));
const themesPath = fileURLToPath(new URL("../themes/", import.meta.url));
let providerScans = 0;
const readdir = fs.readdirSync;
mock.method(fs, "readdirSync", function (dir, ...args) {
  if (dir === join(agentDir, "cache", "statusline", "openai")) providerScans++;
  return readdir.call(this, dir, ...args);
});
syncBuiltinESMExports();
const load = path => import(pathToFileURL(join(modules, path)).href);
const { loadExtensions } = await load("@earendil-works/pi-coding-agent/dist/core/extensions/loader.js");
const { createEventBus } = await load("@earendil-works/pi-coding-agent/dist/core/event-bus.js");
const { CustomEditor } = await load("@earendil-works/pi-coding-agent/dist/modes/interactive/components/custom-editor.js");
const { AssistantMessageComponent } = await load("@earendil-works/pi-coding-agent/dist/modes/interactive/components/assistant-message.js");
const { UserMessageComponent } = await load("@earendil-works/pi-coding-agent/dist/modes/interactive/components/user-message.js");
const { FooterComponent } = await load("@earendil-works/pi-coding-agent/dist/modes/interactive/components/footer.js");
const { KeybindingsManager } = await load("@earendil-works/pi-coding-agent/dist/core/keybindings.js");
const themes = await load("@earendil-works/pi-coding-agent/dist/modes/interactive/theme/theme.js");
const { Markdown, colorToRgb, mixColors, rgbColor, visibleWidth } = await load("@earendil-works/pi-tui/dist/index.js");
themes.initTheme("dark", false);
let now = 10_000;
let wall = 1_000_000;
mock.method(performance, "now", () => now);
mock.method(Date, "now", () => wall);
const events = createEventBus();
const loaded = await loadExtensions([extensionPath], "/tmp", events);
assert.deepEqual(loaded.errors, []);
let effort = "medium";
loaded.runtime.getThinkingLevel = () => effort;
const messages = [];
loaded.runtime.sendMessage = message => messages.push(message);
const entries = [];
loaded.runtime.appendEntry = (customType, data) => entries.push({ type: "custom", customType, data });
const extension = loaded.extensions[0];
const markdown = "### A **heading**\n\n```sh\n### a literal comment\n```\n\n#### Another heading";
const transform = isStreaming => extension.markdownTransformer.transformer(markdown, { isStreaming, messageType: "assistant", availableWidth: 80 });
assert.equal(transform(true), markdown);
assert.equal(transform(false), "## A **heading**\n\n```sh\n### a literal comment\n```\n\n## Another heading");
const markdownScreen = stripVTControlCharacters(new Markdown(transform(false), 0, 0, themes.getMarkdownTheme()).render(80).join("\n"));
assert.match(markdownScreen, /^A heading *$/m);
assert.match(markdownScreen, /### a literal comment/);
let footer, editor, sessionName, hiddenThinkingLabel, queued = false, workingVisible = true;
const tui = { requestRender() {}, terminal: { rows: 42, columns: 151 } };
const statuses = new Map();
const widgets = new Map();
const keybindings = new KeybindingsManager();
const ctx = {
  mode: "tui", model: { provider: "openai", id: "gpt-6.1-sol", name: "GPT-6.1 SOL", contextWindow: 272000 },
  sessionManager: { getSessionId: () => "frame-test", getSessionName: () => sessionName, getBranch: () => [] },
  getContextUsage: () => ({ percent: 24, contextWindow: 272000 }),
  hasPendingMessages: () => queued,
  ui: {
    theme: themes.theme,
    setWidget(name, content) { if (content === undefined) widgets.delete(name); else widgets.set(name, content); },
    setWorkingVisible(value) { workingVisible = value; },
    setHiddenThinkingLabel(value) { hiddenThinkingLabel = value; },
    setEditorComponent(factory) {
      editor = factory?.(tui, themes.getEditorTheme(), keybindings);
      editor?.setPaddingX(0);
    },
    setFooter(factory) {
      footer?.dispose();
      footer = factory?.(tui, themes.theme, { getExtensionStatuses: () => statuses });
    },
  },
};
async function emit(type, event = {}) {
  for (const handler of extension.handlers.get(type) ?? []) await handler({ type, ...event }, ctx);
}
const plain = text => text.replace(/\x1b\[[0-9;]*m/g, "").replace(/\x1b_pi:[^\x07]*\x07/g, "");
async function waitForRibbon(pattern, width = 151) {
  const deadline = new Date().getTime() + 3000;
  const ribbon = () => footer.render(width).map(plain).join("\n");
  while (!pattern.test(ribbon()) && new Date().getTime() < deadline) await delay(20);
  assert.match(ribbon(), pattern);
}
const top = (width = 151) => plain(editor.render(width)[0]);
const assistant = (overrides = {}) => ({
  role: "assistant", timestamp: wall, durationMs: 1600,
  content: [{ type: "text", text: "hello world" }],
  usage: { output: 320, reasoning: 200 }, stopReason: "stop", ...overrides,
});
const sessionFile = join(agentDir, "cache", "statusline", "sessions", `${process.pid}.json`);
const ownSession = () => JSON.parse(readFileSync(sessionFile, "utf8"));
const wave = /^\s*[⠂⠒⠲⠴⠤⠠]\s*$/;
async function start() {
  now = 10_000;
  await emit("agent_start");
  assert.equal(ownSession().state, "running");
  assert.match(top(), wave);
  await emit("before_provider_request");
  assert.match(top(), wave);
  await emit("message_start", { message: assistant({ timestamp: wall - 200 }) });
}
async function delta(type, at, text = "chunk") {
  now = at;
  await emit("message_update", { assistantMessageEvent: { type, delta: text } });
}
async function metrics() {
  await extension.commands.get("statusline-metrics").handler("", ctx);
  return JSON.parse(messages.at(-1).content.match(/```json\n([\s\S]*?)\n```/)[1]);
}
try {
  await emit("session_start");
  const packageDir = join(agentDir, "subagent-package", "pi-subagents");
  mkdirSync(join(packageDir, "bundle"), { recursive: true });
  mkdirSync(join(packageDir, "src", "api"), { recursive: true });
  writeFileSync(join(packageDir, "bundle", "index.js"), `export default function(pi) {
    pi.registerTool({ name: "subagent", description: "Delegate", parameters: {} });
    pi.registerCommand("subagents-fleet", { handler: (_args, ctx) => ctx.ui.notify("Fleet opened") });
    pi.registerCommand("run", { handler: (_args, ctx) => ctx.ui.notify("Agent launched") });
  }`);
  writeFileSync(join(packageDir, "src", "api", "capability-ceiling.js"), `export function registerSubagentCapabilityCeiling({ ceiling }) {
    globalThis.testCeiling = ceiling;
    return { update(value) { globalThis.testCeiling = value; }, dispose() { delete globalThis.testCeiling; } };
  }`);
  const modes = await loadExtensions([fileURLToPath(new URL("../extensions/work-mode.ts", import.meta.url))], "/tmp");
  assert.deepEqual(modes.errors, []);
  const mode = modes.extensions[0];
  const buildTools = ["read", "bash", "write", "edit", "codemode", "mcp__knowledge__propose_edit"];
  let activeTools = buildTools, idle = true;
  const subagent = mode.tools.get("subagent").definition;
  assert.equal(subagent.defaultActive, false);
  modes.runtime.getThinkingLevel = () => "low";
  let choice, menu;
  const notifications = [];
  modes.runtime.getActiveTools = () => activeTools;
  modes.runtime.getAllTools = () => [...buildTools, "subagent", "grep", "mcp__knowledge__read", "mcp__context7__resolve_library_id", "mcp__context7__query_docs"].map(name => ({ name }));
  modes.runtime.setActiveTools = names => { activeTools = names; };
  const modeContext = { ...ctx, isIdle: () => idle, sessionManager: { ...ctx.sessionManager, getEntries: () => [] }, ui: { ...ctx.ui,
    setStatus: (key, value) => statuses.set(key, value), notify: text => notifications.push(text),
    select: async (_title, options) => { menu = options; return choice; },
  } };
  const modeEvent = (type, data = {}) => mode.handlers.get(type)[0]({ type, ...data }, modeContext);
  const shortcut = mode.shortcuts.get("shift+tab");
  activeTools = [...buildTools, "subagent"];
  await modeEvent("session_start");
  assert.deepEqual(activeTools, buildTools, "resumed tools cannot enable Agents by default");
  assert.match(top(), /^ +· Ready {3}$/);
  const neutralFrame = editor.render(151)[1];
  assert.ok(neutralFrame.includes(`${themes.theme.getFgAnsi("borderMuted")}╭`));
  const sections = {};
  await modeEvent("before_agent_start", { systemPromptOptions: { sections } });
  assert.match(sections.work_mode, /Pair.*wait for the user/);
  assert.doesNotMatch(sections.work_mode, /Ask only when stuck/);
  assert.doesNotMatch(sections.work_mode, /subagent/);
  assert.doesNotMatch(top(), /EXECUTE|PAIR/);
  const profileShortcut = mode.shortcuts.get("alt+r");
  const agentsShortcut = mode.shortcuts.get("alt+g");
  await mode.commands.get("execute").handler("", modeContext);
  assert.deepEqual(menu, ["Pair (active)", "Autonomous"]);
  menu = undefined;
  await profileShortcut.handler(modeContext);
  assert.equal(menu, undefined, "cycling does not open the selector");
  assert.match(top(), /^ {3}AUTONOMOUS +· Ready {3}$/);
  await modeEvent("before_agent_start", { systemPromptOptions: { sections } });
  assert.match(sections.work_mode, /Autonomous.*verification/);
  assert.match(sections.work_mode, /Ask only when stuck: the same failure twice with no new hypothesis/);
  assert.ok(editor.render(151)[0].includes(themes.theme.fg("thinkingText", "AUTONOMOUS")));
  assert.equal(editor.render(151)[1], neutralFrame);
  assert.doesNotMatch(plain(editor.render(151)[2]), /EXECUTE/);
  assert.doesNotMatch(editor.render(151)[2], /\x1b\[48;/);
  await shortcut.handler(modeContext);
  assert.notEqual(editor.render(151)[1], neutralFrame);
  assert.match(top(), /^ {3}EXPLORE +· Ready {3}$/);
  const exploreColor = rgbColor(111, 172, 207);
  assert.ok(editor.render(151)[0].includes(themes.theme.style("EXPLORE", { fg: exploreColor })));
  assert.doesNotMatch(editor.render(151).join(""), /\x1b\[48;/);
  editor.setText("x".repeat(145));
  assert.doesNotMatch(plain(editor.render(151)[2]), /EXPLORE/);
  assert.match(top(), /^ {3}EXPLORE/);
  assert.equal(plain(editor.render(151).slice(2).join("")).match(/x/g)?.length, 145);
  editor.setText("");
  assert.deepEqual(activeTools, ["read", "grep", "mcp__knowledge__read", "mcp__context7__resolve_library_id", "mcp__context7__query_docs"]);
  for (const toolName of ["write", "edit", "bash", "codemode", "mcp__knowledge__propose_edit", "subagent"]) {
    assert.equal((await modeEvent("tool_call", { toolName })).block, true);
  }
  assert.equal(await modeEvent("tool_call", { toolName: "read" }), undefined);
  const runSubagent = () => mode.commands.get("run").handler("reviewer Check the diff", modeContext);
  await mode.commands.get("agents").handler("", modeContext);
  assert.equal(notifications.pop(), "Fleet opened");
  await runSubagent();
  assert.match(notifications.pop(), /Switch to Execute before launching a subagent/);
  choice = "Pair";
  await mode.commands.get("execute").handler("", modeContext);
  assert.deepEqual(menu, ["Autonomous (active)", "Pair"]);
  await agentsShortcut.handler(modeContext);
  assert.match(notifications.pop(), /Agents enabled for Execute/);
  assert.deepEqual(globalThis.testCeiling.allowedAgents, []);
  await runSubagent();
  assert.match(notifications.pop(), /Switch to Execute before launching a subagent/);
  assert.match(top(), /^ {3}EXPLORE/);
  await modeEvent("before_agent_start", { systemPromptOptions: { sections } });
  assert.match(sections.work_mode, /switch to Execute/);
  assert.doesNotMatch(sections.work_mode, /subagent/);
  idle = false;
  await shortcut.handler(modeContext);
  assert.equal(notifications.length, 1);
  assert.match(top(), /^ {3}EXPLORE/);
  idle = true;
  await shortcut.handler(modeContext);
  assert.match(top(), /^ {3}AGENTS +· Ready/);
  await modeEvent("before_agent_start", { systemPromptOptions: { sections } });
  assert.match(sections.work_mode, /Pair.*use the subagent tool/);
  assert.match(sections.work_mode, /Every scope, once: a subagent reviews the diff/);
  assert.match(sections.work_mode, /cheaper model/);
  assert.deepEqual(activeTools, [...buildTools, "subagent"]);
  assert.equal(globalThis.testCeiling.allowedAgents, undefined);
  assert.deepEqual(globalThis.testCeiling.allowedTools, ["read", "grep", "find", "ls", "bash", "contact_supervisor"]);
  await runSubagent();
  assert.equal(notifications.pop(), "Agent launched");
  idle = false;
  await agentsShortcut.handler(modeContext);
  assert.match(top(), /^ {3}AGENTS +· Ready/);
  assert.equal(notifications.length, 2);
  idle = true;
  await profileShortcut.handler(modeContext);
  assert.match(top(), /^ {3}AUTONOMOUS · AGENTS/);
  assert.deepEqual(activeTools, [...buildTools, "subagent"]);
  await agentsShortcut.handler(modeContext);
  assert.doesNotMatch(top(), /AGENTS/);
  assert.deepEqual(activeTools, buildTools);
  activeTools = [...buildTools, "subagent"];
  await modeEvent("session_tree");
  assert.deepEqual(activeTools, buildTools, "switching branches cannot re-enable Agents");
  await runSubagent();
  assert.match(notifications.pop(), /Enable Agents with Option\+G in Execute/);
  assert.equal((await modeEvent("tool_call", { toolName: "subagent" })).block, true);
  await modeEvent("before_agent_start", { systemPromptOptions: { sections } });
  assert.doesNotMatch(sections.work_mode, /subagent/);
  await profileShortcut.handler(modeContext);
  assert.match(top(), /^ +· Ready {3}$/);
  await agentsShortcut.handler(modeContext);
  assert.match(top(), /^ {3}AGENTS +· Ready/);
  await shortcut.handler(modeContext);
  await modeEvent("session_shutdown", { reason: "reload" });
  assert.deepEqual(activeTools, buildTools);
  assert.equal(globalThis.testCeiling, undefined);
  statuses.set("work-mode", "FOREMAN · AUTONOMOUS");
  assert.match(top(), /^ {3}FOREMAN · AUTONOMOUS +· Ready {3}$/);
  assert.notEqual(editor.render(151)[1], neutralFrame);
  statuses.clear();
  await delay(150);
  assert.equal(workingVisible, false);
  assert.equal(ownSession().state, "idle");
  await emit("ui_prompt_start");
  assert.equal(ownSession().state, "waiting");
  await emit("ui_prompt_end");
  assert.equal(ownSession().state, "idle");
  assert.equal(hiddenThinkingLabel, "", "collapsed reasoning has no label");
  assert.equal(footer.render(151).length, 1);
  const cachedRibbon = footer.render(151);
  assert.strictEqual(footer.render(151), cachedRibbon);
  footer.invalidate();
  assert.notStrictEqual(footer.render(151), cachedRibbon);
  assert.deepEqual(footer.render(151), cachedRibbon);
  assert.equal(widgets.size, 0, "no panel edges or padding widgets");
  assert.match(top().trim(), /Ready$/);
  await waitForRibbon(/^ {3}GPT-6\.1 SOL · medium · 24% +$/);
  assert.match(footer.render(151)[0], /\x1b\[2;38;5;11mmedium\x1b\[0m/);
  assert.match(footer.render(151)[0], /\x1b\[2;38;5;11mGPT-6\.1 SOL\x1b\[0m/);
  assert.doesNotMatch(plain(footer.render(151)[0]), /\$|[░█]|ctrl\+l|shift\+tab/);
  assert.doesNotMatch(plain(footer.render(151)[0]), /[◉○] \d+/, "one live session must not show session counters");
  assert.match(footer.render(151)[0], /\x1b\[2;32m24%/);
  assert.equal(plain(editor.render(151)[1]), ` ╭${"─".repeat(147)}╮ `);
  sessionName = "Shell timeout display";
  assert.equal(plain(editor.render(151)[1]), ` ╭${"─".repeat(147)}╮ `);
  assert.match(plain(footer.render(151)[0]), /Shell timeout display {3}$/);
  assert.equal(visibleWidth(footer.render(151)[0]), 151);
  const fleet = { label: "2 agents ↓" };
  events.emit("dotfiles:fleet-footer", fleet);
  assert.equal(fleet.shown, true);
  assert.match(plain(footer.render(151)[0]), /^ {3}GPT-6\.1 SOL · medium · 24% · 2 agents ↓ +Shell timeout display {3}$/);
  assert.doesNotMatch(top(), /agents ↓/);
  assert.match(plain(footer.render(30)[0]), /2 agents ↓/);
  assert.ok(footer.render(30).every(row => visibleWidth(row) <= 30));
  events.emit("dotfiles:fleet-footer", {});
  assert.doesNotMatch(plain(footer.render(151)[0]), /agents ↓/);
  sessionName = "\x1b[31m日本語のセッション\x1b[0m";
  assert.match(plain(footer.render(40)[0]), /日本… {3}$/);
  assert.equal(visibleWidth(footer.render(40)[0]), 40);
  assert.doesNotMatch(footer.render(151)[0], /\x1b\[31m/);
  sessionName = undefined;
  assert.match(plain(footer.render(151)[0]), /^ {3}GPT-6\.1 SOL · medium · 24% +$/);
  assert.equal(plain(editor.render(151).at(-1)), ` ╰${"─".repeat(147)}╯ `);
  assert.ok(top().endsWith("· Ready   "));
  assert.doesNotMatch(top(), /[─╭╮]/);
  assert.equal(visibleWidth(top()), 151);
  assert.ok(!editor.render(151)[0].includes(themes.theme.getBgAnsi("customMessageBg")), "stock editor has no card background");
  assert.doesNotMatch(editor.render(151).join(""), /[┃╻╹▄▀]/);
  editor.setText("hello");
  assert.match(plain(editor.render(151)[2]), /^ │ hello *│ $/);
  assert.equal(editor.handleMouse({ type: "click", button: "left", x: 4, y: 2, width: 151, height: 4 })?.handled, true);
  editor.handleInput("!");
  assert.equal(editor.getText(), "h!ello", "the frame and status row do not offset the mouse cursor");
  editor.setText("hello");
  editor.handleInput("\n");
  assert.equal(editor.getText(), "hello\n", "Ctrl+J must insert a newline");
  editor.handleInput("\x1b[13;2u");
  assert.equal(editor.getText(), "hello\n\n", "CSI-u Shift+Enter must insert a newline");
  editor.setText("");
  queued = true;
  assert.match(top(), /queued/);
  queued = false;

  await start();
  assert.match(top(), wave);
  const waiting = editor.render(151)[0];
  const summary = (type, delta) => emit("provider_stream_event", { data: { type: `response.${type}`, delta } });
  await summary("reasoning_text.delta", "**Private reasoning**");
  await delta("thinking_delta", 10_100, "**Private reasoning**");
  assert.match(top().trim(), /^[·✢*✶✻✽]$/);
  await summary("reasoning_summary_part.added");
  await summary("reasoning_summary_text.delta", "**Checking ");
  assert.doesNotMatch(top(), /Checking/);
  await summary("reasoning_summary_text.delta", "the \x1b[31meditor**\n\nbody");
  assert.match(top(), /[·✢*✶✻✽] Checking the editor {3}$/);
  assert.doesNotMatch(top(), /body|\*\*/);
  assert.equal(visibleWidth(top(24)), 24);
  assert.match(top(24), /[·✢*✶✻✽] Checking.*… {3}$/);
  assert.match(top(12).trim(), /^[·✢*✶✻✽]$/);
  await summary("reasoning_summary_part.added");
  assert.doesNotMatch(top(), /Checking the editor/);
  await summary("reasoning_summary_text.delta", "**Comparing results**");
  assert.match(top(), /Comparing results/);
  const thinking = editor.render(151)[0];
  assert.match(plain(thinking), /[·✢*✶✻✽] Comparing results {3}$/);
  await emit("message_update", { assistantMessageEvent: { type: "thinking_end" } });
  assert.match(top(), wave);
  await delta("text_delta", 10_200);
  const generating = editor.render(151)[0];
  assert.match(plain(generating), wave);
  assert.doesNotMatch(plain(generating), /Comparing results/);
  assert.notEqual(waiting, thinking);
  assert.notEqual(thinking, generating);
  for (const phaseRow of [waiting, thinking, generating]) {
    assert.ok(plain(phaseRow).startsWith("   "));
    assert.doesNotMatch(plain(phaseRow), /[─╭╮]/);
    assert.equal(visibleWidth(phaseRow), 151);
  }
  const frame = top();
  now += 150;
  assert.notEqual(top(), frame, "spinner should animate");
  await delta("text_delta", 11_200);
  await emit("message_end", { message: assistant() });
  assert.doesNotMatch(top(), /tok\/s/);
  assert.equal(entries.length, 0, "model response alone does not finish the turn");
  let measured = await metrics();
  assert.equal(measured.firstOutputSeconds, 0.3);
  assert.equal(measured.firstTextSeconds, 0.4);
  assert.equal(measured.textSeconds, 1);
  assert.equal(measured.outputTokens, 320);
  assert.equal(measured.reasoningTokens, 200);
  assert.equal(measured.textTokens, 120);
  assert.equal(measured.speed, 120);

  await emit("tool_execution_start", { toolCallId: "a", toolName: "bash" });
  now = 11_400;
  await emit("tool_execution_start", { toolCallId: "b", toolName: "read", args: { path: "/private/AGENTS.md" } });
  assert.match(top(), /^ {3}bash, read {2,}[⠁⠂⠄⡀⢀⠠⠐⠈] {3}$/);
  assert.doesNotMatch(top(), /private|Comparing results/);
  now = 11_600;
  await emit("tool_execution_end", { toolCallId: "a", isError: true });
  assert.match(top(), /^ {3}read {2,}[⠁⠂⠄⡀⢀⠠⠐⠈] {3}$/);
  assert.doesNotMatch(top(), /error/);
  assert.doesNotMatch(top(), /bash/);
  now = 11_800;
  await emit("tool_execution_end", { toolCallId: "b", isError: false });
  assert.match(top(), wave);
  assert.doesNotMatch(top(), /Running|Waiting|bash|AGENTS\.md|Comparing results/);
  await emit("message_start", { message: assistant() });
  now = 39_900;
  await emit("message_end", { message: assistant() });
  now = 40_000;
  await emit("agent_settled", { aborted: false });
  assert.match(top().trim(), /Ready$/);
  assert.equal(entries.length, 1);
  const timing = entries[0];
  assert.equal(timing.customType, "turn-timing");
  assert.deepEqual(timing.data, { total: 30_000, wait: 28_200, generation: 1100, bash: 200, tools: 200, parallel: 200, other: 100, aborted: false, speed: 120 });
  const timingRows = expanded => extension.entryRenderers.get("turn-timing")(timing, { expanded }, themes.theme).render(151);
  const renderTiming = expanded => plain(timingRows(expanded).join("\n"));
  assert.match(renderTiming(false), /30,0 s · wait 94% · gen 4% · tools 2% · ≈120,0 tok\/s/);
  assert.equal(timingRows(false).length, 1);
  assert.match(renderTiming(true), /wait 28,2 s · gen 1,1 s · tools 0,6 s · other 0,1 s/);
  assert.match(renderTiming(true), /bash 0,2 s · other tools 0,2 s · overlap 0,2 s/);
  assert.doesNotMatch(top(), /error/);
  assert.equal(ownSession().state, "idle");

  await start();
  now = 39_999;
  await emit("message_end", { message: assistant() });
  await emit("agent_settled", { aborted: false });
  const short = entries.at(-1);
  assert.equal(short.data.total, 29_999);
  assert.equal(short.data.wait, 29_999);
  for (const expanded of [false, true]) {
    assert.equal(extension.entryRenderers.get("turn-timing")(short, { expanded }, themes.theme), undefined);
  }

  for (const test of [
    { name: "single chunk", chunks: [10_200], message: assistant(), reason: /fewer than two/ },
    { name: "same-time chunks", chunks: [10_200, 10_200], message: assistant(), reason: /fewer than two/ },
    { name: "unknown reasoning", chunks: [10_200, 11_200], message: assistant({ usage: { output: 120 } }), reason: /did not separate/ },
    { name: "tool-call output", chunks: [10_200, 11_200], message: assistant({ content: [{ type: "toolCall" }] }), reason: /tool-call/ },
    { name: "failed", chunks: [10_200, 11_200], message: assistant({ stopReason: "error" }), reason: /failed/ },
    { name: "aborted", chunks: [10_200, 11_200], message: assistant({ stopReason: "aborted" }), reason: /aborted/ },
    { name: "no text", chunks: [], message: assistant({ usage: { output: 200, reasoning: 200 } }), reason: /No text/ },
  ]) {
    await start();
    for (const at of test.chunks) await delta("text_delta", at);
    await emit("message_end", { message: test.message });
    assert.doesNotMatch(top(), /tok\/s|≈/, test.name);
    measured = await metrics();
    assert.equal(measured.speed, undefined, test.name);
    assert.match(measured.speedUnavailableReason, test.reason, test.name);
  }
  await start();
  await delta("toolcall_delta", 10_100);
  assert.match(top(), wave);
  await emit("message_end", { message: assistant() });
  assert.match((await metrics()).speedUnavailableReason, /tool-call/);
  await emit("agent_settled", { aborted: true });
  assert.match(top(), /Interrupted/);
  assert.ok(editor.render(151)[0].includes(themes.theme.style("■ Interrupted", { fg: "warning", dim: true })));

  for (const appearance of ["light", "dark"]) {
    themes.setThemeInstance(themes.loadThemeFromPath(join(themesPath, `solarized-${appearance}.json`)));
    assert.ok(!editor.render(151).join("").includes(themes.theme.getBgAnsi("customMessageBg")), `${appearance}: no card background`);
    assert.equal(plain(editor.render(151).at(-1)), ` ╰${"─".repeat(147)}╯ `);
    const palette = JSON.parse(readFileSync(join(themesPath, `solarized-${appearance}.json`), "utf8"));
    const claude = JSON.parse(readFileSync(join(themesPath, `../../claude/themes/solarized-${appearance}.json`))).overrides;
    const report = [
      ["**✔ Готово**", "✔ Готово", "success", "success"], ["✘ **Сбой**", "✘ Сбой", "error", "error"],
      ["! Нашёл", "! Нашёл", "accent", "claude"], ["?", "?", "warning", "warning"], ["» Действие", "» Действие", "mdLink", "suggestion"],
    ];
    const source = report.map(([heading]) => heading + "\n\nОбычный текст.").join("\n\n");
    const renderMessage = transformers => new AssistantMessageComponent(assistant({ content: [{ type: "text", text: source }] }),
      false, themes.getMarkdownTheme(), undefined, 0, transformers).render(80);
    const renderer = extension.markdownTransformer.transformer;
    const rows = renderMessage([renderer]);
    assert.deepEqual(rows.map(plain), renderMessage([]).map(plain), "no frames or text changes");
    for (const [, label, fg, original] of report) {
      assert.equal(palette.vars[palette.colors[fg]], claude[original]);
      assert.ok(rows.some(row => row.includes(themes.theme.style(label, { fg, bold: true }))), `${appearance}: ${label}`);
    }
    const bodyRows = list => list.filter(row => plain(row).includes("Обычный текст."));
    assert.equal(bodyRows(rows).length, report.length);
    assert.deepEqual(bodyRows(rows), bodyRows(renderMessage([])));
    const untouched = "> ✔ Цитата\n\n```sh\n! echo test\n```\n\n- ? Список\n\n![image](a.png)\n\n! Первая строка\nпродолжение.";
    for (const [text, messageType, isStreaming] of [[untouched, "assistant", false], [source, "user", false], [source, "assistant", true]]) {
      assert.equal(renderer(text, { messageType, isStreaming, availableWidth: 80 }), text);
    }
    const userText = "User message sample";
    const userRow = new UserMessageComponent(userText).render(80).find(row => plain(row).includes(userText));
    assert.ok(userRow?.includes(themes.theme.getBgAnsi("userMessageBg")));
    assert.ok(userRow.includes(themes.theme.getFgAnsi("userMessageText")));
    const messageBg = colorToRgb(themes.theme.colors.userMessageBg);
    if (appearance === "light") {
      assert.ok(messageBg.r <= 253 && messageBg.g < 246 && messageBg.b < 227);
    } else {
      const luminance = ({ r, g, b }) => [r, g, b].map(value => value / 255)
        .map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4)
        .reduce((total, value, channel) => total + value * [0.2126, 0.7152, 0.0722][channel], 0);
      const background = luminance(messageBg);
      const foreground = luminance(colorToRgb(themes.theme.colors.userMessageText));
      assert.ok(background > luminance({ r: 10, g: 51, b: 62 }), "dark user card must stand out at least as much as an expanded tool");
      assert.ok((foreground + 0.05) / (background + 0.05) >= 4.5, "dark user text must have at least 4.5:1 contrast");
    }
    const borderGray = palette.vars.borderGray;
    assert.ok(/^#([0-9a-f]{2})\1\1$/i.test(borderGray), `${appearance}: border must be neutral gray, not teal`);
    for (const token of ["border", "borderAccent", "borderMuted"]) assert.equal(palette.colors[token], "borderGray");
    // Reproduce Pi recoloring the custom editor after a reasoning-level change.
    editor.borderColor = text => themes.theme.fg("thinkingMedium", text);
    assert.equal(editor.render(151)[1], ` ${themes.theme.fg("borderMuted", `╭${"─".repeat(147)}╮`)} `);
    assert.equal(editor.render(151).at(-1), ` ${themes.theme.fg("borderMuted", `╰${"─".repeat(147)}╯`)} `);
    await emit("agent_settled", { aborted: false });
    const light = appearance === "light";
    const timingFg = light ? mixColors(themes.theme.colors.borderMuted, rgbColor(255, 249, 234), 0.20, "srgb") : rgbColor(89, 102, 106);
    for (const row of timingRows(true)) {
      assert.ok(row.includes(themes.theme.style(plain(row).trim(), { fg: timingFg, dim: light })));
    }
    assert.ok(editor.render(151)[0].includes(themes.theme.style("· Ready", { fg: light ? rgbColor(152, 161, 106) : "success", dim: !light })));
    assert.doesNotMatch(top(), /tok\/s/);
    const modelColor = light ? themes.theme.getFgAnsi("thinkingText") : "\x1b[2;38;5;11m";
    assert.ok(footer.render(151)[0].includes(modelColor + "GPT-6.1 SOL"));
    sessionName = "Shell timeout display";
    assert.ok(footer.render(151)[0].includes(modelColor + sessionName), `${appearance}: session name matches the model color`);
    events.emit("dotfiles:fleet-footer", { label: "2 agents ↓" });
    assert.ok(footer.render(151)[0].includes(modelColor + "2 agents ↓"), `${appearance}: agent count matches the model color`);
    events.emit("dotfiles:fleet-footer", {});
    sessionName = undefined;
    if (light) assert.doesNotMatch(footer.render(151)[0], /\x1b\[2;/);
    await start();
    const waves = [..."⠂⠒⠲⠴⠤⠠"];
    for (const [type, frames] of [[undefined, waves], ["thinking_delta", [..."·✢*✶✻✽✽✻✶*✢·"]], ["text_delta", waves], ["toolcall_delta", waves]]) {
      if (type) await delta(type, now + 200);
      for (let i = 0; i < frames.length; i++, now += 150) {
        assert.equal(top().trim(), frames[Math.floor(now / 150) % frames.length], `${appearance}: ${type ?? "waiting"}`);
      }
    }
    statuses.delete("work-mode");
    await emit("tool_execution_start", { toolCallId: "one", toolName: "bash" });
    await emit("tool_execution_start", { toolCallId: "two", toolName: "read", args: { path: "/private/input" } });
    await emit("tool_execution_start", { toolCallId: "three", toolName: "read", args: { path: "/private/other" } });
    const rotations = "⠁⠂⠄⡀⢀⠠⠐⠈";
    for (let i = 0; i < rotations.length; i++, now += 150) {
      assert.equal(top().trim().replace(/ +/g, " "), `bash, read ${rotations[Math.floor(now / 150) % rotations.length]}`);
    }
    assert.ok(editor.render(151)[0].includes(themes.theme.fg(light ? "thinkingText" : "dim", "bash, read")));
    assert.equal(visibleWidth(top(32)), 32);
    assert.match(top(32), / [⠁⠂⠄⡀⢀⠠⠐⠈] {3}$/);
    await emit("tool_execution_end", { toolCallId: "three" });
    assert.match(top(), /^ {3}bash, read /);
    await emit("tool_execution_end", { toolCallId: "one" });
    assert.match(top(), /^ {3}read /);
    await emit("tool_execution_end", { toolCallId: "two" });
    await emit("agent_settled", { aborted: false });
    assert.match(top(), /^ +· Ready {3}$/);
    statuses.clear();
  }

  const testProvider = `pi-test-${process.pid}`;
  const providerCache = join(agentDir, "cache", "statusline", testProvider);
  try {
    ctx.model.provider = testProvider;
    await emit("model_select");
    await delay(150);
    assert.ok(existsSync(providerCache), "switching provider must use its own cache directory");
  } finally {
    ctx.model.provider = "openai";
    await emit("model_select");
    rmSync(providerCache, { recursive: true, force: true });
  }
  // Only working runtimes count: two including self, never an idle window.
  await start();
  const peer = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"]);
  const peerFile = join(agentDir, "cache", "statusline", "sessions", `${peer.pid}.json`);
  const reset = Math.floor(new Date().getTime() / 1000) + 3600;
  const getBranch = ctx.sessionManager.getBranch;
  try {
    sessionName = "fix shell timeouts";
    ctx.sessionManager.getBranch = () => [{ type: "message", message: assistant({ usage: { input: 80, cacheRead: 20, cacheWrite: 0 } }) }];
    await emit("after_provider_response", { status: 200, headers: {
      "x-codex-primary-used-percent": "22", "x-codex-primary-window-minutes": "300", "x-codex-primary-reset-at": String(reset),
      "x-codex-secondary-used-percent": "9", "x-codex-secondary-window-minutes": "10080", "x-codex-secondary-reset-at": String(reset + 604800),
    } });
    for (const [state, at, expected] of [
      ["running", wall, /◉ 2/], ["idle", wall, /GPT-6.1 SOL/], ["waiting", wall, /GPT-6.1 SOL/],
      ["running", wall - 90001, /GPT-6.1 SOL/],
    ]) {
      writeFileSync(peerFile, JSON.stringify({ pid: peer.pid, at, state }));
      await emit("thinking_level_select");
      await delay(150);
      const ribbon = plain(footer.render(151)[0]);
      assert.match(ribbon, expected);
      if (state === "running" && at === wall) assert.match(ribbon, /◎ 20% · ◉ 2 · fix shell timeouts · .*22%.* · .*9%/);
      else assert.doesNotMatch(ribbon, /[◉○] \d+/);
    }
    const exited = new Promise(resolve => peer.once("exit", resolve));
    peer.kill();
    await exited;
    writeFileSync(peerFile, JSON.stringify({ pid: peer.pid, at: wall, state: "running" }));
    await emit("thinking_level_select");
    await delay(150);
    assert.doesNotMatch(plain(footer.render(151)[0]), /[◉○] \d+/);
  } finally {
    sessionName = undefined;
    ctx.sessionManager.getBranch = getBranch;
    peer.kill();
    rmSync(peerFile, { force: true });
  }
  await emit("agent_settled", { aborted: false });
  effort = "high";
  await emit("thinking_level_select", { level: effort });
  await delay(100);
  assert.match(plain(footer.render(151)[0]), /GPT-6.1 SOL · high · 24%/);
  assert.match(footer.render(151)[0], /\x1b\[2;33mhigh\x1b\[0m/);
  assert.doesNotMatch(footer.render(151).map(plain).join("\n"), /—/);
  sessionName = "日本語のセッション".repeat(8);
  for (const width of [20, 40, 60, 80, 100, 151]) {
    await waitForRibbon(/22%[\s\S]*9%/, width);
    for (const row of footer.render(width)) assert.ok(visibleWidth(row) <= width, `limits overflow at ${width}`);
    if (width <= 40) assert.ok(footer.render(width).length > 1, "narrow footer must wrap instead of hiding limits");
  }
  await waitForRibbon(/日本語[^\n]*… · .*22%[^\n]*9%(?:[^\n]*\S)? {3}$/);
  sessionName = undefined;
  const providerDir = join(agentDir, "cache", "statusline", ctx.model.provider);
  const ownLimits = JSON.parse(readFileSync(join(providerDir, `limits-${process.pid}.json`), "utf8"));
  assert.equal(ownLimits.five_hour.used_percentage, 22);
  // A newer response wins across projects/models, even when its reset drifts four seconds backward.
  const snapshot = (used, at) => ({
    five_hour: { used_percentage: used, resets_at: reset - 4, observedAt: at },
    seven_day: { used_percentage: 44, resets_at: reset + 604800, observedAt: at },
  });
  writeFileSync(join(providerDir, "limits-999999.json"), JSON.stringify(snapshot(99, wall - 1)));
  wall++;
  writeFileSync(join(providerDir, "limits-999998.json"), JSON.stringify(snapshot(35, wall)));
  const initialSessionId = ctx.sessionManager.getSessionId;
  const initialModel = ctx.model.id;
  ctx.sessionManager.getSessionId = () => "another-project-session";
  ctx.model.id = "another-model";
  await emit("model_select");
  await waitForRibbon(/35%[\s\S]*44%/);
  ctx.model.provider = "another-provider";
  await emit("model_select");
  await waitForRibbon(/^(?![\s\S]*(?:35%|44%|—))(?=[\s\S]*24%)/);
  ctx.model.provider = "openai";
  ctx.model.id = initialModel;
  ctx.sessionManager.getSessionId = initialSessionId;
  await emit("model_select");
  await waitForRibbon(/35%[\s\S]*44%/);
  // Reload/new sessions read the shared observation without another model request.
  await emit("session_shutdown");
  footer.dispose();
  await emit("session_start");
  await waitForRibbon(/35%[\s\S]*44%/);
  assert.doesNotMatch(top(), /tok\/s/);
  await extension.commands.get("statusline-limits").handler("", ctx);
  const diagnostic = JSON.parse(messages.at(-1).content.match(/```json\n([\s\S]*?)\n```/)[1]);
  assert.equal(diagnostic.sharedLimits.five_hour.used_percentage, 35);
  assert.equal(diagnostic.sharedLimits.seven_day.used_percentage, 44);
  const beforeExpiry = wall;
  wall = (reset + 1) * 1000;
  await emit("model_select");
  await waitForRibbon(/^(?![\s\S]*(?:35%|—))[\s\S]*44%/);
  wall = beforeExpiry;
  await emit("model_select");
  await waitForRibbon(/35%[\s\S]*44%/);

  const weekly = {
    "x-codex-primary-used-percent": "0", "x-codex-primary-window-minutes": "10080",
    "x-codex-primary-reset-at": String(reset + 604800),
  };
  const disabled = { ...weekly, "x-codex-secondary-window-minutes": "0", "x-codex-secondary-reset-at": "" };
  // A partial response does not say the old short window is gone.
  wall++;
  const beforeResponse = providerScans;
  await emit("after_provider_response", { status: 200, headers: weekly });
  await waitForRibbon(/35%[\s\S]*0%/);
  assert.equal(providerScans - beforeResponse, 1, "an idle footer refresh must reuse the response's scan");
  // A response queued behind the Go renderer must still see a peer that writes before close.
  await emit("model_select");
  const queuedScans = providerScans;
  await emit("after_provider_response", { status: 200, headers: weekly });
  wall++;
  writeFileSync(join(providerDir, "limits-999996.json"), JSON.stringify({ five_hour: snapshot(48, wall).five_hour }));
  await waitForRibbon(/48%[\s\S]*0%/);
  assert.equal(providerScans - queuedScans, 2, "the queued refresh rereads disk at execution time");
  writeFileSync(join(providerDir, "limits-999997.json"), JSON.stringify({ five_hour: snapshot(99, wall).five_hour }));
  await emit("after_provider_response", { status: 200, headers: disabled });
  const weekOnly = /^(?![\s\S]*(?:35%|99%|—))[\s\S]*0%/;
  await waitForRibbon(weekOnly);
  await emit("after_provider_response", { status: 200, headers: {} });
  await emit("session_shutdown");
  footer.dispose();
  await emit("session_start");
  await waitForRibbon(weekOnly);
  await extension.commands.get("statusline-limits").handler("", ctx);
  const afterDisable = JSON.parse(messages.at(-1).content.match(/```json\n([\s\S]*?)\n```/)[1]);
  assert.equal(afterDisable.sharedLimits.five_hour, undefined);
  assert.equal(afterDisable.sharedLimits.seven_day.used_percentage, 0);
  wall++;
  await emit("after_provider_response", { status: 200, headers: {
    ...weekly, "x-codex-secondary-used-percent": "27", "x-codex-secondary-window-minutes": "300",
    "x-codex-secondary-reset-at": String(reset),
  } });
  await waitForRibbon(/27%[\s\S]*0%/);

  const streamLimits = async (primary, secondary, metered_limit_name = "codex") => {
    wall++;
    await emit("provider_stream_event", {
      provider: "litellm-ws", api: "openai-codex-responses", model: "gpt-6.2-sol",
      data: { type: "codex.rate_limits", metered_limit_name, rate_limits: { primary, secondary } },
    });
  };
  const weeklyWindow = { window_minutes: 10080, used_percent: 13, reset_at: reset + 604800 };
  const shortWindow = { window_minutes: 300, used_percent: 37, reset_at: reset };
  ctx.model.provider = "litellm-ws";
  await emit("model_select");
  await streamLimits(weeklyWindow, shortWindow);
  await waitForRibbon(/37%[\s\S]*13%/);
  await streamLimits({ ...weeklyWindow, used_percent: 99 }, null, "other-limit");
  await waitForRibbon(/37%[\s\S]*13%/);
  await streamLimits({ ...weeklyWindow, used_percent: "98" }, null);
  await waitForRibbon(/37%[\s\S]*13%/);
  await streamLimits(weeklyWindow, undefined);
  await waitForRibbon(/37%[\s\S]*13%/);
  await streamLimits({ ...weeklyWindow, used_percent: 14 }, null);
  await waitForRibbon(/^(?![\s\S]*(?:37%|98%|99%))[\s\S]*14%/);
  await extension.commands.get("statusline-limits").handler("", ctx);
  const streamDiagnostic = JSON.parse(messages.at(-1).content.match(/```json\n([\s\S]*?)\n```/)[1]);
  assert.equal(streamDiagnostic.lastResponse.source, "codex.rate_limits");
  assert.equal(streamDiagnostic.lastResponse.provider, "litellm-ws");
  assert.equal(streamDiagnostic.sharedLimits.five_hour, undefined);
  assert.equal(streamDiagnostic.sharedLimits.seven_day.used_percentage, 14);
  await streamLimits(weeklyWindow, shortWindow);
  await waitForRibbon(/37%[\s\S]*13%/);
  ctx.model.provider = "openai";
  await emit("model_select");
  await waitForRibbon(/27%[\s\S]*0%/);
  for (const width of [1, 2, 3, 4, 5, 6, 8, 12, 40, 60, 80, 85, 100, 151, 200]) {
    const lines = editor.render(width);
    assert.ok(visibleWidth(lines[0]) <= width, `top overflow at ${width}`);
    assert.ok(visibleWidth(lines.at(-1)) <= width, `bottom overflow at ${width}`);
    for (const row of footer.render(width)) assert.ok(visibleWidth(row) <= width, `footer overflow at ${width}`);
  }
  assert.doesNotMatch(top(60), /ctrl\+l/);
  statuses.set("test", "日本語 😀");
  assert.match(top(), /日本語 😀/);
  editor.setText(Array.from({ length: 30 }, (_, i) => `line ${i}`).join("\n"));
  assert.match(top(), /↑ \d+ more/);
  await extension.commands.get("statusline").handler("", ctx);
  assert.equal(editor, undefined);
  assert.equal(footer, undefined);
  assert.equal(workingVisible, true);
  const disabledFleet = { label: "2 agents ↓" };
  events.emit("dotfiles:fleet-footer", disabledFleet);
  assert.equal(disabledFleet.shown, undefined, "a disposed footer cannot claim the native summary");
  assert.equal(widgets.has("statusline-spacing"), false);
  assert.equal(widgets.has("statusline-half-edge"), false);
  await extension.commands.get("statusline").handler("", ctx);
  assert.ok(editor);
  assert.equal(workingVisible, false);
  editor.setText("");
  footer.render(100);
  await delay(150);
  const stockEditor = new CustomEditor(tui, themes.getEditorTheme(), keybindings);
  const stockFooter = new FooterComponent({
    state: { model: { ...ctx.model, reasoning: true }, thinkingLevel: effort },
    sessionManager: { getCwd: () => "/tmp/project", getSessionName: () => undefined },
    modelRuntime: { isUsingSubscription: () => true },
  }, { getGitBranch: () => "main", getAvailableProviderCount: () => 1, getExtensionStatuses: () => new Map() });
  stockFooter.getSessionStats = () => ({
    usageTotals: { input: 12000, output: 320, cacheRead: 0, cacheWrite: 0, cost: 0 },
    contextUsage: { percent: 24, contextWindow: 272000 },
  });
  statuses.clear();
  console.log("STOCK PI (fixture data):\n" + [...stockEditor.render(100), ...stockFooter.render(100)].map(plain).join("\n"));
  console.log("CUSTOM PI (same context):\n" + [...editor.render(100), ...footer.render(100)].map(plain).join("\n"));
  console.log("PASS: real Pi loader/editor/renderer; shared provider limits across projects/models/reload, latest-window selection and expiry, reset jitter, active-only session threshold, muted timing and throughput, phase spinners, narrow widths and cleanup");
} finally {
  await emit("session_shutdown");
  assert.equal(existsSync(join(agentDir, "cache", "statusline", "sessions", `${process.pid}.json`)), false);
  footer?.dispose();
  mock.restoreAll();
  syncBuiltinESMExports();
  if (originalHome === undefined) delete process.env.HOME;
  else process.env.HOME = originalHome;
  rmSync(testHome, { recursive: true, force: true });
}
