import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const agentDir = join(homedir(), '.pi', 'agent');
const modules = process.env.PI_TEST_MODULES ?? join(agentDir, 'install', 'releases',
  readFileSync(join(agentDir, 'install', 'current-version'), 'utf8').trim(), 'node_modules');
const dist = join(modules, '@earendil-works/pi-coding-agent/dist');
const { loadExtensions } = await import(pathToFileURL(join(dist, 'core/extensions/loader.js')));
const path = fileURLToPath(new URL('../extensions/compaction.ts', import.meta.url));
const loaded = await loadExtensions([path], '/tmp');
assert.deepEqual(loaded.errors, []);
const [handler] = loaded.extensions[0].handlers.get('session_before_compact');
const command = 'make check CONFIG=fixture';
const symptom = 'fixture.conf: missing section [demo]';
const user = text => ({ role: 'user', content: text, timestamp: 1 });
const preparation = {
  messagesToSummarize: [user(`The check failed: ${symptom}. After adding the section, ${command} passed.`)],
  firstKeptEntryId: 'kept', tokensBefore: 2048,
  fileOps: { written: new Set(['fixture.conf']), read: new Set(), edited: new Set() },
  isSplitTurn: false, turnPrefixMessages: [],
};
const signal = new AbortController().signal;
for (const reason of ['manual', 'threshold', 'overflow']) {
  const prompts = [];
  const modelRegistry = { streamSimple(_model, context, options) {
    assert.equal(options.signal, signal);
    prompts.push(JSON.stringify(context.messages));
    return { result: async () => ({ stopReason: 'stop', content: [{ type: 'text', text: 'fixture summary' }] }) };
  } };
  const split = reason === 'overflow';
  const result = await handler({ reason, signal, customInstructions: reason === 'manual' ? 'Remember ticket DEMO-42.' : undefined,
    preparation: { ...preparation, isSplitTurn: split, turnPrefixMessages: split ? [user('Continue testing.')] : [] } },
    { model: { id: 'fixture', contextWindow: 32000 }, modelRegistry });
  assert.equal(result.compaction.firstKeptEntryId, 'kept');
  assert.match(result.compaction.summary, /fixture summary/);
  assert.deepEqual(result.compaction.details.modifiedFiles, ['fixture.conf']);
  assert.equal(prompts.length, split ? 2 : 1);
  assert.ok(prompts[0].includes(command) && prompts[0].includes(symptom));
  for (const prompt of prompts) {
    assert.ok(prompt.includes('Additional focus: Preserve in my words, not a paraphrase:'));
    assert.ok(prompt.includes('Drop: file contents, tool output, search results, superseded reasoning.'));
    assert.equal(prompt.includes('Remember ticket DEMO-42.'), reason === 'manual');
  }
}
console.log('PASS: manual focus, threshold, overflow and split-turn requests use native compaction with the additional instructions');
