import assert from 'node:assert/strict';
import test from 'node:test';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const dist = join(process.env.PI_TEST_MODULES, '@earendil-works/pi-coding-agent/dist');
const { loadExtensions, createExtensionRuntime } = await import(pathToFileURL(join(dist, 'core/extensions/loader.js')));
const runtime = createExtensionRuntime();
const loaded = await loadExtensions([fileURLToPath(new URL('../extensions/codex-web-search.ts', import.meta.url))], '/tmp', undefined, runtime);
assert.deepEqual(loaded.errors, []);
const extension = loaded.extensions[0];

const codex = { model: { provider: 'openai-codex' } };
const other = { model: { provider: 'anthropic' } };
const setup = (activeTools = ['read']) => {
  runtime.getActiveTools = () => activeTools;
  return Object.fromEntries([...extension.handlers].map(([name, handlers]) => [name, handlers[0]]));
};

test('Codex gets optional hosted search alongside its existing tools', () => {
  const request = setup().before_provider_request;
  const payload = { tools: [{ type: 'function', name: 'read' }], tool_choice: 'auto', input: [] };
  const result = request({ payload }, codex);
  assert.deepEqual(result, { ...payload, tools: [...payload.tools, { type: 'web_search' }] });
  assert.equal(payload.tools.length, 1);
  assert.equal(request({ payload: result }, codex), undefined);
  assert.equal(request({ payload }, other), undefined);
  assert.equal(request({ payload: { ...payload, tool_choice: 'none' } }, codex), undefined);
  assert.deepEqual(request({ payload: {} }, codex), { tools: [{ type: 'web_search' }] });
  assert.equal(setup([]).before_provider_request({ payload: {} }, codex), undefined);
});

test('search preference is Codex-only and respects a tool-free turn', () => {
  const event = { systemPrompt: 'Existing prompt' };
  const prompt = setup().before_agent_start(event, codex).systemPrompt;
  assert.match(prompt, /^Existing prompt\n\n.*web_search first/);
  assert.match(prompt, /Exa search only if built-in search is unavailable or fails/);
  assert.equal(setup().before_agent_start(event, other), undefined);
  assert.equal(setup([]).before_agent_start(event, codex), undefined);
});

test('the codemode tool requires provider search evidence and returns structured citations', async () => {
  const tool = extension.tools.get('codex_web_search').definition;
  const events = [
    { type: 'response.output_item.done', item: { type: 'web_search_call', status: 'completed' } },
    { type: 'response.output_text.annotation.added', annotation: { type: 'url_citation', url: 'https://example.org/', title: 'Example' } },
  ];
  let observed = events;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response(observed.map(event => `data: ${JSON.stringify(event)}\n\n`).join(''));
  try {
    const ctx = { ...codex, modelRegistry: { streamSimple(_model, context, options) {
      assert.deepEqual(context.messages.map(message => message.content), ['public query']);
      assert.equal(options.onPayload({}).tool_choice, 'required');
      return { async result() {
        await (await options.fetch('https://example.org/')).text();
        return { stopReason: 'stop', content: [{ type: 'text', text: 'Answer' }] };
      } };
    } } };
    const run = () => tool.execute('id', { query: 'public query' }, undefined, undefined, ctx);
    assert.deepEqual((await run()).structuredContent, { answer: 'Answer', sources: [{ url: 'https://example.org/', title: 'Example' }] });
    observed = events.slice(1);
    await assert.rejects(run, /did not return a completed web search/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
