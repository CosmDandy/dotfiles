import copy
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SolarizedThemeTest(unittest.TestCase):
    def setUp(self):
        self.theme = json.loads((ROOT / 'themes/solarized-transparent.json').read_text())

    def resolve(self, value, tokens, seen=()):
        if not value.startswith('$'):
            self.assertTrue(value == 'transparent' or re.fullmatch(r'#[0-9a-f]{6}', value))
            return value
        self.assertNotIn(value, seen)
        node = tokens
        for key in value[1:].split('.'):
            if isinstance(node, str):
                node = self.lookup(node, tokens)
            node = node[key]
        return self.resolve(node, tokens, (*seen, value))

    def lookup(self, value, tokens):
        node = tokens
        for key in value[1:].split('.'):
            node = node[key]
        return node

    def test_colors_and_references_in_both_modes(self):
        for mode, background in [('light', '#eee8d5'), ('dark', '#073642')]:
            with self.subTest(mode=mode):
                tokens = copy.deepcopy(self.theme['base'])
                tokens.update(self.theme[mode])
                def check(node, path=()):
                    if isinstance(node, dict):
                        for key, value in node.items():
                            check(value, (*path, key))
                    elif isinstance(node, str):
                        if len(path) == 2 and path[0] == 'hue':
                            self.assertIsInstance(self.lookup(node, tokens), dict)
                        else:
                            self.resolve(node, tokens)
                check(tokens)
                self.assertEqual(tokens['background']['base'], 'transparent')
                self.assertEqual(self.resolve('$background.formfield.base', tokens), background)
                self.assertEqual(self.resolve('$background.raised.high', tokens), background)
                for hue in ['gray', 'red', 'orange', 'yellow', 'green', 'cyan', 'blue', 'purple']:
                    self.assertEqual(set(tokens['hue'][hue]), {str(n) for n in range(100, 1000, 100)})

    def test_selected_theme_and_nix_link(self):
        config = json.loads((ROOT / 'cli.json').read_text())
        self.assertEqual(config['theme'], {'name': 'solarized-transparent', 'mode': 'system'})
        nix = ' '.join((ROOT.parents[1] / 'platform/nix/home/files.nix').read_text().split())
        self.assertIn('"opencode/cli.json".source = link "tools/opencode/cli.json";', nix)
        self.assertIn('"opencode/themes/solarized-transparent.json".source = link "tools/opencode/themes/solarized-transparent.json";', nix)

    def test_syntax_and_markdown_use_hue_references(self):
        # OpenCode 2.1.4 restricts these groups to hex colors or hue-step references.
        for group in ['syntax', 'markdown']:
            for value in self.theme['base'][group].values():
                self.assertRegex(value, r'^(#[0-9a-f]{6}|\$hue\..+\.[1-9]00)$')


if __name__ == '__main__':
    unittest.main()
