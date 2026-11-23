import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { pathToFileURL } from 'node:url';
import { stripVTControlCharacters } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';

const createSession = directory => {
  const timestamp = new Date().toISOString();
  const stamp = Date.now();
  const usage = { input: 1, output: 1, cacheRead: 0, cacheWrite: 0, totalTokens: 2,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
  const text = text => ({ type: 'text', text });
  const messages = [{ role: 'user', content: [text('Saved prompt')] },
    { role: 'bashExecution', command: 'printf shell-fixture', output: 'recorded-shell-output',
      exitCode: 0, cancelled: false, truncated: false }];
  for (let i = 1; i <= 11; i++) {
    const toolCallId = `call-${i}`;
    messages.push({ role: 'user', content: [text(`Between calls: ${i}`)] });
    messages.push({ role: 'assistant', api: 'openai-responses', provider: 'openai', model: 'gpt-5',
      stopReason: 'toolUse', usage, content: [
        { type: 'toolCall', id: toolCallId, name: 'bash', arguments: { command: `printf fixture-${i}.txt` } }] });
    messages.push({ role: 'toolResult', toolCallId, toolName: 'bash', isError: false,
      content: [text(i === 9 ? Array.from({ length: 18 }, (_, j) => `selected-output-${j + 1}`).join('\n') : `output-${i}`)] });
  }
  messages.push({ role: 'assistant', api: 'openai-responses', provider: 'openai', model: 'gpt-5', stopReason: 'stop', usage,
    content: [text('Answer: alpha_beta cat-dog wide café 👩‍💻.\n\nSecond paragraph.')] });
  const id = i => (i + 1).toString(16).padStart(8, '0');
  const file = join(directory, 'session.jsonl');
  const entries = [{ type: 'session', version: 3, id: 'vim-fixture', timestamp, cwd: directory },
    ...messages.map((message, i) => ({ type: 'message', id: id(i), parentId: i === 0 ? null : id(i - 1),
      timestamp, message: { ...message, timestamp: stamp } }))];
  writeFileSync(file, entries.map(entry => JSON.stringify(entry)).join('\n') + '\n');
  return file;
};

function load(path) {
  assert.ok(process.env.PI_TEST_BIN, 'PI_TEST_BIN must point to the patched Pi executable');
  const modules = process.env.PI_TEST_MODULES ?? join(dirname(dirname(process.env.PI_TEST_BIN)), 'lib', 'pi', 'node_modules');
  return import(pathToFileURL(join(modules, '@earendil-works', path)));
}

test('word motions distinguish words and WORDs and preserve Unicode graphemes', async () => {
  const { VimText } = await load('pi-coding-agent/dist/modes/interactive/vim-text.js');
  const text = new VimText(['', ' Alpha βeta foo-bar 👩‍💻', ' Résumé end'], 1);
  const alpha = text.firstNonblank(1);
  const beta = text.word(alpha, 'w', false, 1);
  const foo = text.word(alpha, 'w', false, 2);
  const hyphen = text.word(foo, 'w', false, 1);
  const emoji = text.word(foo, 'w', true, 1);
  assert.equal(text.text(beta, text.word(beta, 'e', false, 1), false), 'βeta');
  assert.equal(text.text(hyphen, hyphen, false), '-');
  assert.equal(text.text(foo, text.word(foo, 'e', true, 1), false), 'foo-bar');
  assert.equal(text.text(emoji, emoji, false), '👩‍💻');
  assert.deepEqual(text.word(text.firstNonblank(2), 'b', true, 1), emoji);
  assert.equal(text.columns(emoji)[1] - text.columns(emoji)[0], 2);
});

test('the Vim frame softens transcript colors and mutes the dock more strongly', async () => {
  const { setCapabilityOverrides } = await load('pi-tui/dist/index.js');
  const { initTheme } = await load('pi-coding-agent/dist/modes/interactive/theme/theme.js');
  const { paintVimFrame } = await load('pi-coding-agent/dist/modes/interactive/vim-dock.js');
  setCapabilityOverrides({ trueColor: true });
  initTheme('dark', false);
  const editor = {};
  const width = 54;
  const transcript = '\x1b[38;2;255;0;0mred\x1b[0m and \x1b[38;2;0;255;0mgreen\x1b[0m';
  const screen = [transcript, ' EXECUTE · PAIR'.padEnd(width - 5) + 'Ready', ' draft',
    ' \x1b[2;38;5;11mGPT\x1b[0m · \x1b[2;38;5;9mxhigh\x1b[0m'];
  const readyColumn = screen[1].indexOf('Ready');
  const clip = (y, height) => ({ x: 0, y, width, height });
  const dock = { clip: clip(1, 3), children: [{ component: editor, clip: clip(1, 2) }] };
  const primaryScrollView = { scrollTop: 0 };
  const view = { scrollView: primaryScrollView, rect: clip(0, 1), clip: clip(0, 1), children: [] };
  paintVimFrame(screen, { width, primaryScrollView, root: { children: [view, dock] } }, editor, 'NORMAL');
  const status = stripVTControlCharacters(screen[1]);
  assert.match(status, /^ EXECUTE · PAIR  +NORMAL/);
  assert.equal(status.indexOf('Ready'), readyColumn);
  assert.equal(stripVTControlCharacters(screen[0]), stripVTControlCharacters(transcript));
  assert.notEqual(screen[0], transcript);
  assert.doesNotMatch(screen[3], /\x1b\[2m/, 'terminal faint must not vary by footer field');
  const color = (row, text) => [...screen[row].slice(0, screen[row].indexOf(text)).matchAll(/\x1b\[38;2;(\d+);(\d+);(\d+)m/g)]
    .at(-1).slice(1).map(Number);
  const gpt = color(3, 'GPT');
  const red = color(0, 'red');
  const green = color(0, 'green');
  assert.ok(color(3, 'xhigh').every((channel, i) => Math.abs(channel - gpt[i]) < 20));
  assert.ok(red.every(channel => channel === red[0]) && green.every(channel => channel === green[0]));
  assert.ok(Math.abs(red[0] - green[0]) < 25);
  assert.ok(red.reduce((sum, n) => sum + n, 0) > gpt.reduce((sum, n) => sum + n, 0) + 60);
});

test('an open block retains its syntax and backgrounds while neighboring rows are monochrome', async () => {
  const { setCapabilityOverrides } = await load('pi-tui/dist/index.js');
  const { initTheme } = await load('pi-coding-agent/dist/modes/interactive/theme/theme.js');
  const { paintVimFrame } = await load('pi-coding-agent/dist/modes/interactive/vim-dock.js');
  setCapabilityOverrides({ trueColor: true });
  initTheme('dark', false);
  const syntax = '\x1b[38;2;35;190;105mconst value\x1b[39m';
  const diff = '\x1b[48;2;17;63;29m+\x1b[38;2;137;220;99mvalue\x1b[0m';
  const original = ['untouched', syntax, syntax, diff, diff, 'untouched'];
  const screen = [...original];
  const viewport = { scrollTop: 12 };
  const rect = { x: 0, y: 1, width: 30, height: 4 };
  const view = { scrollView: viewport, rect, clip: rect, children: [] };
  const frame = { width: 30, primaryScrollView: viewport, root: { children: [view] } };
  const editor = {};
  paintVimFrame(screen, frame, editor, 'NORMAL', [13, 15]);
  assert.equal(screen[2], syntax);
  assert.equal(screen[3], diff);
  assert.notEqual(screen[1], syntax);
  assert.notEqual(screen[4], diff);
  assert.equal(screen[0], original[0]);
  assert.equal(screen[5], original[5]);
  const closed = [...original];
  paintVimFrame(closed, frame, editor, 'NORMAL');
  assert.equal(closed[2], screen[1]);
  assert.equal(closed[3], screen[4]);
});

test('colored two-digit labels stay on the left over tables and wrapped continuations', async () => {
  const { setCapabilityOverrides } = await load('pi-tui/dist/index.js');
  const { initTheme, theme } = await load('pi-coding-agent/dist/modes/interactive/theme/theme.js');
  const { AssistantMessageComponent } = await load('pi-coding-agent/dist/modes/interactive/components/assistant-message.js');
  const { VimTranscript } = await load('pi-coding-agent/dist/modes/interactive/vim-transcript.js');
  const { paintVimFrame } = await load('pi-coding-agent/dist/modes/interactive/vim-dock.js');
  setCapabilityOverrides({ trueColor: true });
  initTheme('dark', false);
  const block = new AssistantMessageComponent();
  const rows = ['Heading', ...Array(9).fill(' paragraph'), '│ data │ row │', 'wrapped continuation'];
  block.render = () => rows;
  const viewport = { scrollTop: 0, viewportHeight: rows.length, isFollowingEnd: false, scrollTo() {} };
  let chatRow = 0;
  const transcript = new VimTranscript(() => viewport, () => chatRow, () => {}, () => {}, () => {});
  transcript.addChild(block);
  const width = 30;
  transcript.render(width);
  assert.equal(transcript.enter(), true);
  transcript.focused = true;
  transcript.handleInput('\r');
  transcript.render(width);
  const screen = [...rows];
  const rect = { x: 0, y: 0, width, height: rows.length };
  const view = { scrollView: viewport, rect, clip: rect, children: [] };
  assert.deepEqual(transcript.openRows(), [0, rows.length]);
  const region = paintVimFrame(screen, { width, primaryScrollView: viewport, root: { children: [view] } }, {}, 'NORMAL', transcript.openRows());
  transcript.paintVisible(screen, width, region);
  assert.match(stripVTControlCharacters(screen[10]), /^10data │ row │/);
  assert.match(stripVTControlCharacters(screen[11]), /^11apped continuation/);
  assert.ok(screen[10].includes(theme.getFgAnsi('error').slice(2, -1)), 'the badge retains the theme accent');
  assert.equal(rows[10], '│ data │ row │', 'post-layout painting never edits the document text');
  chatRow = 4;
  assert.deepEqual(transcript.openRows(), [4, 4 + rows.length], 'the index follows the document offset');
  block.render = () => [...rows, 'new line'];
  transcript.render(width);
  assert.deepEqual(transcript.openRows(), [4, 5 + rows.length], 'the index is rebuilt when the layout changes');
});

test('fullscreen Vim navigation operates on the real transcript and preserves the prompt draft', async () => {
  assert.ok(process.env.PI_TEST_BIN, 'PI_TEST_BIN must point to the patched Pi executable');
  const directory = mkdtempSync(join(tmpdir(), 'pi-vim-'));
  const socket = `pi-vim-${process.pid}`;
  const tmux = (...args) => execFileSync('tmux', ['-f', '/dev/null', '-L', socket, ...args], { encoding: 'utf8' });
  let pane;
  const send = (...keys) => tmux('send-keys', '-t', pane, ...keys);
  const screen = (ansi = false) => tmux('capture-pane', '-p', ...(ansi ? ['-e'] : []), '-t', pane);
  const verifyClipboard = process.platform === 'linux' || process.env.PI_TEST_OSC52 === '1';
  async function waitFor(condition) {
    const deadline = Date.now() + 8000;
    let frame;
    do {
      frame = screen();
      if (condition(frame)) return frame;
      await delay(40);
    } while (Date.now() < deadline);
    assert.fail(`Expected frame was not rendered:\n${frame}`);
  }
  const marker = (prefix, path) => new RegExp(`^[ \\t]*${prefix}(?![0-9])[^\\n]*fixture-${path}\\.txt`, 'm');
  const answer = prefix => new RegExp(`^ *${prefix} *Answer:`, 'm');
  try {
    const session = createSession(directory);
    const agent = join(directory, 'agent');
    mkdirSync(agent);
    writeFileSync(join(agent, 'keybindings.json'), readFileSync(new URL('../keybindings.json', import.meta.url)));
    pane = tmux('new-session', '-d', '-P', '-F', '#{pane_id}', '-c', directory, '-x', '105', '-y', '42',
      '-e', `PI_CODING_AGENT_DIR=${agent}`, '-e', 'PI_CLIPBOARD_OSC52=1', process.env.PI_TEST_BIN,
      '--no-extensions', '--no-skills', '--no-mcp', '--tui-mode', 'fullscreen', '--session', session).trim();
    if (verifyClipboard) tmux('set-option', '-s', 'set-clipboard', 'on');
    tmux('set-option', '-w', '-t', pane, 'remain-on-exit', 'on');
    await waitFor(frame => frame.includes('output-11'));
    send('-l', 'keep this draft');
    const ghosttyConfig = readFileSync(new URL('../../ghostty/config', import.meta.url), 'utf8');
    const shiftEnter = ghosttyConfig.match(/^keybind = shift\+enter=text:(.+)$/m)[1].replaceAll('\\x1b', '\x1b');
    send('-l', shiftEnter);
    send('-l', 'shift-enter line');
    send('C-j');
    send('-l', 'ctrl-j line');
    const insert = await waitFor(frame => /keep this draft[^\n]*\n *shift-enter line[^\n]*\n *ctrl-j line/.test(frame));
    const draftStyle = frame => frame.split('\n').find(line => line.includes('keep this draft'));
    const footerStyle = frame => frame.split('\n').find(line => line.includes('↑12 ↓12'));
    const insertDock = screen(true);
    const header = frame => frame.split('\n').find(line => line.includes('fixture-11.txt'));
    const blockColumn = header(insert).indexOf('$');
    assert.ok(blockColumn >= 0 && blockColumn <= 1, 'the transcript uses its native left padding');
    const insertHeader = header(screen(true));
    const insertTitle = insertHeader.slice(insertHeader.indexOf('$'));
    send('C-c');
    await delay(100);
    assert.doesNotMatch(screen(), marker('▸', 11));
    send('Escape');
    await waitFor(frame => answer('▸').test(frame) && marker('1', 11).test(frame) && frame.includes('NORMAL'));
    const normalDock = screen(true);
    assert.notEqual(draftStyle(normalDock), draftStyle(insertDock), 'Escape mutes the draft immediately');
    assert.notEqual(footerStyle(normalDock), footerStyle(insertDock), 'Escape mutes the footer immediately');
    send('Right');
    await waitFor(frame => answer('│').test(frame));
    send('$', '0', '^', 'W', 'W', 'v', 'E');
    await waitFor(frame => answer('│').test(frame) && frame.includes('VISUAL'));
    if (verifyClipboard) {
      send('y');
      await waitFor(frame => answer('✓').test(frame));
      assert.equal(tmux('show-buffer'), 'cat-dog');
    }
    send('Left');
    await waitFor(frame => answer('▸').test(frame));
    send('Up');
    const normal = await waitFor(frame => marker('▸', 11).test(frame) && marker('1', 10).test(frame));
    assert.equal(header(normal).indexOf('$'), blockColumn);
    assert.doesNotMatch(normal, /^ +output-11 *$/m, 'tool output is hidden before entering');
    const selectedHeader = header(screen(true));
    assert.match(selectedHeader, /\x1b\[[\d;]*(?:4[0-7]|48;[25];[\d;]+)m[^\n]*▸/);
    assert.notEqual(selectedHeader.slice(selectedHeader.indexOf('$')), insertTitle);
    send('2', 'Up');
    await waitFor(frame => marker('▸', 9).test(frame) && marker('1', 10).test(frame) && marker('2', 11).test(frame));
    assert.doesNotMatch(screen(), /selected-output-|13 earlier lines/);
    send('Right');
    const opened = await waitFor(frame => marker('│', 9).test(frame) && frame.includes('selected-output-1'));
    assert.doesNotMatch(opened, /^ +output-(?:10|11) *$/m, 'only the entered call exposes its output');
    send('2', 'Down');
    const details = await waitFor(frame => /^ *│ *selected-output-1 *$/m.test(frame));
    assert.match(details, /^10elected-output-11 *$/m, 'two-digit badges stay pinned to the left');
    send('V', 'Down');
    await waitFor(frame => /^ *│ *selected-output-2 *$/m.test(frame) && frame.includes('VISUAL'));
    assert.equal(draftStyle(screen(true)), draftStyle(normalDock), 'the draft stays muted in VISUAL');
    if (verifyClipboard) {
      send('y');
      await waitFor(frame => /^ *✓ *selected-output-2 *$/m.test(frame));
      assert.equal(tmux('show-buffer').trim().replace(/^ +/gm, ''), 'selected-output-1\nselected-output-2');
    }
    send('Left');
    await waitFor(frame => marker('▸', 9).test(frame) && !frame.includes('selected-output-') && frame.includes('NORMAL'));
    send('Enter');
    await waitFor(frame => marker('│', 9).test(frame));
    send('Escape');
    await waitFor(frame => marker('▸', 9).test(frame) && !frame.includes('selected-output-'));
    send('2', 'C-u');
    const scrolled = await waitFor(frame => /^ *▸[^\n]*fixture-[2-8]\.txt/m.test(frame));
    const pageAnchor = Number(scrolled.match(/^ *▸[^\n]*fixture-([2-8])\.txt/m)[1]);
    send('Up');
    await waitFor(frame => marker('▸', pageAnchor - 1).test(frame));
    send('C-a');
    const start = await waitFor(frame => frame.includes('shell-fixture') && /^ *▸[^\n]*fixture-[1-4]\.txt/m.test(frame));
    assert.doesNotMatch(start, /recorded-shell-output/, 'direct shell output is hidden too');
    assert.match(start, /v\d+\.\d+\.\d+\/cosm/);
    const selectedAtTop = Number(start.match(/^ *▸[^\n]*fixture-([1-4])\.txt/m)[1]);
    send(String(9 - selectedAtTop), 'Down');
    const down = await waitFor(frame => marker('▸', 9).test(frame));
    assert.ok(down.split('\n').findIndex(line => marker('▸', 9).test(line)) >= 30, 'downward jump reveals the item at the bottom edge');
    send('i');
    await waitFor(frame => frame.includes('keep this draft') && !frame.includes('NORMAL') && /^ +output-11 *$/m.test(frame));
    assert.equal(draftStyle(screen(true)), draftStyle(insertDock), 'leaving Vim restores the original draft colors');
    send('Escape');
    await waitFor(frame => answer('▸').test(frame));
    const paneStatus = () => tmux('display-message', '-p', '-t', pane, '#{pane_dead}:#{pane_dead_status}').trim();
    send('C-c');
    await waitFor(frame => frame.includes('keep this draft') && !frame.includes('▸'));
    await delay(700);
    send('C-c');
    await delay(700);
    assert.equal(paneStatus().split(':')[0], '0', 'single and spaced interrupts do not quit');
    send('C-c', 'C-c');
    const deadline = Date.now() + 5000;
    while (!paneStatus().startsWith('1:') && Date.now() < deadline) await delay(40);
    assert.equal(paneStatus(), '1:0', 'two quick interrupts exit gracefully');
  } finally {
    try { tmux('kill-server'); } catch {}
    rmSync(directory, { recursive: true, force: true });
  }
});
