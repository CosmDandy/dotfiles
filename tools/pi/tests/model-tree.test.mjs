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
console.log('PASS: model tree, collapse, expand, flat search and model selection');
