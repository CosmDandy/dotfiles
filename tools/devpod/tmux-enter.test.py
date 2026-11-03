import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class TmuxEnterTest(unittest.TestCase):
    def test_new_and_existing_sessions(self):
        script = Path(__file__).with_name('tmux-enter.sh').resolve()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tmux = root / 'tmux'
            tmux.write_text(
                '#!/bin/sh\n'
                'printf "%s\\n" "$*" >> "$TMUX_TEST_LOG"\n'
                'if [ "$1" = has-session ]; then exit "$TMUX_TEST_EXISTS"; fi\n'
            )
            tmux.chmod(0o700)
            for exists in (False, True):
                with self.subTest(exists=exists):
                    log = root / ('existing.log' if exists else 'new.log')
                    env = dict(
                        os.environ, PATH=directory + os.pathsep + os.environ['PATH'],
                        TERM='xterm-256color', TMUX_TEST_LOG=str(log),
                        TMUX_TEST_EXISTS='0' if exists else '1',
                    )
                    subprocess.run(['sh', str(script), 'test'], env=env, check=True)
                    commands = log.read_text().splitlines()
                    self.assertEqual(commands[-1], 'attach -t test')
                    if exists:
                        self.assertEqual(commands, ['has-session -t test', 'attach -t test'])
                    else:
                        self.assertIn('new-session -d -s test', commands)
                        self.assertEqual(commands.count('new-window -t test:'), 2)
                        self.assertIn('send-keys -t test:1 nvim C-m', commands)
                        self.assertIn('send-keys -t test:2 opencode C-m', commands)
                        self.assertIn('select-window -t test:1', commands)
                    self.assertNotIn('claude', log.read_text())


if __name__ == '__main__':
    unittest.main()
