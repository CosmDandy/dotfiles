import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { selectTask, summarizeTask } from '../session-analysis.mjs';

test('selects inclusive boundaries on one branch', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'pi-session-analysis-'));
  try {
    const file = join(dir, 'session.jsonl');
    const entry = (id, parentId) => ({ type: 'message', id, parentId });
    await writeFile(file, [
      { type: 'session', id: 'session' }, entry('prior', null), entry('start', 'prior'),
      entry('other', 'start'), entry('mid', 'start'), entry('end', 'mid'), entry('later', 'end'),
    ].map(row => JSON.stringify(row)).join('\n') + '\n{"incomplete":');
    const task = await selectTask(file, 'start', 'end');
    assert.deepEqual(task.entries.map(row => row.id), ['start', 'mid', 'end']);
    assert.equal(task.invalidLines, 1);
    await assert.rejects(selectTask(file, 'other', 'end'), /not an ancestor/);
    await assert.rejects(selectTask(file, 'missing', 'end'), /boundary not found/);
    await assert.rejects(selectTask(join(dir, 'missing.jsonl'), 'start', 'end'), { code: 'ENOENT' });
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

const message = (role, fields) => ({ type: 'message', message: { role, ...fields } });
const text = value => ({ type: 'text', text: value });
const call = (id, name) => ({ type: 'toolCall', id, name, arguments: { path: 'private-fixture' } });

test('counts calls, partial usage and UTF-8 output without publishing content', () => {
  const report = summarizeTask({ invalidLines: 1, entries: [
    message('assistant', { provider: 'openai-codex', model: 'example', content: [call('1', 'read'), call('2', 'bash')], usage: { input: 5, output: 3 } }),
    message('toolResult', { toolCallId: '1', content: [text('я🛠'), { type: 'image', data: 'private-fixture' }], isError: true, usage: { input: 1, output: 1 } }),
    { type: 'usage', usage: { cacheRead: 10, cost: { total: 0.05 } } },
    { type: 'compaction', usage: { input: 2, output: 3, cacheWrite: 0 } },
    { type: 'branch_summary' },
    message('assistant', { stopReason: 'stop', content: [text('Ответ 🛠')], usage: { input: 0, output: 4 } }),
  ] });
  assert.deepEqual(report.models, ['openai-codex/example']);
  assert.equal(report.modelTurns, 2);
  assert.equal(report.toolCalls, 2);
  assert.equal(report.toolResults, 1);
  assert.equal(report.callsWithoutResult, 1);
  assert.deepEqual(report.tools.read, { calls: 1, results: 1, errors: 1, recordedTextBytes: 6 });
  assert.equal(report.recordedToolTextBytes, 6);
  assert.equal(report.finalAnswerCharacters, 7);
  assert.equal(report.invalidTranscriptLines, 1);
  assert.deepEqual(report.usage.input, { knownTotal: 8, missingRecords: 2 });
  assert.deepEqual(report.usage.output, { knownTotal: 11, missingRecords: 2 });
  assert.deepEqual(report.usage.cacheRead, { knownTotal: 10, missingRecords: 5 });
  assert.deepEqual(report.usage.cacheWrite, { knownTotal: 0, missingRecords: 5 });
  assert.deepEqual(report.usage.estimatedUsd, { knownTotal: 0.05, missingRecords: 5 });
  assert.match(report.costNotice, /not a bill/);
  assert.doesNotMatch(JSON.stringify(report), /private-fixture|Ответ|я🛠/);
});
