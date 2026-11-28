import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const root = join(process.env.PI_TEST_SUBAGENTS, "pi-subagents");
const sources = await Promise.all(["src/runs/shared/mutation-evidence.js", "bundle/chunk-2LEBXCLU.js"].map(p => import(pathToFileURL(join(root, p)))));
const tmp = mkdtempSync(join(tmpdir(), "pi-fingerprints-"));
const cwd = join(tmp, "repo"), trace = join(tmp, "trace");
mkdirSync(cwd);
process.env.GIT_CONFIG_GLOBAL = "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";
const git = (args, dir = cwd) => execFileSync("git", ["-c", "core.fsmonitor=false", ...args], { cwd: dir, maxBuffer: 8 << 20 });
const put = (name, data) => writeFileSync(join(cwd, name), data);
function reference(dir = cwd) {
  const paths = git(["diff", "--no-ext-diff", "--name-only", "-z", "HEAD", "--"], dir).toString().split("\0").filter(Boolean);
  const dirtyFiles = paths.slice(0, 500);
  const fingerprints = Object.fromEntries(dirtyFiles.map(file => {
    const bytes = git(["diff", "--no-ext-diff", "--binary", "HEAD", "--", file], dir);
    const digest = createHash("sha256").update(bytes.length > 1 << 20 ? bytes : bytes.toString()).digest("hex");
    return [file, { kind: "diff", digest }];
  }));
  return { source: "tracked-files", trackedOnly: true, cwd: dir, dirtyFiles, fingerprints, truncated: paths.length > 500 };
}
function parity(dir = cwd) {
  const expected = reference(dir);
  for (const m of sources) assert.deepEqual(m.snapshotTrackedMutations(dir), expected);
  return expected;
}
function gitCount(run) {
  writeFileSync(trace, "");
  process.env.GIT_TRACE2_EVENT = trace;
  try { run(); } finally { delete process.env.GIT_TRACE2_EVENT; }
  return readFileSync(trace, "utf8").trim().split("\n").map(JSON.parse).filter(e => e.event === "start").length;
}
try {
  git(["init", "-q"]);
  assert.ok(sources[0].snapshotTrackedMutations(cwd).unavailable);
  const normal = Array.from({ length: 501 }, (_, i) => "n" + String(i).padStart(3, "0"));
  const odd = ["filea", "file[ab]", "tab\tname", "line\nbreak", "файл", "with space", "binary", "old", "mode"];
  mkdirSync(join(cwd, "nested"));
  for (const file of [...normal, ...odd, "nested/text"]) put(file, file + "\n");
  symlinkSync(normal[0], join(cwd, "link"));
  git(["add", "--", ...normal, ...odd.filter(f => !f.includes("[")), ":(literal)file[ab]", "nested/text", "link"]);
  git(["-c", "user.name=Probe", "-c", "user.email=a@example.invalid", "-c", "core.hooksPath=/dev/null", "commit", "--no-gpg-sign", "-qm", "fixture"]);
  put("untracked", "ignored");
  for (const count of [0, 1, 32, 128, 501]) {
    for (const file of normal.slice(0, count)) put(file, "edited " + file);
    const snapshot = parity();
    for (const m of sources) assert.equal(gitCount(() => m.snapshotTrackedMutations(cwd)),
      count < 2 ? 1 + count : 1 + 2 * Math.ceil(snapshot.dirtyFiles.length / 64), "bounded Git processes: " + count);
    if (process.argv.includes("--bench") && count < 501) {
      const median = f => Array.from({ length: 5 }, () => {
        const start = performance.now(); f(cwd); return performance.now() - start;
      }).sort((a,b) => a-b)[2].toFixed(1);
      console.log(`${count} dirty: old ${median(reference)} ms, patched ${median(sources[0].snapshotTrackedMutations)} ms (n=5)`);
    }
  }
  git(["reset", "--hard", "-q", "HEAD"]);
  put("n001", "a"); put("n002", "b"); put(".gitattributes", "n* diff=unspecified\n");
  for (const m of sources) assert.equal(gitCount(() => m.snapshotTrackedMutations(cwd)), 4, "named driver uses individual diffs");
  rmSync(join(cwd, ".gitattributes"));
  put("n001", "first child baseline"); put("n002", "foreign"); put("n003", "foreign");
  const first = parity();
  put("n001", "second child baseline");
  const second = parity();
  put("n003", "n003\n"); put("n004", "newly dirty");
  for (const m of sources) {
    assert.deepEqual((await m.collectTrackedMutationEvidence(first)).changedFiles, ["n001", "n003", "n004"]);
    assert.deepEqual((await m.collectTrackedMutationEvidence(second)).changedFiles, ["n003", "n004"]);
  }
  for (const f of odd.slice(0, 6)) put(f, "new " + f);
  put("binary", Buffer.from([0, 255, 0, 1]));
  put("nested/text", "different");
  chmodSync(join(cwd, "mode"), 0o755);
  git(["mv", "old", "rename"]);
  rmSync(join(cwd, "link")); symlinkSync("mode", join(cwd, "link"));
  parity(); parity(join(cwd, "nested"));
  git(["config", "diff.noprefix", "true"]); parity();
  put(".gitattributes", "n001 diff\nn002 diff\n");
  put("n001", Buffer.from([0xfe, 65]));
  put("n002", Buffer.alloc((1 << 20) + 100, 0xfe));
  const unusual = parity();
  for (const m of sources) assert.deepEqual((await m.collectTrackedMutationEvidence(unusual)).changedFiles, []);
  console.log("PASS: both runtimes, exact legacy hashes, bounded Git processes, independent child baselines, truncation and fallback");
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
