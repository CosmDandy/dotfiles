"""Diagnostic: list the Claude Code system-prompt sections and what gates them.

Run on every client bump:
    uv run --no-project python3 tools/claude/metrics/prompt-sections.py [--binary PATH]

The binary is minified JS; names are mangled and change per build, so all lookups
go by string literals and a plain str.find, never by grep windows over long lines.
"""

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ASSEMBLY_ANCHORS = ("autonomy_append", "act_dont_rederive")
PHRASES = (
    "Your text output is what the user reads",
    "say in a line what you're about to do",
    "Before ending your turn, check your last paragraph",
    "make file changes with sed, heredocs",
    "While bypass permissions mode is active",
    "keep-coding-instructions",
    "stop_hook_active",
    "worktree.baseRef",
)


def find_binary(arg):
    path = arg or shutil.which("claude") or str(Path.home() / ".local/bin/claude")
    return Path(path).resolve()


def printable_runs(data, minlen=4):
    return b"\n".join(re.findall(rb"[\x20-\x7e\t]{%d,}" % minlen, data)).decode()


def load_strings(binary):
    try:
        out = subprocess.run(["strings", str(binary)], capture_output=True, check=True)
        return out.stdout.decode(errors="replace")
    except (OSError, subprocess.CalledProcessError):
        return printable_runs(binary.read_bytes())


def definition(text, name, near):
    """First `function name(` or `name=` definition at or before `near`, else after."""
    pat = re.compile(rf"(?:function {re.escape(name)}\(|[,;\s]{re.escape(name)}=)")
    hits = [
        m.start() for m in pat.finditer(text, max(0, near - 400_000), near + 400_000)
    ]
    if not hits:
        return None
    best = min(hits, key=lambda h: abs(h - near))
    return text[best : best + 200].replace("\n", " ")


def assembly_sections(text):
    """Entries of the form ng(`id...`,()=>body) in the prompt-assembly array."""
    anchor = max(text.rfind(a) for a in ASSEMBLY_ANCHORS)
    if anchor < 0:
        return anchor, []
    start = text.rfind("=[ng(", 0, anchor)
    chunk = text[start : text.find("],", anchor + 400)]
    pat = re.compile(
        r'ng\((?:`([a-z0-9_]+)(.{0,80}?)`|"([a-z0-9_]+)"()),\(\)=>(?=(.{0,400}))', re.S
    )
    return anchor, [
        (m.group(1) or m.group(3), m.group(2) or "", m.group(5))
        for m in pat.finditer(chunk)
    ]


def capability_table(text):
    rows = []
    for m in re.finditer(r'\{id:"(claude-[a-z0-9-]+)",family:"\w+"', text):
        nxt = text.find('{id:"claude-', m.end())
        seg = text[m.end() : nxt if nxt > 0 else m.end() + 6000]
        caps = re.search(r"capabilities:\[([^\]]*)\]", seg)
        if caps:
            rows.append((m.group(1), caps.group(1).replace('"', "")))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--binary")
    binary = find_binary(ap.parse_args().binary)
    text = load_strings(binary)
    version = subprocess.run([str(binary), "--version"], capture_output=True, text=True)
    print(
        f"binary:  {binary}\nversion: {version.stdout.strip()}\n"
        f"strings: {len(text):,} chars"
    )

    anchor, sections = assembly_sections(text)
    print(f"\n== assembly array near offset {anchor}: {len(sections)} sections ==")
    if not sections:
        print("NOT FOUND: anchors renamed; search the PHRASES below")
    for sid, suffix, body in sections:
        print(f"\n[{sid}{suffix}]\n  body:  {body[:200]!r}")
        for name in dict.fromkeys(re.findall(r"([A-Za-z_$][\w$]*)\(", body)):
            d = definition(text, name, anchor)
            if d:
                print(f"  gate:  {name} -> {d[:200]!r}")
        flags = re.findall(r'"((?:tengu_)?[a-z0-9_]{5,})"', body)
        if flags:
            print(f"  flags: {sorted(set(flags))}")

    print("\n== model capabilities (per-model prompt gates) ==")
    for model, caps in capability_table(text):
        gates = [
            c
            for c in caps.split(",")
            if "bundle" in c or c in ("lean_prompt", "fable_5_mitigations")
        ]
        print(f"  {model:22} {','.join(gates) or '-'}")

    print("\n== phrase anchors (offset: context) ==")
    for phrase in PHRASES:
        offs = [m.start() for m in re.finditer(re.escape(phrase), text)]
        print(f"\n'{phrase}': {len(offs)} hits")
        for o in offs[:2]:
            print(f"  {o}: {text[max(0, o - 100) : o + 160]!r}")


if __name__ == "__main__":
    sys.exit(main())
