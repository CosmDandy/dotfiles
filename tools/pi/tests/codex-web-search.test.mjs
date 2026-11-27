import assert from 'node:assert/strict';
import test from 'node:test';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const dist = join(process.env.PI_TEST_MODULES, '@earendil-works/pi-coding-agent/dist');
const { loadExtensions, createExtensionRuntime } = await import(pathToFileURL(join(dist, 'core/extensions/loader.js')));
const { createCodemodeToolDefinition } = await import(pathToFileURL(join(dist, 'extensions/codemode/tool.js')));
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

test('the search instructions distinguish hosted search from the codemode route', () => {
  const section = (tools, ctx) => {
    const event = { systemPromptOptions: { sections: {} } };
    setup(tools).before_agent_start(event, ctx);
    return event.systemPromptOptions.sections.codex_web_search;
  };
  assert.match(section(['read'], codex), /hosted web_search first/);
  assert.doesNotMatch(section(['read'], codex), /tools\.codex_web_search/);
  for (const ctx of [codex, other]) {
    const prompt = section(['codemode'], ctx);
    assert.match(prompt, /tools\.codex_web_search\(\{ query \}\)/);
    assert.match(prompt, /Omit timeout_ms/);
    assert.match(prompt, /Use Exa only if Codex search is unavailable or fails/);
  }
  assert.equal(section(['read'], other), undefined);
  assert.equal(section([], codex), undefined);
});

test('Pi lists the search tool and its timeout guidance in the codemode catalog', () => {
  const search = extension.tools.get('codex_web_search').definition;
  const codemode = createCodemodeToolDefinition();
  const catalog = codemode.prepareLoadout({
    callable: [search],
    declared: [codemode],
    getExposure: () => search.exposure,
    getNamespace: () => undefined,
    getPromptGuidelines: () => search.promptGuidelines,
  }).descriptions.codemode;
  assert.match(catalog, /tools\.codex_web_search/);
  assert.match(catalog, /Omit timeout_ms/);
});

test('short codemode deadlines are rejected before a Codex web search starts', () => {
  const check = (code, toolName = 'codemode') => setup().tool_call({ toolName, input: { code } });
  const short = '// @options: {"timeout_ms": 20000}';
  const search = 'return await tools.codex_web_search({ query: "public query" });';
  assert.match(check(`${short}\n${search}`).reason, /without timeout_ms.*300000/);
  assert.equal(check(`${short}\nreturn await tools["codex_web_search"]({ query: "public query" });`).block, true);
  assert.equal(check(search), undefined);
  assert.equal(check(`// @options: {"max_output_tokens": 500}\n${search}`), undefined);
  assert.equal(check(`// @options: {"timeout_ms": 300000}\n${search}`), undefined);
  assert.equal(check(`${short}\nreturn await tools.read({ path: "README.md" });`), undefined);
  assert.equal(check(`${short}\n${search}`, 'another_tool'), undefined);
});

test('the 180-second deadline is distinguished from a caller abort', async (t) => {
  const tool = extension.tools.get('codex_web_search').definition;
  const deadline = new AbortController();
  const caller = new AbortController();
  t.mock.method(AbortSignal, 'timeout', ms => {
    assert.equal(ms, 180_000);
    return deadline.signal;
  });
  const ctx = { ...codex, modelRegistry: { streamSimple(_model, _context, options) {
    return { async result() {
      assert.equal(options.signal.aborted, true);
      return { stopReason: 'aborted', errorMessage: 'Request was aborted' };
    } };
  } } };
  const run = signal => tool.execute('id', { query: 'public query' }, signal, undefined, ctx);
  caller.abort();
  await assert.rejects(run(caller.signal), { message: 'Request was aborted' });
  deadline.abort(new DOMException('Timed out', 'TimeoutError'));
  await assert.rejects(run(), { message: 'Codex web search timed out after 180 seconds.' });
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
