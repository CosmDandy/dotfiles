import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const script = fileURLToPath(new URL("../install-subagents-settings.sh", import.meta.url));
const defaultsPath = fileURLToPath(new URL("../settings.json", import.meta.url));
const defaults = JSON.parse(readFileSync(defaultsPath)).subagents;

test("upgrades the old managed agent tool lists, preserving other settings", t => {
  const directory = mkdtempSync(join(tmpdir(), "pi-subagents-settings-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const path = join(directory, "settings.json");
  const install = () => {
    const result = spawnSync("bash", [script, defaultsPath, path], { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
  };
  const legacyTools = ["read", "grep", "find", "ls"];
  const customTools = ["read", "ls"];
  writeFileSync(path, JSON.stringify({
    theme: "custom",
    subagents: {
      agentOverrides: {
        scout: { tools: legacyTools, thinking: "low" },
        reviewer: { tools: legacyTools },
        oracle: { tools: customTools },
        custom: { tools: legacyTools },
      },
    },
  }));
  install();
  assert.deepEqual(JSON.parse(readFileSync(path)), {
    theme: "custom",
    subagents: {
      ...defaults,
      agentOverrides: {
        ...defaults.agentOverrides,
        scout: { ...defaults.agentOverrides.scout, tools: [...legacyTools, "bash"], thinking: "low" },
        reviewer: { ...defaults.agentOverrides.reviewer, tools: [...legacyTools, "bash"] },
        oracle: { ...defaults.agentOverrides.oracle, tools: customTools },
        custom: { tools: legacyTools },
      },
    },
  });
  const inode = statSync(path).ino;
  install();
  assert.equal(statSync(path).ino, inode, "an unchanged file should not be replaced");
});
