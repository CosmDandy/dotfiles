#!/usr/bin/env python3
"""Build reader samples (H1 interstitial texts, H2 reports, H4 worktrees) from the
transcript list. Standalone: re-walks the files with the same turn segmentation as
session-metrics.py (imported for its regexes and helpers).

Usage: extract-samples.py <files.txt> <outdir>
  files.txt — one transcript path per line (the research/autonomy-audit sample list)
  outdir    — receives h1-sample.jsonl, h2-sample.jsonl, h4-worktrees.jsonl
The seed is fixed so the 2026-10 audit samples come out identical on a re-run."""

import importlib.util
import json
import os
import random
import sys

SM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "session-metrics.py")
spec = importlib.util.spec_from_file_location("sm", SM)
sm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sm)

# NOTE: the audit sessions themselves (2026-10 research run) are excluded so the
# readers never rate the session that briefed them.
EXCLUDE_SIDS = {"899e9f87", "01908811", "687aba92"}
random.seed(20261029)


def tool_label(name, inp):
    if name == "Bash":
        return "Bash: " + (inp.get("command") or "").strip().replace("\n", " ⏎ ")[:140]
    if name in ("Edit", "Write", "Read", "MultiEdit", "NotebookEdit"):
        return f"{name}: {inp.get('file_path', '')}"
    if name == "Agent":
        desc = (inp.get("description") or "")[:80]
        return f"Agent({inp.get('subagent_type', '')}): {desc}"
    if name == "Grep":
        return f"Grep: {inp.get('pattern', '')} in {inp.get('path', '')}"
    if name == "Skill":
        return f"Skill: {inp.get('skill', '')}"
    return name


def walk(path):
    project, in_wt = sm.project_of(path)
    turns = []
    turn = None
    sid = ""
    model = ""
    for lineno, line in enumerate(open(path, encoding="utf-8"), 1):
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if rec.get("isSidechain"):
            continue
        if not sid:
            sid = (rec.get("sessionId") or "")[:8]
        kind = rec.get("type")
        if kind == "user":
            content = sm.blocks(rec)
            if content and content[0].get("type") != "tool_result":
                first = content[0].get("text", "").lstrip()
                origin = (rec.get("origin") or {}).get("kind", "human")
                if first.startswith(sm.INTERRUPT):
                    if turn:
                        turn["interrupted"] = True
                elif (
                    origin == "human"
                    and not rec.get("isMeta")
                    and not first.startswith(("<", "This session is being continued"))
                ):
                    if turn:
                        turn["next_owner"] = first[:300]
                    turn = {
                        "line": lineno,
                        "end": lineno,
                        "ts": rec.get("timestamp", ""),
                        "prompt": first[:400],
                        "texts": [],
                        "trace": [],
                        "interrupted": False,
                        "next_owner": None,
                    }
                    turns.append(turn)
                continue
            if turn:
                turn["end"] = lineno
            continue
        if kind != "assistant":
            continue
        msg = rec.get("message", {})
        if not model and msg.get("model"):
            model = msg["model"]
        if turn is None:
            turn = {
                "line": lineno,
                "end": lineno,
                "ts": rec.get("timestamp", ""),
                "prompt": "",
                "texts": [],
                "trace": [],
                "interrupted": False,
                "next_owner": None,
            }
            turns.append(turn)
        turn["end"] = lineno
        for b in sm.blocks(rec):
            t = b.get("type")
            if t == "text" and b.get("text", "").strip():
                turn["texts"].append(
                    {
                        "line": lineno,
                        "text": b["text"],
                        "after_tools": len(turn["trace"]),
                        "followed": False,
                    }
                )
            elif t == "tool_use":
                for tx in turn["texts"]:
                    tx["followed"] = True
                turn["trace"].append(
                    (lineno, tool_label(b.get("name", ""), b.get("input") or {}))
                )
    return sid, project, in_wt, model, turns


