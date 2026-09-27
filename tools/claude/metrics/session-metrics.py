#!/usr/bin/env python3
"""Mechanical CLAUDE.md-compliance metrics for Claude Code session transcripts.

Every metric here is checkable without a model (the IFEval idea: verifiable
constraints, precision counted), so the numbers are comparable across models and
across weeks. Tone and "one idea per line" need a judge and live elsewhere.

    session-metrics.py [--jsonl OUT] [--summary] TRANSCRIPT.jsonl ...

One row per transcript; `--summary` adds a per-model mean table on stderr-free
stdout. Rows are JSON so a cron on the devpod can append them to a weekly file.

Metric -> the CLAUDE.md line it checks:
  report_lines             any report — 20 lines; past that it is a replay
  report_blocks            ✔ ✘ ! ? » labels present in the final report
  chat_ru_share            Russian — everything addressed to me
  commits, commits_en      English — commits
  code_fences              code in chat only when the shape is new to this repo
  ask_user_question        your questions — plain text, never AskUserQuestion
  questions_before_work    ask only when stuck (questions before the first tool)
  heredoc_writes           we use Edit; generated files are written by scripts,
                           not `cat > file <<EOF` from the shell
  sed_i                    mass mechanical edits go through sed (informational)
  read_full                Read without offset and limit (always offset+limit)
  hook_denials, denials    harness refusals: what the guard had to stop
  errors                   tool results flagged is_error
  repeat_commands          the same Bash command run again verbatim
  single_call_share        share of tool turns with exactly one call (batching)
  ctx_peak_k, out_k        peak context and total output, thousands of tokens
  turn_min                 sum of turn_duration records (model + tools), minutes
  compactions              compact_boundary records
  final_signal             result:/needs input:/failed: in the final message
                           (job-list convention for unattended runs)
"""

import argparse
import json
import re
import statistics
import sys
from collections import Counter

CYRILLIC = re.compile(r"[а-яё]", re.IGNORECASE)
LATIN = re.compile(r"[a-z]", re.IGNORECASE)
FENCE = re.compile(r"^```", re.MULTILINE)
BLOCK_LABELS = ("✔", "✘", "!", "?", "»")
FINAL_SIGNAL = re.compile(
    r"^\s*(result|needs input|failed):", re.IGNORECASE | re.MULTILINE
)
COMMIT_MSG = re.compile(
    r"git\b[^|;&]*?\bcommit\b[^|;&]*?-m\s+(['\"])(.*?)\1", re.DOTALL
)
HEREDOC_WRITE = re.compile(
    r"(cat|tee)\s*(>{1,2}|-a)?\s*\S*\s*<<|<<\s*-?['\"]?\w+['\"]?[^\n]*>\s*\S"
)
ECHO_WRITE = re.compile(r"^\s*(echo|printf)\b[^|]*>{1,2}\s*\S", re.MULTILINE)
SED_I = re.compile(r"\bsed\s+(-[a-zA-Z]*i|--in-place)")
# A denied permission-rule result carries the hook's own reason as its text; the
# harness's "Permission to use X ... has been denied" is an ask nobody granted.
ASK_DENIED = "Permission to use "
MIN_TEXT = 40


def blocks(rec):
    content = rec.get("message", {}).get("content")
    if isinstance(content, list):
        return content
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    return []


def is_russian(text):
    cyr = len(CYRILLIC.findall(text))
    lat = len(LATIN.findall(text))
    return cyr + lat >= 10 and cyr > lat


def result_text(block):
    content = block.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(
            part.get("text", "") for part in content if isinstance(part, dict)
        )
    return ""


