import { createReadStream } from 'node:fs';
import { createInterface } from 'node:readline';
import { pathToFileURL } from 'node:url';

export async function selectTask(file, start, end) {
  if (!start || !end) throw new Error('Both task boundary IDs are required.');
  const entries = new Map();
  let invalidLines = 0;
  const input = createReadStream(file, { encoding: 'utf8' });
  for await (const line of createInterface({ input, crlfDelay: Infinity })) {
    if (!line.trim()) continue;
    let entry;
    try { entry = JSON.parse(line); } catch { invalidLines++; continue; }
    if (entry?.type === 'session') continue;
    if (typeof entry?.id !== 'string' || !entry.id) { invalidLines++; continue; }
    if (entries.has(entry.id)) throw new Error('Duplicate entry ID in the transcript.');
    entries.set(entry.id, entry);
  }
  if (!entries.has(start) || !entries.has(end)) throw new Error('Task boundary not found in the transcript.');
  const branch = [];
  const seen = new Set();
  for (let id = end; id != null;) {
    if (seen.has(id)) throw new Error('Cycle in the task branch.');
    const entry = entries.get(id);
    if (!entry) throw new Error('Missing parent in the task branch.');
    seen.add(id);
    branch.push(entry);
    if (id === start) return { entries: branch.reverse(), invalidLines };
    id = entry.parentId;
  }
  throw new Error('The start boundary is not an ancestor of the end boundary.');
}

const textBlocks = message => (message.content ?? []).filter(block => block.type === 'text');
const usageFields = ['input', 'cacheRead', 'cacheWrite', 'output', 'estimatedUsd'];

export function summarizeTask({ entries, invalidLines }) {
  const calls = new Map();
  const tools = new Map();
  const models = new Set();
  const usage = Object.fromEntries(usageFields.map(key => [key, { knownTotal: null, missingRecords: 0 }]));
  let modelTurns = 0;
  let finalAnswer = null;
  let unmatchedResults = 0;
  let recordedToolTextBytes = 0;
  const countUsage = record => {
    for (const key of usageFields) {
      const value = key === 'estimatedUsd' ? record?.cost?.total : record?.[key];
      const metric = usage[key];
      if (!Number.isFinite(value) || value < 0) metric.missingRecords++;
      else metric.knownTotal = (metric.knownTotal ?? 0) + value;
    }
  };
  const modelKey = row => {
    if (typeof row.model === 'string' && row.model) models.add(row.provider ? `${row.provider}/${row.model}` : row.model);
  };
  for (const entry of entries) {
    const message = entry.type === 'message' ? entry.message : undefined;
    if (message?.role === 'assistant') {
      modelTurns++;
      modelKey(message);
      countUsage(message.usage);
      const blocks = (message.content ?? []).filter(block => block.type === 'toolCall');
      finalAnswer = !blocks.length && message.stopReason === 'stop'
        ? textBlocks(message).map(block => block.text).join('\n') : null;
      for (const block of blocks) {
        const stats = tools.get(block.name) ?? { calls: 0, results: 0, errors: 0, recordedTextBytes: 0 };
        tools.set(block.name, stats);
        stats.calls++;
        if (block.id) calls.set(block.id, stats);
      }
    } else if (message?.role === 'toolResult') {
      const bytes = textBlocks(message).reduce((sum, block) => sum + Buffer.byteLength(block.text), 0);
      recordedToolTextBytes += bytes;
      const stats = calls.get(message.toolCallId);
      if (stats) {
        stats.results++;
        stats.recordedTextBytes += bytes;
        if (message.isError) stats.errors++;
        calls.delete(message.toolCallId);
      } else unmatchedResults++;
      if (message.usage) countUsage(message.usage);
    } else if (['usage', 'compaction', 'branch_summary'].includes(entry.type)) {
      modelKey(entry);
      countUsage(entry.usage);
    }
  }
  const toolCalls = [...tools.values()].reduce((sum, stats) => sum + stats.calls, 0);
  const matchedResults = [...tools.values()].reduce((sum, stats) => sum + stats.results, 0);
  return {
    models: [...models], modelTurns, toolCalls, tools: Object.fromEntries(tools),
    toolResults: matchedResults + unmatchedResults, callsWithoutResult: toolCalls - matchedResults, unmatchedResults,
    recordedToolTextBytes, finalAnswerCharacters: finalAnswer === null ? null : [...finalAnswer].length,
    invalidTranscriptLines: invalidLines, usage,
    costNotice: 'Estimated by Pi, not a bill. Actual charges and subscription quota are unavailable from the transcript.',
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.argv.length !== 5) throw new Error('Usage: node tools/pi/session-analysis.mjs SESSION.jsonl START_ID END_ID');
    const task = await selectTask(...process.argv.slice(2));
    console.log(JSON.stringify(summarizeTask(task), null, 2));
  } catch (error) {
    console.error(error.code ? `Cannot read the session (${error.code}).` : error.message);
    process.exitCode = 1;
  }
}