def main(listfile, outdir):
    h1, h2, h4 = [], [], []
    for path in open(listfile).read().split():
        sid, project, in_wt, model, turns = walk(path)
        if sid in EXCLUDE_SIDS or model in ("", "<synthetic>"):
            continue
        git_trace = []
        for ti, t in enumerate(turns):
            final = [tx for tx in t["texts"] if not tx["followed"]]
            final_text = "\n".join(tx["text"] for tx in final)
            inter = [
                tx
                for tx in t["texts"]
                if tx["followed"]
                and not (tx["after_tools"] == 0 and tx is t["texts"][0])
            ]
            for tx in inter:
                h1.append(
                    {
                        "project": project,
                        "model": model,
                        "sid": sid,
                        "line": tx["line"],
                        "prompt": t["prompt"][:200],
                        "tools_before": tx["after_tools"],
                        "tools_total": len(t["trace"]),
                        "text": tx["text"][:1500],
                    }
                )
            lines = sm.nonblank_lines(final_text)
            files = sorted(
                {
                    lbl.split(": ", 1)[1].rsplit("/", 1)[-1]
                    for _, lbl in t["trace"]
                    if lbl.startswith(("Edit: ", "Write: ")) and ": " in lbl
                }
            )
            missing = [f for f in files if f and f not in final_text]
            ended_q = bool(lines) and lines[-1].rstrip().endswith("?")
            if (
                t["trace"]
                and final_text
                and (len(lines) > 20 or len(missing) >= 2 or ended_q)
            ):
                h2.append(
                    {
                        "project": project,
                        "model": model,
                        "sid": sid,
                        "lines": [t["line"], t["end"]],
                        "prompt": t["prompt"],
                        "trace": [lbl for _, lbl in t["trace"]][:80],
                        "trace_total": len(t["trace"]),
                        "edited_files": files,
                        "missing": missing,
                        "report_lines": len(lines),
                        "ended_q": ended_q,
                        "interrupted": t["interrupted"],
                        "report": final_text[:7000],
                        "next_owner": t["next_owner"],
                    }
                )
            for ln, lbl in t["trace"]:
                if lbl.startswith(("EnterWorktree", "ExitWorktree")) or (
                    lbl.startswith("Bash: ")
                    and (
                        "worktree" in lbl
                        or "git branch" in lbl
                        or "switch -c" in lbl
                        or "checkout -b" in lbl
                        or "git merge" in lbl
                        or "git push" in lbl
                    )
                ):
                    git_trace.append({"turn": ti, "line": ln, "cmd": lbl})
        if git_trace or in_wt:
            h4.append(
                {
                    "project": project,
                    "model": model,
                    "sid": sid,
                    "in_worktree": in_wt,
                    "turns": len(turns),
                    "first_prompt": turns[0]["prompt"][:300] if turns else "",
                    "git_trace": git_trace,
                    "last_report": "\n".join(
                        tx["text"] for tx in turns[-1]["texts"] if not tx["followed"]
                    )[:1500]
                    if turns
                    else "",
                }
            )

    def stratified(items, n, key):
        groups = {}
        for it in items:
            groups.setdefault(key(it), []).append(it)
        out = []
        per = max(1, n // len(groups)) if groups else 0
        for g in groups.values():
            random.shuffle(g)
            out.extend(g[:per])
        random.shuffle(out)
        return out[:n]

    h1s = stratified(h1, 40, lambda it: (it["project"], it["model"]))
    h2s = stratified(h2, 30, lambda it: (it["project"], it["model"]))
    for i, it in enumerate(h1s, 1):
        it["id"] = f"T{i:02d}"
    for i, it in enumerate(h2s, 1):
        it["id"] = f"R{i:02d}"
    for name, data in (("h1-sample", h1s), ("h2-sample", h2s), ("h4-worktrees", h4)):
        with open(f"{outdir}/{name}.jsonl", "w", encoding="utf-8") as fh:
            for it in data:
                fh.write(json.dumps(it, ensure_ascii=False) + "\n")
    print(
        f"h1 pool {len(h1)} -> {len(h1s)}; h2 pool {len(h2)} -> {len(h2s)}; "
        f"h4 sessions {len(h4)}"
    )


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
