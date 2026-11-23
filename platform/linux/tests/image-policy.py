"""Exercise the production checkout and lifecycle against disposable local Git repos."""

import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LINUX = Path('platform/linux')


def run(*args, cwd=None, ok=True):
    result = subprocess.run(args, cwd=cwd, env=env, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=25)
    if (result.returncode == 0) != ok:
        raise AssertionError((args, result.returncode, result.stdout))
    return result.stdout.strip()


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def commit():
    run('git', 'add', '--all', cwd=repo)  # Only the disposable fixture.
    run('git', 'commit', '-qm', 'fixture', cwd=repo)
    return run('git', 'rev-parse', 'HEAD', cwd=repo)


with tempfile.TemporaryDirectory() as directory:
    tmp = Path(directory)
    home, repo, bin_dir = tmp/'home', tmp/'origin', tmp/'bin'
    home.mkdir(); repo.mkdir(); bin_dir.mkdir()
    env = dict(os.environ, HOME=str(home), GIT_CONFIG_GLOBAL=str(tmp/'gitconfig'),
               GIT_CONFIG_NOSYSTEM='1', GIT_TERMINAL_PROMPT='0', GIT_ALLOW_PROTOCOL='file', PROFILE='devops',
               GIT_AUTHOR_NAME='Test', GIT_AUTHOR_EMAIL='test@example.org',
               GIT_COMMITTER_NAME='Test', GIT_COMMITTER_EMAIL='test@example.org',
               CONTAINER_TZ='unused', XDG_CONFIG_HOME=str(home/'.config'))
    env.pop('DOTFILES_ROOT', None)
    env['PATH'] = str(bin_dir) + ':' + env['PATH']
    # Nix's optional system profile is sourced before the user profile by install.sh.
    env['TEST_PATH'] = env['PATH']
    write(home/'.nix-profile/etc/profile.d/nix.sh', 'export PATH="$TEST_PATH"\n')
    for cmd in ('nix', 'home-manager', 'sudo'):
        shim = bin_dir/cmd
        write(shim, '#!/bin/sh\necho "${0##*/} $*" >> "$HOME/calls"\n')
        shim.chmod(0o755)
    run('git', 'init', '-qb', 'main', cwd=repo)
    for file in ('platform/common.sh', *(str(LINUX/name) for name in
                 ('image-key', 'image-inputs', 'install.sh', 'dotfiles-provision', 'Dockerfile'))):
        (repo/file).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT/file, repo/file)
    # An initialized local private submodule exercises identity validation without secrets.
    sub = tmp/'private'; sub.mkdir(); run('git', 'init', '-q', cwd=sub)
    write(sub/'git/includes.conf', ''); run('git', 'add', '.', cwd=sub)
    run('git', 'commit', '-qm', 'fixture identity', cwd=sub)
    run('git', 'config', '--global', 'protocol.file.allow', 'always')
    run('git', 'submodule', 'add', '-q', str(sub), 'private', cwd=repo)
    write(repo/'tools/claude/custom/install.sh', '#!/bin/sh\nexit 0\n')
    (repo/'tools/claude/custom/install.sh').chmod(0o755)
    base = commit()
    manifest = (repo/LINUX/'image-inputs').read_text().splitlines()
    workflow = (ROOT/'.github/workflows/devcontainer-image.yml').read_text()
    paths = re.findall(r"^      - '([^']+)'$", workflow.split('  schedule:')[0], re.M)
    assert paths == [*manifest, '.github/workflows/devcontainer-image.yml']
    key = run(repo/LINUX/'image-key', cwd=repo)
    for path in ('tools/pi/AGENTS.md', 'tools/pi/extensions/work-mode.ts', 'tools/pi/themes/theme.json',
                 'tools/pi/README.md', 'tools/pi/statusline/statusline_test.go', 'tools/zsh/.zshrc',
                 'platform/nix/home/darwin.nix', 'platform/nix/nixos/default.nix', 'tools/nvim/lua/config/keymaps.lua'):
        write(repo/path, 'live'); commit()
        assert run(repo/LINUX/'image-key', cwd=repo) == key, path
    # Run the real Docker checkout recipe after main has moved beyond the requested SHA.
    for url in ('https://github.com/CosmDandy/dotfiles.git', 'git@github.com:CosmDandy/dotfiles.git'):
        run('git', 'config', '--global', '--add', f'url.{repo.as_uri()}.insteadOf', url)
    env['REVISION'] = base
    recipe = (repo/LINUX/'Dockerfile').read_text().split('FROM base AS checkout\n')[1]
    recipe = recipe.split('RUN ', 1)[1].split('\n\n', 1)[0]
    run('sh', '-ec', recipe, cwd=home)
    clone = home/'dotfiles'
    assert run('git', 'rev-parse', 'HEAD', cwd=clone) == base
    assert run('git', 'branch', '--show-current', cwd=clone) == 'main'
    assert (home/'.dotfiles-generation').read_text().strip() == key
    write(home/'.dotfiles-profile', 'devops\n')
    write(home/'.claude/.mcp-baked-from', run('git', 'rev-parse', 'HEAD:tools/claude/custom', cwd=clone))
    (home/'.claude/skills').symlink_to(clone/'tools/claude/custom/skills')
    for _ in range(2):
        assert 'skipping home-manager switch' in run(repo/LINUX/'dotfiles-provision')
        assert run('git', 'rev-parse', 'HEAD', cwd=clone) == run('git', 'rev-parse', 'HEAD', cwd=repo)
    assert not (home/'calls').exists() or 'home-manager switch' not in (home/'calls').read_text()
    run('git', 'remote', 'set-url', 'origin', str(tmp/'missing-origin'), cwd=clone)
    assert 'skipping home-manager switch' in run(repo/LINUX/'dotfiles-provision')
    run('git', 'remote', 'set-url', 'origin', repo.as_uri(), cwd=clone)
    for path in ('platform/nix/flake.lock', 'platform/nix/home/pi.nix', 'tools/pi/statusline/main.go',
                 'tools/pi/patches/vim-transcript.patch', 'tools/pi/mcp.json',
                 'tools/nvim/lua/plugins/editor/blink-cmp.lua', 'tools/zsh/plugins.zsh'):
        write(repo/path, 'baked'); commit()
        new_key = run(repo/LINUX/'image-key', cwd=repo)
        assert new_key != key, path
        key = new_key
    (home/'calls').unlink(missing_ok=True)
    message = run(repo/LINUX/'dotfiles-provision', ok=False)
    assert f'ghcr.io/cosmdandy/devcontainer:devops-env-{key}' in message and not (home/'calls').exists()
    write(home/'.dotfiles-generation', key); write(home/'.dotfiles-profile', 'core')
    assert 'devops-env-' in run(repo/LINUX/'dotfiles-provision', ok=False)
    (home/'.dotfiles-generation').unlink()
    assert 'devops-env-' in run(repo/LINUX/'dotfiles-provision', ok=False)
    run(clone/LINUX/'install.sh', '--allow-local-build')
    assert 'home-manager switch --flake' in (home/'calls').read_text()
    assert not (home/'.dotfiles-generation').exists()
    print('PASS: CI paths, pinned checkout, live-only sync, baked inputs, exact tag, profile, missing marker, explicit switch')
