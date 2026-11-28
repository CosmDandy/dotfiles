import { createHash } from "node:crypto";

// Only batch ordinary modified files whose patch boundaries can be verified. The
// collector still runs the original per-path diff and must get exactly these bytes.
function batch(cwd, files, gitOutput) {
  // Stateful clean filters or text converters need not agree across invocations.
  // --all distinguishes a driver literally named "unspecified" from no attribute.
  const attrs = gitOutput(cwd, ["check-attr", "-z", "--all", "--", ...files]).split("\0");
  if (attrs.some((v, i) => i % 3 === 1 && (v === "filter" || v === "diff"))) return;
  const diff = gitOutput(cwd, ["diff", "--no-ext-diff", "--no-renames", "--raw", "-z", "-p", "--binary", "HEAD", "--", ...files]);
  const boundary = diff.indexOf("\0\0");
  if (boundary < 0) return;
  const raw = diff.slice(0, boundary).split("\0");
  if (raw.length !== 2 * files.length) return;
  const expected = new Set(files);
  const paths = [];
  for (let i = 0; i < raw.length; i += 2) {
    const file = raw[i + 1];
    if (!/^:100(?:644|755) 100(?:644|755) [0-9a-f]+ [0-9a-f]+ M$/.test(raw[i]) || !expected.delete(file)) return;
    paths.push(file);
  }
  const patch = diff.slice(boundary + 2);
  const starts = [...patch.matchAll(/^diff --git /gm)].map(m => m.index);
  if (starts.length !== paths.length || starts[0] !== 0) return;
  const result = [];
  for (const [i, file] of paths.entries()) {
    const part = patch.slice(starts[i], starts[i + 1]);
    if (!part.startsWith(`diff --git a/${file} b/${file}\n`)) return;
    result.push([file, { kind: "diff", digest: createHash("sha256").update(part).digest("hex") }]);
  }
  return result;
}

export function snapshotFingerprints(cwd, files, gitOutput, fingerprintPath) {
  const fingerprints = {};
  const simple = process.env.GIT_ICASE_PATHSPECS ? [] : files.filter(f => /^[a-zA-Z0-9_./ -]+$/.test(f));
  for (let i = 0; i < simple.length; i += 64) {
    const group = simple.slice(i, i + 64);
    if (group.length < 2) break;
    let parts;
    try { parts = batch(cwd, group, gitOutput); } catch { /* Large patches use the bounded per-file fallback. */ }
    if (parts) for (const [file, fp] of parts) fingerprints[file] = fp;
  }
  for (const file of files) {
    if (!Object.hasOwn(fingerprints, file)) fingerprints[file] = fingerprintPath(cwd, file);
  }
  return fingerprints;
}
