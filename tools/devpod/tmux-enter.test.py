import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("tmux-enter.sh").resolve()


class TmuxEnterTest(unittest.TestCase):
    def run_script(self, *args, exists=False, tmux_env="", agent_env=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tmux = root / "tmux"
            tmux.write_text(
                "#!/bin/sh\n"
                'printf "%s\\n" "$*" >> "$TMUX_TEST_LOG"\n'
                'if [ "$1" = has-session ]; then exit "$TMUX_TEST_EXISTS"; fi\n'
                'if [ "$1" = new-session ]; then\n'
                '  echo "cwd $(pwd -P)" >> "$TMUX_TEST_LOG"\n'
                "fi\n"
            )
            tmux.chmod(0o700)
            log = root / "log"
            env = dict(
                os.environ,
                PATH=directory + os.pathsep + os.environ["PATH"],
                TERM="xterm-256color",
                TMUX_TEST_LOG=str(log),
                TMUX=tmux_env,
                TMUX_TEST_EXISTS="0" if exists else "1",
                HOME=directory,
            )
            env.pop("WORKSPACE_AGENT", None)
            if agent_env is not None:
                env["WORKSPACE_AGENT"] = agent_env
            result = subprocess.run(
                ["sh", str(SCRIPT), *args], env=env, capture_output=True, text=True
            )
            return result, log.read_text().splitlines() if log.exists() else []

    def test_existing_session_is_attached_untouched(self):
        _, commands = self.run_script("test", exists=True)
        self.assertEqual(commands, ["has-session -t test", "attach -t test"])

    def test_existing_session_from_inside_tmux_switches(self):
        _, commands = self.run_script("test", exists=True, tmux_env="x")
        self.assertEqual(
            commands,
            ["has-session -t test", "switch-client -t test", "refresh-client -S"],
        )

    def test_template(self):
        _, commands = self.run_script("test")
        self.assertIn("new-session -d -s test", commands)
        self.assertEqual(commands.count("new-window -t test:"), 2)
        self.assertIn("send-keys -t test:1 nvim C-m", commands)
        self.assertIn("select-window -t test:1", commands)
        self.assertEqual(commands[-1], "attach -t test")

    def test_default_agent_is_claude_after_ide_lock(self):
        _, commands = self.run_script("test")
        agent = [c for c in commands if c.startswith("send-keys -t test:2 ")][0]
        self.assertIn(".claude/ide", agent)
        self.assertTrue(agent.endswith("&& cl C-m"), agent)

    def test_agent_from_env_and_argument(self):
        for args, env, expected in (
            (("test",), "opencode", "opencode"),
            (("test", "", "pi"), "opencode", "pi"),
        ):
            with self.subTest(args=args, env=env):
                _, commands = self.run_script(*args, agent_env=env)
                self.assertIn(f"send-keys -t test:2 {expected} C-m", commands)
                self.assertNotIn("claude", "\n".join(commands))

    def test_unknown_agent_is_refused_before_tmux(self):
        result, commands = self.run_script("test", "", "vim")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(commands, [])

    def test_directory_becomes_the_session_directory(self):
        with tempfile.TemporaryDirectory() as work:
            result, commands = self.run_script("test", work, "pi")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(f"cwd {Path(work).resolve()}", commands)


if __name__ == "__main__":
    unittest.main()
