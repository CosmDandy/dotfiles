"""Paired warm startup and first /agents measurements; no model requests."""

import argparse
import json
import os
from pathlib import Path
import select
import statistics
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("before", type=Path, help="stock lib/node_modules")
parser.add_argument("after", type=Path, help="candidate lib/node_modules")
parser.add_argument("--pi", required=True)
parser.add_argument("--pairs", type=int, default=9)
args = parser.parse_args()
source = Path(__file__).resolve().parents[1]

def wait_for(fd, needle):
    seen = b""
    deadline = time.monotonic() + 10
    while not any(needle in line for line in seen.split(b"\n")[:-1]):
        timeout = deadline - time.monotonic()
        if timeout <= 0 or not select.select([fd], [], [], timeout)[0]:
            raise TimeoutError(f"{needle!r} did not appear: {seen[-400:]!r}")
        data = os.read(fd, 65536)
        if not data:
            raise RuntimeError(f"EOF before {needle!r}: {seen[-400:]!r}")
        seen = (seen + data)[-65536:]
    return seen

def trial(root, driver, env):
    argv = [args.pi, "--offline", "--no-mcp", "--no-session", "--no-extensions",
            "-e", str(source / "extensions/work-mode.ts"), "-e", str(root / "ready.ts")]
    t0 = time.perf_counter()
    ms = lambda: (time.perf_counter() - t0) * 1000
    if driver == "rpc":
        with subprocess.Popen([*argv, "--mode", "rpc"], cwd=root, env=env,
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as child:
            try:
                child.stdin.write(b'{"type":"get_state","id":"bench"}\n')
                child.stdin.flush()
                out = wait_for(child.stdout.fileno(), b'"id":"bench"')
                elapsed = ms()
                assert any(json.loads(line).get("success") for line in out.split(b"\n")[:-1] if b'"id":"bench"' in line)
                return [elapsed]
            finally:
                child.kill()
    def tmux(*cmd):
        return subprocess.check_output(["tmux", "-L", f"pi-perf-{os.getpid()}", "-f", "/dev/null", *cmd], timeout=5)
    def screen(needle):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            frame = tmux("capture-pane", "-p", "-t", pane)
            if needle in frame:
                return
            time.sleep(.01)
        raise TimeoutError(f"{needle!r} did not appear: {frame[-500:]!r}")
    pane = tmux("new-session", "-d", "-P", "-F", "#{pane_id}", "-c", str(root), "-x", "112", "-y", "40",
                "env", "-i", *(f"{k}={v}" for k,v in env.items()), *argv, "--tui-mode", "regular").decode().strip()
    try:
        screen(b"PERF_READY")
        ready = ms()
        tmux("send-keys", "-t", pane, "-l", "/agents")
        tmux("send-keys", "-t", pane, "Enter")
        screen(b"Subagent fleet inspector")
        menu = ms()
        return [menu, menu - ready]
    finally:
        tmux("kill-server")

with tempfile.TemporaryDirectory(prefix="pi-agent-startup-") as tmp:
    root = Path(tmp)
    agent = root / ".pi/agent"
    agent.mkdir(parents=True)
    (agent / "agents").symlink_to(source / "agents", target_is_directory=True)
    (root / "ready.ts").write_text('export default pi => pi.on("session_start", (_,ctx) => { if (ctx.mode === "tui") ctx.ui.setStatus("bench", "PERF_READY"); });')
    env = dict(HOME=tmp, PATH=os.environ["PATH"], PI_CODING_AGENT_DIR=str(agent), PI_TELEMETRY="0",
               PI_SUBAGENTS_TEMP_ROOT=str(root / "runs"), TERM="xterm-256color", TMPDIR=tmp)
    env["NODE_COMPILE_CACHE"] = str(root / "node-cache")
    for driver in ["rpc", "menu"]:
        samples = {k: [] for k in ["before", "after"]}
        for i in range(args.pairs + 1):
            for label in (["before", "after"] if i % 2 == 0 else ["after", "before"]):
                link = agent / "subagent-package"
                link.unlink(missing_ok=True)
                link.symlink_to(getattr(args, label).resolve(), target_is_directory=True)
                sample = trial(root, driver, env)
                if i:
                    samples[label].append(sample)
        for label, rows in samples.items():
            print(driver, label, "median ms:", [round(statistics.median(v), 1) for v in zip(*rows)],
                  "pairs:", args.pairs, flush=True)
