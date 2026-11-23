import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('../install-mcp.sh', import.meta.url));
const template = fileURLToPath(new URL('../mcp.json', import.meta.url));
const defaults = JSON.parse(readFileSync(template));

test('installs MCP defaults without replacing user configuration', t => {
  const dir = mkdtempSync(join(tmpdir(), 'pi-mcp-install-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const target = join(dir, 'agent', 'mcp.json');
  const install = (path = target) => spawnSync('bash', [script, template, path], { encoding: 'utf8' });
  const expectInstalled = () => {
    const result = install();
    assert.equal(result.status, 0, result.stderr);
  };

  expectInstalled();
  assert.deepEqual(JSON.parse(readFileSync(target)), defaults);
  assert.equal(statSync(target).mode & 0o777, 0o600);

  const user = { autoEnableCodemode: false, mcpServers: {
    knowledge: { url: 'https://mcp.example.invalid', enabled: false },
    custom: { command: 'custom-mcp' },
  } };
  writeFileSync(target, JSON.stringify(user));
  expectInstalled();
  assert.deepEqual(JSON.parse(readFileSync(target)), {
    ...user, mcpServers: { ...defaults.mcpServers, ...user.mcpServers },
  });
  const inode = statSync(target).ino;
  expectInstalled();
  assert.equal(statSync(target).ino, inode, 'an unchanged file should not be replaced');

  const backing = join(dir, 'linked-config.json');
  const linked = join(dir, 'symlink.json');
  writeFileSync(backing, '{}');
  symlinkSync(backing, linked);
  assert.notEqual(install(linked).status, 0);
  assert.equal(readFileSync(backing, 'utf8'), '{}');

  for (const invalid of ['', '{invalid', '{"mcpServers": []}', '{"value": NaN}', '{}\n{}']) {
    writeFileSync(target, invalid);
    assert.notEqual(install().status, 0);
    assert.equal(readFileSync(target, 'utf8'), invalid);
  }
});
