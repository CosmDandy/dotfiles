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
  const handlers = loaded.extensions[0].handlers;
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
  assert.match(context.systemPrompt, /six words or fewer/);
  await session.finish();
  assert.equal(session.name(), 'Verify Build');
});

test('caps the stored title at eight words', async () => {
  const session = await fixture();
  session.settle();
  await session.finish('stop', 'Check Build Artifacts And Verify Release Notes Before Deployment');
  assert.equal(session.name(), 'Check Build Artifacts And Verify Release Notes Before');
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
