import assert from "node:assert/strict";
import { stripVTControlCharacters } from "node:util";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
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
symlinkSync(realpathSync(join(installedAgentDir, "bin", "solarized-statusline")), join(agentDir, "bin", "solarized-statusline"));
process.env.HOME = testHome;
const extensionPath = fileURLToPath(new URL("../extensions/solarized-status.ts", import.meta.url));
const themesPath = fileURLToPath(new URL("../themes/", import.meta.url));
const load = path => import(pathToFileURL(join(modules, path)).href);
const { loadExtensions } = await load("@earendil-works/pi-coding-agent/dist/core/extensions/loader.js");
const { CustomEditor } = await load("@earendil-works/pi-coding-agent/dist/modes/interactive/components/custom-editor.js");
const { FooterComponent } = await load("@earendil-works/pi-coding-agent/dist/modes/interactive/components/footer.js");
const { KeybindingsManager } = await load("@earendil-works/pi-coding-agent/dist/core/keybindings.js");
const themes = await load("@earendil-works/pi-coding-agent/dist/modes/interactive/theme/theme.js");
const { Markdown, colorToRgb, mixColors, rgbColor, visibleWidth } = await load("@earendil-works/pi-tui/dist/index.js");
themes.initTheme("dark", false);
let now = 10_000;
let wall = 1_000_000;
mock.method(performance, "now", () => now);
mock.method(Date, "now", () => wall);
const loaded = await loadExtensions([extensionPath], "/tmp");
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
let footer, editor, hiddenThinkingLabel, queued = false, workingVisible = true;
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
async function start() {
  now = 10_000;
  await emit("agent_start");
  assert.equal(ownSession().state, "running");
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
  modes.runtime.getAllTools = () => [...buildTools, "grep", "mcp__knowledge__read", "mcp__context7__resolve_library_id", "mcp__context7__query_docs"].map(name => ({ name }));
  modes.runtime.setActiveTools = names => { activeTools = names; };
  const modeContext = { ...ctx, isIdle: () => idle, ui: { ...ctx.ui,
    setStatus: (key, value) => statuses.set(key, value), notify: text => notifications.push(text),
    select: async (_title, options) => { menu = options; return choice; },
  } };
  const modeEvent = (type, data = {}) => mode.handlers.get(type)[0]({ type, ...data }, modeContext);
  const shortcut = mode.shortcuts.get("shift+tab");
  activeTools = [...buildTools, "subagent"];
  await modeEvent("session_start");
  assert.deepEqual(activeTools, buildTools, "resumed tools cannot enable Agents by default");
  assert.match(top(), /^ {3}EXECUTE · PAIR +· Ready {3}$/);
  const sections = {};
  await modeEvent("before_agent_start", { systemPromptOptions: { sections } });
  assert.match(sections.work_mode, /Pair.*wait for the user/);
  assert.doesNotMatch(sections.work_mode, /Ask only when stuck/);
  assert.doesNotMatch(sections.work_mode, /subagent/);
  const coral = rgbColor(217, 126, 116);
  assert.ok(editor.render(151)[0].includes(themes.theme.style("EXECUTE", { fg: coral })));
  const pairColor = mixColors(themes.theme.colors.muted, themes.theme.colors.dim, 0.65, "srgb");
  assert.ok(editor.render(151)[0].includes(themes.theme.style("PAIR", { fg: pairColor })));
  const profileShortcut = mode.shortcuts.get("alt+r");
  const agentsShortcut = mode.shortcuts.get("alt+g");
  await mode.commands.get("execute").handler("", modeContext);
  assert.deepEqual(menu, ["Pair (active)", "Autonomous"]);
  menu = undefined;
  await profileShortcut.handler(modeContext);
  assert.equal(menu, undefined, "cycling does not open the selector");
  assert.match(top(), /EXECUTE · AUTONOMOUS/);
  await modeEvent("before_agent_start", { systemPromptOptions: { sections } });
  assert.match(sections.work_mode, /Autonomous.*verification/);
  assert.match(sections.work_mode, /Ask only when stuck: the same failure twice with no new hypothesis/);
  assert.ok(editor.render(151)[0].includes(themes.theme.style("AUTONOMOUS", { fg: coral })));
  const executeFrame = editor.render(151)[1];
  assert.doesNotMatch(plain(editor.render(151)[2]), /EXECUTE/);
  assert.doesNotMatch(editor.render(151)[2], /\x1b\[48;/);
  await shortcut.handler(modeContext);
  assert.notEqual(editor.render(151)[1], executeFrame);
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
  const task = { task: "Find the relevant source" };
  const runSubagent = () => subagent.execute("test", task, undefined, undefined, { ...modeContext, cwd: testHome });
  await assert.rejects(runSubagent, /Enable Agents in Execute/);
  choice = "Pair";
  await mode.commands.get("execute").handler("", modeContext);
  assert.deepEqual(menu, ["Autonomous (active)", "Pair"]);
  await mode.commands.get("agents").handler("", modeContext);
  assert.match(notifications.pop(), /Agents enabled for Execute/);
  await assert.rejects(runSubagent, /Enable Agents in Execute/);
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
  assert.match(top(), /^ {3}EXECUTE · PAIR · AGENTS/);
  await modeEvent("before_agent_start", { systemPromptOptions: { sections } });
  assert.match(sections.work_mode, /Pair.*may use the subagent tool/);
  assert.match(sections.work_mode, /Every scope, once: a subagent reviews the diff/);
  assert.doesNotMatch(sections.work_mode, /on a cheaper model/);
  assert.deepEqual(activeTools, [...buildTools, "subagent"]);
  const originalPath = process.env.PATH;
  try {
    writeFileSync(join(testHome, "pi"), '#!/bin/sh\nprintf "%s\\n" "$PWD" "$@"\n', { mode: 0o755 });
    process.env.PATH = `${testHome}:${originalPath}`;
    const report = (await runSubagent()).content[0].text;
    assert.ok(report.startsWith(realpathSync(testHome) + "\n"));
    assert.match(report, /--no-session\n--no-extensions\n--no-mcp\n/);
    assert.match(report, /--tools\nread,grep,find,ls\n--model\nopenai\/gpt-6\.1-sol\n--thinking\nlow\n/);
    assert.ok(report.endsWith("--\nDelegated task:\nFind the relevant source"));
  } finally {
    process.env.PATH = originalPath;
  }
  idle = false;
  await agentsShortcut.handler(modeContext);
  assert.match(top(), /EXECUTE · PAIR · AGENTS/);
  assert.equal(notifications.length, 2);
  idle = true;
  await profileShortcut.handler(modeContext);
  assert.match(top(), /EXECUTE · AUTONOMOUS · AGENTS/);
  assert.deepEqual(activeTools, [...buildTools, "subagent"]);
  await agentsShortcut.handler(modeContext);
  assert.doesNotMatch(top(), /AGENTS/);
  assert.deepEqual(activeTools, buildTools);
  activeTools = [...buildTools, "subagent"];
  await modeEvent("session_tree");
  assert.deepEqual(activeTools, buildTools, "switching branches cannot re-enable Agents");
  await assert.rejects(runSubagent, /Enable Agents in Execute/);
  await modeEvent("before_agent_start", { systemPromptOptions: { sections } });
  assert.doesNotMatch(sections.work_mode, /subagent/);
  await profileShortcut.handler(modeContext);
  assert.match(top(), /EXECUTE · PAIR/);
  await agentsShortcut.handler(modeContext);
  assert.match(top(), /EXECUTE · PAIR · AGENTS/);
  await shortcut.handler(modeContext);
  await modeEvent("session_shutdown", { reason: "reload" });
  assert.deepEqual(activeTools, buildTools);
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
  assert.equal(widgets.size, 0, "no panel edges or padding widgets");
  assert.match(top().trim(), /Ready$/);
  await waitForRibbon(/^ {3}GPT-6\.1 SOL · medium · 24%[^\n]*\S {3}$/);
  const insetRibbon = plain(footer.render(151)[0]);
  assert.match(insetRibbon, /^ {3}GPT-6\.1 SOL/);
  assert.match(insetRibbon, /\S {3}$/, "footer limits align with the right inset of the editor status row");
  assert.match(footer.render(151)[0], /\x1b\[2;38;5;11mmedium\x1b\[0m/);
  assert.match(footer.render(151)[0], /\x1b\[2;38;5;11mGPT-6\.1 SOL\x1b\[0m/);
  assert.doesNotMatch(plain(footer.render(151)[0]), /\$|[░█]|ctrl\+l|shift\+tab/);
  assert.doesNotMatch(plain(footer.render(151)[0]), /[◉○] \d+/, "one live session must not show session counters");
  assert.match(footer.render(151)[0], /\x1b\[2;32m24%/);
  assert.equal(plain(editor.render(151)[1]), ` ╭${"─".repeat(147)}╮ `);
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
  assert.match(top().trim(), /Waiting$/);
  const waiting = editor.render(151)[0];
  await delta("thinking_delta", 10_100);
  const thinking = editor.render(151)[0];
  assert.match(plain(thinking), /Thinking {3}$/);
  await delta("text_delta", 10_200);
  const generating = editor.render(151)[0];
  assert.match(plain(generating), /Generating/);
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
  await emit("tool_execution_start", { toolCallId: "b", toolName: "read" });
  assert.match(top(), /bash, read.*Running {3}$/);
  now = 11_600;
  await emit("tool_execution_end", { toolCallId: "a", isError: true });
  assert.match(top(), /read.*Running {3}$/);
  assert.doesNotMatch(top(), /error/);
  assert.doesNotMatch(top(), /bash/);
  now = 11_800;
  await emit("tool_execution_end", { toolCallId: "b", isError: false });
  assert.match(top(), /Active/);
  assert.doesNotMatch(top(), /Running|Waiting|bash|read/);
  now = 11_900;
  await emit("agent_settled", { aborted: false });
  assert.match(top().trim(), /Ready$/);
  assert.equal(entries.length, 1);
  const timing = entries[0];
  assert.equal(timing.customType, "turn-timing");
  assert.deepEqual(timing.data, { total: 1900, wait: 100, generation: 1100, bash: 200, tools: 200, parallel: 200, other: 100, aborted: false, speed: 120 });
  const timingRows = expanded => extension.entryRenderers.get("turn-timing")(timing, { expanded }, themes.theme).render(151);
  const renderTiming = expanded => plain(timingRows(expanded).join("\n"));
  assert.match(renderTiming(false), /1,9 s · wait 5% · gen 58% · tools 32% · other 5% · ≈120,0 tok\/s/);
  assert.equal(timingRows(false).length, 1);
  assert.match(renderTiming(true), /wait 0,1 s · gen 1,1 s · tools 0,6 s · other 0,1 s/);
  assert.match(renderTiming(true), /bash 0,2 s · other tools 0,2 s · overlap 0,2 s/);
  assert.doesNotMatch(top(), /error/);
  assert.equal(ownSession().state, "idle");

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
  assert.match(top(), /Preparing/);
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
    const messageBg = colorToRgb(themes.theme.colors.userMessageBg);
    const terminalBg = appearance === "light" ? { r: 253, g: 246, b: 227 } : { r: 0, g: 43, b: 54 };
    assert.ok(messageBg.r <= terminalBg.r && messageBg.g < terminalBg.g && messageBg.b < terminalBg.b);
    const borderGray = palette.vars.borderGray;
    assert.ok(/^#([0-9a-f]{2})\1\1$/i.test(borderGray), `${appearance}: border must be neutral gray, not teal`);
    for (const token of ["border", "borderAccent", "borderMuted"]) assert.equal(palette.colors[token], "borderGray");
    // Reproduce Pi recoloring the custom editor after a reasoning-level change.
    editor.borderColor = text => themes.theme.fg("thinkingMedium", text);
    assert.equal(editor.render(151)[1], ` ${themes.theme.fg("borderMuted", `╭${"─".repeat(147)}╮`)} `);
    assert.equal(editor.render(151).at(-1), ` ${themes.theme.fg("borderMuted", `╰${"─".repeat(147)}╯`)} `);
    await emit("agent_settled", { aborted: false });
    const light = appearance === "light";
    const timingFg = light ? mixColors(themes.theme.colors.borderMuted, rgbColor(255, 249, 234), 0.27, "srgb") : "borderMuted";
    for (const row of timingRows(true)) {
      assert.ok(row.includes(themes.theme.style(plain(row).trim(), { fg: timingFg, dim: true })));
    }
    assert.ok(editor.render(151)[0].includes(themes.theme.style("· Ready", { fg: light ? rgbColor(152, 161, 106) : "success", dim: !light })));
    assert.doesNotMatch(top(), /tok\/s/);
    if (light) {
      assert.ok(footer.render(151)[0].includes(themes.theme.getFgAnsi("thinkingText") + "GPT-6.1 SOL"));
      assert.doesNotMatch(footer.render(151)[0], /\x1b\[2;/);
    }
    await start();
    const phaseColors = [
      { type: undefined, label: "Waiting", frames: ["⠂", "⠒", "⠲", "⠴", "⠤", "⠠"], token: "thinkingLow" },
      { type: "thinking_delta", label: "Thinking", frames: ["·", "✢", "*", "✶", "✻", "✽", "✽", "✻", "✶", "*", "✢", "·"], token: "thinkingText" },
      { type: "text_delta", label: "Generating", frames: ["⠖", "⠲", "⢲", "⢰", "⣰", "⣠", "⣄", "⣆", "⡆", "⡖"], token: "thinkingMedium" },
      { type: "toolcall_delta", label: "Preparing", frames: ["·", "•", "●", "•"], token: "warning" },
    ];
    for (const phase of phaseColors) {
      if (phase.type) await delta(phase.type, now + 200);
      const frame = phase.frames[Math.floor(now / 150) % phase.frames.length];
      const color = themes.theme.colors[phase.token];
      const fg = light && phase.label !== "Thinking" ? mixColors(color, rgbColor(253, 246, 227), 0.23, "srgb") : color;
      const expected = themes.theme.style(`${frame} ${phase.label}`, { fg, dim: !light });
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
  // Only working runtimes count: two including self, never an idle window.
  await start();
  const peer = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"]);
  const peerFile = join(agentDir, "cache", "statusline", "sessions", `${peer.pid}.json`);
  try {
    for (const [state, at, expected] of [
      ["running", wall, /◉ 2/], ["idle", wall, /GPT-6.1 SOL/], ["waiting", wall, /GPT-6.1 SOL/],
      ["running", wall - 90001, /GPT-6.1 SOL/],
    ]) {
      writeFileSync(peerFile, JSON.stringify({ pid: peer.pid, at, state }));
      await emit("thinking_level_select");
      await delay(150);
      const ribbon = plain(footer.render(151)[0]);
      assert.match(ribbon, expected);
      if (state !== "running" || at < wall) assert.doesNotMatch(ribbon, /[◉○] \d+/);
    }
    const exited = new Promise(resolve => peer.once("exit", resolve));
    peer.kill();
    await exited;
    writeFileSync(peerFile, JSON.stringify({ pid: peer.pid, at: wall, state: "running" }));
    await emit("thinking_level_select");
    await delay(150);
    assert.doesNotMatch(plain(footer.render(151)[0]), /[◉○] \d+/);
  } finally {
    peer.kill();
    rmSync(peerFile, { force: true });
  }
  await emit("agent_settled", { aborted: false });
  effort = "high";
  await emit("thinking_level_select", { level: effort });
  await delay(100);
  assert.match(plain(footer.render(151)[0]), /GPT-6.1 SOL · high · 24%/);
  assert.match(footer.render(151)[0], /\x1b\[2;33mhigh\x1b\[0m/);
  assert.match(footer.render(151).map(plain).join("\n"), /—.*—/);
  const reset = Math.floor(new Date().getTime() / 1000) + 3600;
  await emit("after_provider_response", { status: 200, headers: {
    "x-codex-primary-used-percent": "22", "x-codex-primary-window-minutes": "300", "x-codex-primary-reset-at": String(reset),
    "x-codex-secondary-used-percent": "9", "x-codex-secondary-window-minutes": "10080", "x-codex-secondary-reset-at": String(reset + 604800),
  } });
  for (const width of [20, 40, 60, 80, 100, 151]) {
    await waitForRibbon(/22%[\s\S]*9%/, width);
    for (const row of footer.render(width)) assert.ok(visibleWidth(row) <= width, `limits overflow at ${width}`);
    if (width <= 40) assert.ok(footer.render(width).length > 1, "narrow footer must wrap instead of hiding limits");
  }
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
  await waitForRibbon(/—[\s\S]*—/);
  assert.doesNotMatch(footer.render(151).map(plain).join("\n"), /35%|44%/);
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
  await waitForRibbon(/—[\s\S]*44%/);
  wall = beforeExpiry;
  await emit("model_select");
  await waitForRibbon(/35%[\s\S]*44%/);
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
  if (originalHome === undefined) delete process.env.HOME;
  else process.env.HOME = originalHome;
  rmSync(testHome, { recursive: true, force: true });
}
