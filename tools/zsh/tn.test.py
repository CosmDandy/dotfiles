import os
from pathlib import Path
import subprocess
import unittest


class TnTest(unittest.TestCase):
    def test_tmux_layout_and_client_selection(self):
        source = Path(__file__).with_name('.zshrc').read_text()
        function = 'tn() {' + source.split('tn() {', 1)[1].split('\n}', 1)[0] + '\n}'
        for attached in (False, True):
            with self.subTest(attached=attached):
                env = dict(os.environ, TMUX='test' if attached else '')
                script = "tmux() { print -r -- \"${(j: :)@}\"; }\n" + function + '\ntn .test.name'
                result = subprocess.run(
                    ['zsh', '-f', '-c', script], env=env,
                    capture_output=True, text=True, check=True,
                )
                commands = result.stdout.splitlines()
                self.assertIn('send-keys -t test-name:1 nvim C-m', commands)
                self.assertIn('send-keys -t test-name:2 opencode C-m', commands)
                self.assertEqual(sum(c.startswith('new-window ') for c in commands), 2)
                self.assertIn('select-window -t test-name:1', commands)
                if attached:
                    self.assertIn('switch-client -t test-name', commands)
                    self.assertIn('refresh-client -S', commands)
                else:
                    self.assertIn('attach -t test-name', commands)
                self.assertNotIn('claude', result.stdout)
                self.assertNotIn('find ', result.stdout)


if __name__ == '__main__':
    unittest.main()
