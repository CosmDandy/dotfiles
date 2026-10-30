import assert from "node:assert/strict";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { setTimeout as delay } from "node:timers/promises";
import { mock } from "node:test";

const agentDir = join(homedir(), ".pi", "agent");
const modules = process.env.PI_TEST_MODULES ?? join(agentDir, "install", "releases",
  readFileSync(join(agentDir, "install", "current-version"), "utf8").trim(), "node_modules");
const extensionPath = fileURLToPath(new URL("../extensions/solarized-status.ts", import.meta.url));
const themesPath = fileURLToPath(new URL("../themes/", import.meta.url));
const load = path => import(pathToFileURL(join(modules, path)).href);
const { loadExtensions } = await load("@earendil-works/pi-coding-agent/dist/core/extensions/loader.js");
const { KeybindingsManager } = await load("@earendil-works/pi-coding-agent/dist/core/keybindings.js");
const themes = await load("@earendil-works/pi-coding-agent/dist/modes/interactive/theme/theme.js");
const { visibleWidth } = await load("@earendil-works/pi-tui/dist/index.js");
themes.initTheme("dark", false);
let now = 10_000;
const wall = 1_000_000;
mock.method(performance, "now", () => now);
mock.method(Date, "now", () => wall);
const loaded = await loadExtensions([extensionPath], "/tmp");
assert.deepEqual(loaded.errors, []);
let effort = "medium";
loaded.runtime.getThinkingLevel = () => effort;
const messages = [];
loaded.runtime.sendMessage = message => messages.push(message);
const extension = loaded.extensions[0];
let footer, editor, queued = false, workingVisible = true;
const tui = { requestRender() {}, terminal: { rows: 42, columns: 151 } };
const statuses = new Map();
const widgets = new Map();
const keybindings = new KeybindingsManager();
const ctx = {
  mode: "tui", model: { provider: "openai", id: "gpt-6.1-sol", name: "GPT-6.1 SOL", contextWindow: 272000 },
  sessionManager: { getSessionId: () => "frame-test", getBranch: () => [] },
  getContextUsage: () => ({ percent: 24, contextWindow: 272000 }),
  hasPendingMessages: () => queued,
  ui: {
    theme: themes.theme,
    setWidget(name, content) { if (content === undefined) widgets.delete(name); else widgets.set(name, content); },
    setWorkingVisible(value) { workingVisible = value; },
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
const plain = text => text.replace(/\x1b\[[0-9;]*m/g, "");
const top = (width = 151) => plain(editor.render(width)[0]);
const assistant = (overrides = {}) => ({
  role: "assistant", timestamp: wall, durationMs: 1600,
  content: [{ type: "text", text: "hello world" }],
  usage: { output: 320, reasoning: 200 }, stopReason: "stop", ...overrides,
});
async function start() {
  now = 10_000;
  await emit("agent_start");
  assert.match(top(), /Active/);
  assert.doesNotMatch(top(), /Waiting/);
  await emit("before_provider_request");
  assert.match(top(), /Waiting/);
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
  await delay(150);
  assert.equal(workingVisible, false);
  assert.equal(footer.render(151).length, 2);
  assert.equal(widgets.has("statusline-spacing"), false);
  const upperEdge = () => widgets.get("statusline-half-edge")().render(151)[0];
  assert.equal(plain(upperEdge()), " ╻" + "▄".repeat(148) + " ");
  assert.match(top(), /Ready/);
  assert.doesNotMatch(top(), /ctrl\+l|shift\+tab/);
  assert.match(top(), /— s · — tok\/s/);
  editor.render(151);
  await delay(100);
  assert.match(plain(editor.render(151).at(-1)), /GPT-6.1 SOL.*medium/);
  assert.doesNotMatch(plain(editor.render(151).at(-1)), /24%|\$0\.00/);
  assert.match(plain(footer.render(151)[1]), /ctrl\+l model.*shift\+tab effort.*24%.*\$0\.00/);
  assert.doesNotMatch(plain(footer.render(151)[1]), /GPT-6.1 SOL/);
  const padding = footer.render(151)[0];
  assert.equal(plain(padding), " ╹" + "▀".repeat(148) + " ");
  assert.ok(padding.startsWith("\x1b[49m"), "half-cell edge must use the terminal background");
  assert.ok(!padding.includes(themes.theme.getBgAnsi("customMessageBg")), "edge must not paint a full background row");
  assert.ok(padding.includes(themes.theme.style("▀".repeat(148), { fg: themes.theme.colors.customMessageBg })), "upper half must match the panel color");
  assert.ok(!footer.render(151)[1].includes(themes.theme.getBgAnsi("customMessageBg")), "general information must be outside the card background");
  assert.match(editor.render(151).at(-1), /\x1b\[34mmedium/);
  for (const border of [top(), plain(editor.render(151).at(-1))]) {
    assert.ok(border.startsWith(" ┃ ") && border.endsWith("   "), border);
    assert.equal(visibleWidth(border), 151);
  }
  assert.doesNotMatch(top(), /─/);
  assert.ok(editor.render(151)[0].includes(themes.theme.getBgAnsi("customMessageBg")), "card must retain its panel background");
  assert.ok(editor.render(151)[0].startsWith("\x1b[49m " + themes.theme.style("┃", { fg: themes.theme.colors.dim, dim: true }) + themes.theme.getBgAnsi("customMessageBg")), "stripe must sit outside the panel background and join centered half-caps");
  editor.setText("hello");
  assert.ok(plain(editor.render(151)[1]).startsWith(" ┃ hello"));
  editor.handleInput("\n");
  assert.equal(editor.getText(), "hello\n", "Ctrl+J must insert a newline");
  editor.handleInput("\x1b[13;2u");
  assert.equal(editor.getText(), "hello\n\n", "CSI-u Shift+Enter must insert a newline");
  editor.setText("");
  queued = true;
  assert.match(top(), /queued/);
  queued = false;

  await start();
  assert.match(top(), /Waiting.*0,2 s/);
  const waiting = editor.render(151)[0];
  await delta("thinking_delta", 10_100);
  const thinking = editor.render(151)[0];
  assert.match(plain(thinking), /Thinking/);
  await delta("text_delta", 10_200);
  const generating = editor.render(151)[0];
  assert.match(plain(generating), /Generating/);
  assert.notEqual(waiting, thinking);
  assert.notEqual(thinking, generating);
  for (const phaseRow of [waiting, thinking, generating]) {
    assert.ok(plain(phaseRow).startsWith(" ┃ "));
    assert.equal(visibleWidth(phaseRow), 151);
  }
  const frame = top();
  now += 150;
  assert.notEqual(top(), frame, "spinner should animate");
  await delta("text_delta", 11_200);
  await emit("message_end", { message: assistant() });
  assert.match(top(), /1,6 s · ≈120,0 tok\/s/);
  let measured = await metrics();
  assert.equal(measured.firstOutputSeconds, 0.3);
  assert.equal(measured.firstTextSeconds, 0.4);
  assert.equal(measured.textSeconds, 1);
  assert.equal(measured.outputTokens, 320);
  assert.equal(measured.reasoningTokens, 200);
  assert.equal(measured.textTokens, 120);
  assert.equal(measured.speed, 120);

  await emit("tool_execution_start", { toolCallId: "a", toolName: "bash" });
  await emit("tool_execution_start", { toolCallId: "b", toolName: "read" });
  assert.match(top(), /Running.*bash, read/);
  await emit("tool_execution_end", { toolCallId: "a", isError: true });
  assert.match(top(), /Running.*read.*error/);
  assert.doesNotMatch(top(), /bash/);
  await emit("tool_execution_end", { toolCallId: "b", isError: false });
  assert.match(top(), /Active/);
  assert.doesNotMatch(top(), /Running|Waiting|bash|read/);
  await emit("agent_settled", { aborted: false });
  assert.match(top(), /Ready.*error.*120,0 tok\/s/);

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
    assert.match(top(), /— tok\/s/, test.name);
    assert.doesNotMatch(top(), /≈/, test.name);
    measured = await metrics();
    assert.equal(measured.speed, undefined, test.name);
    assert.match(measured.speedUnavailableReason, test.reason, test.name);
  }
  await start();
  await delta("toolcall_delta", 10_100);
  assert.match(top(), /Preparing/);
  await emit("message_end", { message: assistant() });
  assert.match((await metrics()).speedUnavailableReason, /tool-call/);
  await emit("agent_settled", { aborted: true });
  assert.match(top(), /Interrupted/);

  for (const appearance of ["light", "dark"]) {
    themes.setThemeInstance(themes.loadThemeFromPath(join(themesPath, `solarized-${appearance}.json`)));
    const edge = footer.render(151)[0];
    assert.ok(edge.includes(themes.theme.style("▀".repeat(148), { fg: themes.theme.colors.customMessageBg })), `${appearance}: edge must match panel color`);
    assert.ok(!edge.includes(themes.theme.getBgAnsi("customMessageBg")), `${appearance}: edge must not fill a whole row`);
    assert.ok(upperEdge().includes(themes.theme.style("▄".repeat(148), { fg: themes.theme.colors.customMessageBg })), `${appearance}: upper edge must match panel color`);
    await start();
    const phaseColors = [
      { type: undefined, label: "Waiting", frames: ["⠂", "⠒", "⠲", "⠴", "⠤", "⠠"], token: "thinkingLow" },
      { type: "thinking_delta", label: "Thinking", frames: ["·", "✢", "*", "✶", "✻", "✽", "✽", "✻", "✶", "*", "✢", "·"], token: "thinkingHigh" },
      { type: "text_delta", label: "Generating", frames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"], token: "thinkingMedium" },
      { type: "toolcall_delta", label: "Preparing", frames: ["·", "•", "●", "•"], token: "warning" },
    ];
    for (const phase of phaseColors) {
      if (phase.type) await delta(phase.type, now + 200);
      const frame = phase.frames[Math.floor(now / 150) % phase.frames.length];
      const expected = themes.theme.style(`${frame} ${phase.label}`, { fg: themes.theme.colors[phase.token], dim: true });
      assert.ok(editor.render(151)[0].includes(expected), `${appearance}: ${phase.label} should use its dimmed theme color`);
    }
    await emit("agent_settled", { aborted: false });
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
  effort = "high";
  await emit("thinking_level_select", { level: effort });
  await delay(100);
  assert.match(editor.render(151).at(-1), /\x1b\[33mhigh/);
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
  assert.equal(widgets.has("statusline-spacing"), false);
  assert.equal(widgets.has("statusline-half-edge"), false);
  await extension.commands.get("statusline").handler("", ctx);
  assert.ok(editor);
  assert.equal(workingVisible, false);
  console.log("PASS: real loader/editor/renderer; symmetric spacing, text-only throughput, latency diagnostics, phase spinners, queue/errors, parallel tools, narrow widths, Unicode, scrolling, toggle cleanup");
} finally {
  footer?.dispose();
  mock.restoreAll();
}
