import assert from "node:assert/strict";
import { copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const liveAgentDir = join(homedir(), ".pi", "agent");
const modules = process.env.PI_TEST_MODULES ?? join(liveAgentDir, "install", "releases",
  readFileSync(join(liveAgentDir, "install", "current-version"), "utf8").trim(), "node_modules");
const load = path => import(pathToFileURL(join(modules, path)).href);
const { loadProjectContextFiles } = await load("@earendil-works/pi-coding-agent/dist/core/resource-loader.js");
const { loadSkills } = await load("@earendil-works/pi-coding-agent/dist/core/skills.js");
const { buildSystemPromptSections } = await load("@earendil-works/pi-coding-agent/dist/core/system-prompt.js");
const sourcePath = fileURLToPath(new URL("../AGENTS.md", import.meta.url));
const source = readFileSync(sourcePath, "utf8");
const skillNames = ["ops-metal", "ops-net", "ops-remote", "ops-vm"];
assert.ok(lstatSync(sourcePath).isFile());
assert.equal(lstatSync(sourcePath).isSymbolicLink(), false);
const sandbox = mkdtempSync(join(tmpdir(), "pi-instructions-"));
try {
  const agentDir = join(sandbox, "agent");
  const cwd = join(sandbox, "project");
  mkdirSync(agentDir);
  mkdirSync(cwd);
  const globalPath = join(agentDir, "AGENTS.md");
  copyFileSync(sourcePath, globalPath);
  let contexts = loadProjectContextFiles({ cwd, agentDir });
  assert.deepEqual(contexts, [{ path: globalPath, content: source }]);
  assert.equal(lstatSync(globalPath).isSymbolicLink(), false);
  writeFileSync(globalPath, source + "\nLocal Pi instructions only.\n");
  assert.equal(readFileSync(sourcePath, "utf8"), source, "local edits must not change the template");
  assert.match(loadProjectContextFiles({ cwd, agentDir })[0].content, /Local Pi instructions only/);

  const claudePath = join(agentDir, "CLAUDE.md");
  renameSync(globalPath, claudePath);
  assert.equal(loadProjectContextFiles({ cwd, agentDir })[0].path, claudePath, "Pi natively accepts CLAUDE.md too");
  renameSync(claudePath, globalPath);
  writeFileSync(join(cwd, "AGENTS.md"), "Lower-priority project instructions.");
  writeFileSync(join(cwd, "AGENTS.override.md"), "Project override instructions.");
  contexts = loadProjectContextFiles({ cwd, agentDir });
  assert.equal(contexts.length, 2);
  assert.equal(contexts[1].content, "Project override instructions.");
  const skills = loadSkills({ cwd, agentDir, skillPaths: [], includeDefaults: true });
  assert.deepEqual(skills.skills, []);
  const sections = buildSystemPromptSections({ cwd, contextFiles: contexts, skills: skills.skills });
  assert.match(sections.preamble, /coding assistant running inside pi/);
  assert.ok(sections.project_context.includes(readFileSync(globalPath, "utf8")), "the full file must reach the prompt");
  assert.equal(sections.addendum, undefined);
  assert.equal(sections.skills, undefined);

  const skillsDir = join(agentDir, "skills");
  mkdirSync(skillsDir);
  for (const name of skillNames) {
    symlinkSync(fileURLToPath(new URL(`../skills/${name}`, import.meta.url)), join(skillsDir, name));
  }
  const installed = loadSkills({ cwd, agentDir, skillPaths: [], includeDefaults: true });
  assert.deepEqual(installed.skills.map(skill => skill.name).sort(), skillNames);

  if (process.argv.includes("--live")) {
    const liveContexts = loadProjectContextFiles({ cwd: process.cwd(), agentDir: liveAgentDir });
    assert.equal(liveContexts[0].path, join(liveAgentDir, "AGENTS.md"));
    assert.equal(lstatSync(liveContexts[0].path).isSymbolicLink(), false);
    const live = loadSkills({ cwd: process.cwd(), agentDir: liveAgentDir, skillPaths: [], includeDefaults: true });
    for (const name of skillNames) assert.ok(live.skills.some(skill => skill.name === name), `missing skill: ${name}`);
    for (const name of ["CLAUDE.md", "APPEND_SYSTEM.md", "SYSTEM.md", "claude-rules"]) {
      assert.equal(existsSync(join(liveAgentDir, name)), false, `legacy resource remains: ${name}`);
    }
  }
  console.log("PASS: native AGENTS.md, project priority, standalone Pi skills and no addendum");
} finally {
  rmSync(sandbox, { recursive: true, force: true });
}
