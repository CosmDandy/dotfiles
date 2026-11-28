import assert from 'node:assert/strict';
import { stripVTControlCharacters as plain } from 'node:util';
import { pathToFileURL } from 'node:url';
const base = pathToFileURL(`${process.env.PI_TEST_MODULES}/@earendil-works/pi-coding-agent/dist/modes/interactive/`);
const { ModelSelectorComponent } = await import(new URL('components/model-selector.js', base));
const { initTheme } = await import(new URL('theme/theme.js', base));
initTheme('dark', false);
const models = ['gpt-6.2-sol', 'gpt-6.2-astra', 'gpt-6.1-sol'].map(id => ({ id, name: id.replace(/^gpt-/, '').replace(/-([a-z])/, (_, c) => ' ' + c.toUpperCase()), provider: 'openai-codex', contextWindow: 500000, cost: { input: 1, output: 2, cacheRead: 0, cacheWrite: 0 } }));
let chosen;
const selector = new ModelSelectorComponent({ requestRender() {} }, models[0], {
  getAvailableSnapshot: () => models, refresh: async () => ({ errors: new Map() }), getError: () => undefined,
}, [], model => { chosen = model; }, () => {});
try {
  await new Promise(resolve => setImmediate(resolve));
  const screen = () => plain(selector.render(120).join('\n'));
  assert.match(screen(), /├── 6\.2/);
  assert.match(screen(), /│   └── 6\.2 Sol\s+500K/);
  assert.match(screen(), /└── 6\.1/);
  selector.handleInput('\x1b[D');
  assert.doesNotMatch(screen(), /500K/);
  selector.handleInput('\x1b[C');
  assert.match(screen(), /500K/);
  for (const key of '6.1-sol') selector.handleInput(key);
  assert.doesNotMatch(screen(), /[├└]──|gpt-6\.1-sol/i);
  assert.match(screen(), /6\.1 Sol/);
  selector.handleInput('\r');
  assert.equal(chosen, models[2]);
} finally { selector.dispose(); }
const sol = { ...models[0], provider: 'litellm' };
const preset = { ...sol, id: 'sol-medium', api: 'pi-virtual' };
const directPreset = { ...preset, provider: 'openai-codex' };
const otherVirtual = { ...preset, id: 'other-virtual', name: 'Other Virtual' };
const catalog = [sol, preset, directPreset, otherVirtual];
const picker = new ModelSelectorComponent({ requestRender() {} }, preset, {
  getAvailableSnapshot: () => catalog,
  getModel: (provider, id) => catalog.find(model => model.provider === provider && model.id === id),
  refresh: async () => ({ errors: new Map() }), getError: () => undefined,
}, [sol, preset].map(model => ({ model })), model => { chosen = model; }, () => {});
try {
  const screen = () => plain(picker.render(120).join('\n'));
  assert.match(screen(), /sol-medium/);
  picker.handleInput('\t');
  await new Promise(resolve => setImmediate(resolve));
  assert.doesNotMatch(screen(), /sol-medium|Sol · medium/);
  assert.match(screen(), /other-virtual/);
  for (const key of 'sol-medium') picker.handleInput(key);
  assert.match(screen(), /No matching models/);
  for (const _ of 'sol-medium') picker.handleInput('\x7f');
  for (const key of '6.2-sol') picker.handleInput(key);
  assert.match(screen(), /gpt-6\.2-sol|6\.2 Sol/);
  assert.doesNotMatch(screen(), /sol-medium|Sol · medium/);
  picker.handleInput('\r');
  assert.equal(chosen, sol);
  for (const _ of '6.2-sol') picker.handleInput('\x7f');
  picker.handleInput('\t');
  assert.match(screen(), /sol-medium/);
  picker.handleInput('\r');
  assert.equal(chosen, preset);
} finally { picker.dispose(); }
console.log('PASS: model tree, collapse, expand, flat search, scoped-only Sol medium, and model selection');
