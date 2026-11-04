import subprocess
import unittest
from pathlib import Path


class TnTest(unittest.TestCase):
    def test_delegates_to_the_shared_template(self):
        source = Path(__file__).with_name(".zshrc").read_text()
        function = "tn() {" + source.split("tn() {", 1)[1].split("\n}", 1)[0] + "\n}"
        # The script path is replaced with a stub that prints its arguments.
        function = function.replace(
            '"$DOTFILES_DIR/tools/devpod/tmux-enter.sh"', "print -r --"
        )
        result = subprocess.run(
            ["zsh", "-f", "-c", function + "\ncd /tmp && tn .test.name"],
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertEqual(result.stdout.split(), ["test-name", "/tmp"])


if __name__ == "__main__":
    unittest.main()
