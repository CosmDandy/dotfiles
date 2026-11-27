import assert from 'node:assert/strict';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { test } from 'node:test';

const dist = join(process.env.PI_TEST_MODULES, '@earendil-works/pi-coding-agent/dist');
const { loadExtensions, createExtensionRuntime } = await import(pathToFileURL(join(dist, 'core/extensions/loader.js')));
const path = fileURLToPath(new URL('../extensions/session-auto-title.ts', import.meta.url));
const user = { type: 'message', message: { role: 'user', content: [
  { type: 'text', text: 'Проверить сборку' }, { type: 'image', data: 'image-data' },
] } };
const assistant = { type: 'message', message: { role: 'assistant', stopReason: 'stop', content: 'private answer' } };

async function fixture({ existing = [], name, mode = 'tui', file = '/tmp/session.jsonl' } = {}) {
  const runtime = createExtensionRuntime();
  runtime.getSessionName = () => name;
  runtime.setSessionName = value => { name = value; };
  const loaded = await loadExtensions([path], '/tmp', undefined, runtime);
  assert.deepEqual(loaded.errors, []);
  const { handlers, tools } = loaded.extensions[0];
  const calls = [];
  const result = Promise.withResolvers();
  const ctx = { mode, model: { id: 'fixture' }, modelRegistry: {
    streamSimple(model, context, options) {
      calls.push({ model, context, options });
      return { result: () => result.promise };
    },
  }, sessionManager: {
    getEntries: () => existing, getBranch: () => [user, assistant], getSessionFile: () => file,
  } };
  handlers.get('session_start')[0]({}, ctx);
  return {
    calls, name: () => name, rename: value => { name = value; },
    tool: tools.get('rename_session')?.definition,
    settle: (aborted = false) => handlers.get('agent_settled')[0]({ aborted }, ctx),
    shutdown: () => handlers.get('session_shutdown')[0]({}, ctx),
    finish: async (stopReason = 'stop', text = '  Verify\n  Build  ') => {
      result.resolve({ stopReason, content: [{ type: 'text', text }] });
      await new Promise(resolve => setImmediate(resolve));
    },
  };
}

test('names a new session once in the background, using only the first prompt text', async () => {
  const session = await fixture();
  assert.equal(session.settle(), undefined);
  session.settle();
  assert.equal(session.name(), undefined);
  assert.equal(session.calls.length, 1);
  const [{ model, context }] = session.calls;
  assert.equal(model.id, 'fixture');
  assert.deepEqual(context.messages.map(({ content }) => content), ['Проверить сборку']);
  assert.equal(context.tools, undefined);
  assert.match(context.systemPrompt, /English session title/);
  assert.match(context.systemPrompt, /lowercase, at most 4 words/);
  assert.match(context.systemPrompt, /Start with a specific action verb/);
  assert.match(context.systemPrompt, /precise technical terms over generic filler/);
  assert.match(context.systemPrompt, /do not assume it was completed/);
  await session.finish();
  assert.equal(session.name(), 'verify build');
});

test('caps generated names at four lowercase words', async () => {
  const session = await fixture();
  session.settle();
  await session.finish('stop', '\x1b[31mDiagnose Pnpm Dependency Resolution\x1b[0m Errors');
  assert.equal(session.name(), 'diagnose pnpm dependency resolution');
});

test('renames an existing session on request using the same title rules', async () => {
  const session = await fixture({ existing: [user], name: 'First Task' });
  const { tool } = session;
  assert.equal(tool?.label, 'Rename Session');
  assert.match(tool.description, /only when the user explicitly asks/);
  assert.match(tool.description, /lowercase, at most 4 words/);
  assert.match(tool.description, /Start with a specific action verb/);
  assert.match(tool.description, /precise technical terms over generic filler/);
  assert.match(tool.description, /past tense for completed work/);
  await assert.rejects(tool.execute('rename', { title: ' \t\n\x1b[31m ' }), /non-empty session title/);
  await assert.rejects(tool.execute('rename', { title: 'Cancelled rename' }, AbortSignal.abort()), { name: 'AbortError' });
  assert.equal(session.name(), 'First Task');
  const result = await tool.execute('rename', { title: 'Stabilized  Codex\nWebSocket Reconnects In Pi' });
  assert.equal(session.name(), 'stabilized codex websocket reconnects');
  assert.match(result.content[0].text, /stabilized codex websocket reconnects/);
  assert.equal(session.calls.length, 0, 'renaming does not make a separate model request');
});

test('skips existing, named, ephemeral, non-TUI and aborted sessions', async () => {
  for (const [options, aborted] of [[{ existing: [user] }], [{ name: 'Manual' }],
    [{ file: null }], [{ mode: 'print' }], [{}, true]]) {
    const session = await fixture(options);
    session.settle(aborted);
    assert.equal(session.calls.length, 0);
  }
});

test('preserves manual names and drops failed or late responses', async () => {
  const renamed = await fixture();
  renamed.settle();
  renamed.rename('Manual');
  await renamed.finish();
  assert.equal(renamed.name(), 'Manual');

  const closed = await fixture();
  closed.settle();
  closed.shutdown();
  assert.equal(closed.calls[0].options.signal.aborted, true);
  await closed.finish();
  assert.equal(closed.name(), undefined);

  const failed = await fixture();
  failed.settle();
  await failed.finish('error');
  assert.equal(failed.name(), undefined);
});