def analyze(path):
    m = {
        "sid": "",
        "model": "",
        "started": "",
        "human_turns": 0,
        "assistant_msgs": 0,
        "tool_calls": 0,
        "report_lines": 0,
        "report_blocks": 0,
        "chat_ru_share": None,
        "commits": 0,
        "commits_en": 0,
        "code_fences": 0,
        "ask_user_question": 0,
        "questions_before_work": 0,
        "heredoc_writes": 0,
        "sed_i": 0,
        "read_full": 0,
        "hook_denials": 0,
        "denials": 0,
        "errors": 0,
        "repeat_commands": 0,
        "single_call_share": None,
        "ctx_peak_k": 0,
        "out_k": 0,
        "turn_min": 0.0,
        "compactions": 0,
        "final_signal": False,
    }
    models = Counter()
    texts_ru = []
    tool_turns = []
    per_msg = {}
    bash_cmds = Counter()
    last_text = ""
    seen_tool = False
    turn_ms = 0

    with open(path, encoding="utf-8") as fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("isSidechain"):
                continue
            kind = rec.get("type")
            if not m["sid"]:
                m["sid"] = (rec.get("sessionId") or "")[:8]
            if kind == "system":
                sub = rec.get("subtype")
                if sub == "compact_boundary":
                    m["compactions"] += 1
                elif sub == "turn_duration":
                    turn_ms += rec.get("durationMs") or 0
                continue
            if kind == "user":
                content = blocks(rec)
                if content and content[0].get("type") != "tool_result":
                    # isMeta and "<…>" strings are harness injections (goal
                    # check-ins, task notifications); the compaction summary is
                    # "This session is being continued…". None of them is a person.
                    first = content[0].get("text", "").lstrip()
                    if not rec.get("isMeta") and not first.startswith(
                        ("<", "This session is being continued")
                    ):
                        m["human_turns"] += 1
                        if not m["started"]:
                            m["started"] = rec.get("timestamp", "")
                denial = rec.get("toolDenialKind")
                if denial:
                    m["denials"] += 1
                for b in content:
                    if b.get("type") != "tool_result" or not b.get("is_error"):
                        continue
                    m["errors"] += 1
                    text = result_text(b)
                    if denial == "permission-rule" and not text.startswith(ASK_DENIED):
                        m["hook_denials"] += 1
                continue
            if kind != "assistant":
                continue

            # One API message is streamed as several records sharing message.id
            # (one per content block), each carrying the whole message's usage:
            # count calls and tokens per id, not per record.
            msg = rec.get("message", {})
            mid = msg.get("id") or rec.get("uuid") or str(len(per_msg))
            entry = per_msg.setdefault(mid, {"calls": 0, "usage": {}})
            entry["usage"] = msg.get("usage") or entry["usage"]
            models[msg.get("model", "")] += 1

            calls = 0
            for b in blocks(rec):
                t = b.get("type")
                if t == "text":
                    text = b.get("text", "")
                    if not text.strip():
                        continue
                    last_text = text
                    if len(text) >= MIN_TEXT:
                        texts_ru.append(is_russian(text))
                    m["code_fences"] += len(FENCE.findall(text)) // 2
                    if not seen_tool and text.rstrip().endswith("?"):
                        m["questions_before_work"] += 1
                elif t == "tool_use":
                    calls += 1
                    seen_tool = True
                    name = b.get("name", "")
                    inp = b.get("input") or {}
                    if name == "AskUserQuestion":
                        m["ask_user_question"] += 1
                    elif name == "Read":
                        if "offset" not in inp and "limit" not in inp:
                            m["read_full"] += 1
                    elif name == "Bash":
                        cmd = inp.get("command", "")
                        bash_cmds[cmd.strip()] += 1
                        if HEREDOC_WRITE.search(cmd) or ECHO_WRITE.search(cmd):
                            m["heredoc_writes"] += 1
                        if SED_I.search(cmd):
                            m["sed_i"] += 1
                        for _, msg_text in COMMIT_MSG.findall(cmd):
                            m["commits"] += 1
                            if not CYRILLIC.search(msg_text):
                                m["commits_en"] += 1
            entry["calls"] += calls
            m["tool_calls"] += calls

    m["assistant_msgs"] = len(per_msg)
    for entry in per_msg.values():
        usage = entry["usage"]
        ctx = (
            (usage.get("input_tokens") or 0)
            + (usage.get("cache_read_input_tokens") or 0)
            + (usage.get("cache_creation_input_tokens") or 0)
        )
        m["ctx_peak_k"] = max(m["ctx_peak_k"], ctx // 1000)
        m["out_k"] += usage.get("output_tokens") or 0
        if entry["calls"]:
            tool_turns.append(entry["calls"])

    m["model"] = models.most_common(1)[0][0] if models else ""
    m["report_lines"] = len([ln for ln in last_text.splitlines() if ln.strip()])
    m["report_blocks"] = sum(1 for lab in BLOCK_LABELS if f"{lab} " in last_text)
    m["final_signal"] = bool(FINAL_SIGNAL.search(last_text))
    if texts_ru:
        m["chat_ru_share"] = round(sum(texts_ru) / len(texts_ru), 2)
    if tool_turns:
        m["single_call_share"] = round(
            sum(1 for c in tool_turns if c == 1) / len(tool_turns), 2
        )
    m["repeat_commands"] = sum(n - 1 for n in bash_cmds.values() if n > 1)
    m["out_k"] //= 1000
    m["turn_min"] = round(turn_ms / 60000, 1)
    return m


COLUMNS = (
    "sid model human_turns tool_calls report_lines report_blocks chat_ru_share "
    "commits_en commits code_fences ask_user_question questions_before_work "
    "heredoc_writes read_full hook_denials errors repeat_commands "
    "single_call_share ctx_peak_k out_k turn_min compactions final_signal"
).split()

NUMERIC = [
    c
    for c in COLUMNS
    if c not in ("sid", "model", "final_signal")
]


def fmt(v):
    if v is None:
        return "-"
    if isinstance(v, bool):
        return "y" if v else "n"
    return str(v)


def print_table(rows, cols):
    print("\t".join(cols))
    for r in rows:
        print("\t".join(fmt(r.get(c)) for c in cols))


def summary(rows):
    by_model = {}
    for r in rows:
        by_model.setdefault(r["model"] or "?", []).append(r)
    out = []
    for model, group in sorted(by_model.items()):
        s = {"model": model, "sessions": len(group)}
        for c in NUMERIC:
            vals = [r[c] for r in group if r.get(c) is not None]
            s[c] = round(statistics.mean(vals), 2) if vals else None
        s["final_signal"] = round(
            sum(1 for r in group if r["final_signal"]) / len(group), 2
        )
        out.append(s)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("transcripts", nargs="+")
    ap.add_argument("--jsonl", help="append one JSON row per session to this file")
    ap.add_argument("--summary", action="store_true", help="per-model means")
    args = ap.parse_args(argv)

    rows = [analyze(p) for p in args.transcripts]
    if args.jsonl:
        with open(args.jsonl, "a", encoding="utf-8") as fh:
            for r in rows:
                fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    print_table(rows, COLUMNS)
    if args.summary:
        print()
        print_table(summary(rows), ["model", "sessions", *NUMERIC, "final_signal"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
