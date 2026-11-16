import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'tools/update/upd'
MOCK = '''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['UPD_LOG'], 'a') as out:
    out.write(json.dumps([name, *args]) + '\\n')
if os.environ.get('UPD_FAIL') == ' '.join([name, *args[:2]]):
    sys.exit(7)
if name == 'claude' and args[:2] == ['mcp', 'get']:
    sys.exit(1 if os.environ.get('MOCK_MCP_MISSING') else 0)
if name == 'sudo':
    sys.exit(0 if args == ['-v'] else subprocess.call(args))
if name == 'uname':
    print(os.environ['MOCK_OS'] if args in [[], ['-s']] else os.environ.get('MOCK_ARCH', 'x86_64'))
elif name == 'whoami':
    print('tester')
elif name == 'hostname':
    print('nixos-stand')
elif name == 'brew' and args[:1] == ['outdated']:
    print('ghostty\\nclaude')
elif name == 'softwareupdate':
    print('No new software available.')
elif name == 'nvim' and '+MasonToolsUpdateSync' in args and os.environ.get('MOCK_MASON_FAIL'):
    log = pathlib.Path(os.environ['XDG_STATE_HOME']) / 'nvim/mason.log'
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('a') as out:
        out.write('Installation failed for Package(name=test-tool) error=test\\n')
'''


class UpdateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name).resolve()
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        for name in ['sudo', 'nix', 'darwin-rebuild', 'nixos-rebuild', 'home-manager',
                     'brew', 'mas', 'softwareupdate', 'claude', 'npm', 'uv', 'launchctl',
                     'nvim', 'determinate-nixd', 'apt-get', 'uname', 'whoami', 'hostname', 'zinit']:
            p = self.bin / name
            p.write_text(MOCK)
            p.chmod(0o755)
        self.log = self.home / 'commands.jsonl'
        self.env = dict(os.environ, HOME=str(self.home), MOCK_OS='Darwin',
                        XDG_DATA_HOME=str(self.home / '.local/share'),
                        XDG_STATE_HOME=str(self.home / '.local/state'),
                        PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        UPD_LOG=str(self.log))
        (self.home / '.config/nvim').mkdir(parents=True)
        (self.home / '.config/nvim/init.lua').touch()
        zinit = self.home / '.local/share/zinit/zinit.git'
        zinit.mkdir(parents=True)
        (zinit / 'zinit.zsh').write_text('zinit() { command zinit "$@"; }\n')

    def run_upd(self, *args, system=None):
        if system:
            cmd = ['zsh', '-f', '-c',
                   'source "$1"; _upd_detect_system() { print "$MOCK_SYSTEM"; }; shift; _upd_main "$@"',
                   'test', str(SCRIPT), *args]
            self.env['MOCK_SYSTEM'] = system
        else:
            cmd = ['zsh', '-f', str(SCRIPT), *args]
        result = subprocess.run(cmd, env=self.env, capture_output=True, text=True, timeout=15)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result, calls

    def test_install_only_checks_and_activates_on_each_platform(self):
        for system, rebuild in [('darwin', 'darwin-rebuild'), ('linux', 'home-manager'), ('nixos', 'nixos-rebuild')]:
            with self.subTest(system=system):
                self.log.unlink(missing_ok=True)
                result, calls = self.run_upd('install', system=system)
                self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                operations = [c for c in calls if c[0] not in ['uname', 'whoami', 'hostname', 'sudo']]
                self.assertEqual([c[0] for c in operations], ['nix', rebuild])
                self.assertIn('--no-update-lock-file', operations[0])
                self.assertIn('--no-update-lock-file', operations[1])

    def test_removed_modes_are_rejected_before_any_commands(self):
        for system in ['darwin', 'linux', 'nixos']:
            for mode in ['plan', 'apply']:
                with self.subTest(system=system, mode=mode):
                    result, calls = self.run_upd(mode, system=system)
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertEqual(calls, [])
                    self.assertIn('Usage: upd [install]', result.stderr)

    def test_default_runs_the_full_update(self):
        result, default = self.run_upd()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('upd — darwin —', result.stdout)
        self.assertIn(['brew', 'upgrade', '--formula'], default)
        self.assertIn(['brew', 'upgrade', '--cask', '--greedy', 'ghostty'], default)
        self.assertIn(['claude', 'update'], default)
        self.assertIn(['zinit', 'update'], default)
        self.assertTrue(any(c[0] == 'nvim' and '+MasonToolsUpdateSync' in c for c in default))
        forbidden = ['git', 'nix-collect-garbage', 'nix-env']
        self.assertFalse(any(c[0] in forbidden or '--zap' in c or 'cleanup' in c for c in default))

    def test_linux_detects_profile_and_uses_apt(self):
        self.env['MOCK_OS'] = 'Linux'
        self.env['MOCK_ARCH'] = 'aarch64'
        (self.home / '.dotfiles-profile').write_text('core\n')
        result, calls = self.run_upd()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('#tester-core-aarch64-linux', result.stdout)
        self.assertIn(['apt-get', 'upgrade', '-y'], calls)
        self.assertFalse(any(c[0] == 'brew' for c in calls))

    def test_nixos_never_runs_standalone_home_manager_or_apt(self):
        result, calls = self.run_upd(system='nixos')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(any(c[0] == 'nixos-rebuild' for c in calls))
        self.assertFalse(any(c[0] in ['apt-get', 'home-manager'] for c in calls))

    def test_validation_failure_stops_before_activation(self):
        self.env['UPD_FAIL'] = 'nix flake check'
        result, calls = self.run_upd('install')
        self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
        self.assertFalse(any(c[0] in ['sudo', 'darwin-rebuild', 'brew', 'claude'] for c in calls))
        self.assertIn('Earlier steps remain applied', result.stderr)

    def test_help_and_invalid_arguments_do_not_execute(self):
        for args, code in [(('--help',), 0), (('-h',), 0), (('',), 2), (('upgrade',), 2), (('install', 'extra'), 2)]:
            with self.subTest(args=args):
                result, calls = self.run_upd(*args)
                self.assertEqual(result.returncode, code)
                self.assertEqual(calls, [])
                if code == 0:
                    self.assertIn('Usage: upd [install]', result.stdout)

    def test_unsupported_system_stops(self):
        self.env['MOCK_OS'] = 'FreeBSD'
        result, calls = self.run_upd('install')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(calls, [['uname', '-s']])

    def test_activation_is_install_only(self):
        hooks = (ROOT / 'platform/nix/home/hooks.nix').read_text()
        self.assertIn('+Lazy! install', hooks)
        self.assertNotIn('+Lazy! sync', hooks)
        self.assertNotIn('nvim-treesitter").update()', hooks)
        self.assertIn('install.sh" --install-only', hooks)
        self.assertNotIn('submodule update', hooks)
        darwin = (ROOT / 'platform/nix/darwin-configuration.nix').read_text()
        self.assertIn('cleanup = "none";', darwin)

    def test_mason_log_failure_is_not_reported_as_success(self):
        self.env['MOCK_MASON_FAIL'] = '1'
        result, calls = self.run_upd()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('Installation failed for Package(name=test-tool)', result.stderr)
        self.assertNotIn('Done.', result.stdout)
        self.assertFalse(any(c[0] == 'zinit' for c in calls))

    def test_historical_mason_errors_do_not_fail_current_update(self):
        log = self.home / '.local/state/nvim/mason.log'
        log.parent.mkdir(parents=True)
        log.write_text('Installation failed for Package(name=old-error)\n')
        result, calls = self.run_upd()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(['zinit', 'update'], calls)

    def test_timing_service_does_not_sync_dependencies_on_start(self):
        start = (ROOT / 'tools/claude/custom/mcp/timing/start.sh').read_text()
        self.assertIn('uv run --no-sync', start)

    def installer_fixture(self):
        root = self.home / 'custom'
        root.mkdir()
        (root / 'install.sh').write_text((ROOT / 'tools/claude/custom/install.sh').read_text())
        for directory in ['skills', 'agents', 'mcp/timing/.venv']:
            (root / directory).mkdir(parents=True)
        (root / 'mcp/timing/pyproject.toml').touch()
        for directory, tools in [('uv-bin', ['mcp-atlassian', 'things-mcp']),
                                 ('npm/bin', ['context7-mcp'])]:
            dest = self.home / directory
            dest.mkdir(parents=True)
            for tool in tools:
                (dest / tool).write_text('#!/bin/sh\nexit 0\n')
                (dest / tool).chmod(0o755)
        self.env['UV_TOOL_BIN_DIR'] = str(self.home / 'uv-bin')
        self.env['NPM_CONFIG_PREFIX'] = str(self.home / 'npm')
        return root

    def run_installer(self, root, mode='--install-only'):
        result = subprocess.run(['bash', str(root / 'install.sh'), mode], env=self.env,
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_installer_preserves_existing_mcp_and_venv(self):
        root = self.installer_fixture()
        calls = self.run_installer(root)
        self.assertFalse(any(c[0] == 'uv' for c in calls))
        self.assertFalse(any(c[:3] in [['claude', 'mcp', 'add'], ['claude', 'mcp', 'remove']] for c in calls))
        self.assertEqual((self.home / '.claude/skills').resolve(), root / 'skills')

    def test_installer_installs_missing_mcp_without_removing_any(self):
        root = self.installer_fixture()
        self.env['MOCK_MCP_MISSING'] = '1'
        calls = self.run_installer(root)
        self.assertEqual(sum(c[:3] == ['claude', 'mcp', 'add'] for c in calls), 4)
        self.assertFalse(any(c[:3] == ['claude', 'mcp', 'remove'] for c in calls))

    def test_installer_uses_locked_dependencies_only_for_missing_venv(self):
        root = self.installer_fixture()
        (root / 'mcp/timing/.venv').rmdir()
        calls = self.run_installer(root)
        self.assertIn(['uv', 'sync', '--locked', '--quiet'], calls)

    def test_installer_backs_up_real_directories(self):
        root = self.installer_fixture()
        skills = self.home / '.claude/skills'
        skills.mkdir(parents=True)
        (skills / 'personal.txt').write_text('keep me')
        self.run_installer(root)
        backups = list(skills.parent.glob('skills.backup.*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / 'personal.txt').read_text(), 'keep me')
        self.assertEqual(skills.resolve(), root / 'skills')

    def test_installer_replaces_symlink_not_its_target(self):
        root = self.installer_fixture()
        old = self.home / 'old-skills'
        old.mkdir()
        skills = self.home / '.claude/skills'
        skills.parent.mkdir()
        skills.symlink_to(old)
        self.run_installer(root)
        self.assertEqual(skills.resolve(), root / 'skills')
        self.assertEqual(list(old.iterdir()), [])

    def test_installer_check_does_not_create_claude_directory(self):
        root = self.installer_fixture()
        calls = self.run_installer(root, '--check')
        self.assertEqual(calls, [])
        self.assertFalse((self.home / '.claude').exists())


if __name__ == '__main__':
    unittest.main()
