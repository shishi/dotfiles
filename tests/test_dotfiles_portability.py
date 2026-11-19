import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
# Windows では、コマンド名だけを渡すと PATH より先に System32 が探され、WSL の bash が選ばれる。
# WSL の bash は Windows のパスを読めないので、PATH の順で見つかる bash (Git Bash) を使う。
# PATH でも System32 が Git Bash より前にあると、ここでも WSL の bash になる
BASH = shutil.which('bash') or 'bash'


class PortabilityTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.env = {**os.environ, 'GIT_CONFIG_GLOBAL': os.devnull, 'GIT_CONFIG_NOSYSTEM': '1'}
        self.git('init', '-q')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'commit.gpgSign', 'false')
        for path in ['agent-shared/bin/check-dotfiles-portability.py',
                     'agent-shared/bin/install-dotfiles-hooks.sh',
                     'agent-shared/git-hooks/pre-commit']:
            if (ROOT / path).exists():
                target = self.root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / path, target)
        self.write('initial.txt', 'initial\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'initial')

    def git(self, *args, input=None, check=True):
        return subprocess.run(['git', *args], cwd=self.root, env=self.env, input=input,
                              capture_output=True, text=True, check=check)

    def write(self, path, text):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def install(self):
        script = self.root / 'agent-shared/bin/install-dotfiles-hooks.sh'
        if script.exists():
            subprocess.run([BASH, str(script)], cwd=self.root, env=self.env,
                           capture_output=True, text=True, check=True)

    def commit(self):
        return self.git('commit', '-qm', 'change', check=False)

    def stage_link(self, path, target):
        oid = self.git('hash-object', '-w', '--stdin', input=target).stdout.strip()
        self.git('update-index', '--add', '--cacheinfo', '120000', oid, path)

    def stage_hook(self, command, path='codex/hooks.json', key='command'):
        self.write(path, json.dumps({'hooks': {'SessionStart': [
            {'hooks': [{'type': 'command', key: command}]},
        ]}}))
        self.git('add', path)

    def test_absolute_link_is_rejected_before_head_changes(self):
        self.install()
        before = self.git('rev-parse', 'HEAD').stdout
        self.stage_link('codex/skills/review/SKILL.md', '/nix/store/example/share/SKILL.md')
        result = self.commit()
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn('codex/skills/review/SKILL.md', result.stderr)
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout, before)

    def test_staged_absolute_hook_cannot_be_hidden_by_a_worktree_fix(self):
        self.install()
        self.stage_hook("bash '/workspace/private/agent.sh' session")
        self.write('codex/hooks.json', '{}\n')
        result = self.commit()
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn('codex/hooks.json', result.stderr)

    def test_windows_absolute_hook_is_rejected(self):
        self.install()
        self.stage_hook(r'& "D:\profiles\example\agent.ps1"',
                        path='claude/settings.json', key='commandWindows')
        self.assertNotEqual(self.commit().returncode, 0)

    def test_absolute_hook_argument_with_equals_is_rejected(self):
        self.install()
        self.stage_hook("bash '/workspace/a=b/agent.sh' session")
        self.assertNotEqual(self.commit().returncode, 0)

    def test_portable_hook_allows_retry_after_rejection(self):
        self.install()
        self.stage_hook("bash '/workspace/private/agent.sh' session")
        self.assertNotEqual(self.commit().returncode, 0)
        self.stage_hook('bash ~/.codex/agent.sh session > /dev/null')
        result = self.commit()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_unusable_python3_falls_back_to_working_python(self):
        self.install()
        self.write('bin/python3', '#!/bin/sh\nexit 1\n')
        self.write('bin/python', '#!/bin/sh\nexec ' + shlex.quote(sys.executable) + ' "$@"\n')
        for name in ['python3', 'python']:
            (self.root / 'bin' / name).chmod(0o755)
        self.env['PATH'] = str(self.root / 'bin') + os.pathsep + self.env['PATH']
        self.stage_hook('bash ~/.codex/agent.sh session')
        result = self.commit()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_relative_link_to_staged_file_is_portable(self):
        self.install()
        self.write('skills/source.md', 'source\n')
        self.git('add', 'skills/source.md')
        self.stage_link('skills/entry.md', 'source.md')
        result = self.commit()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_relative_link_to_an_untracked_file_is_rejected(self):
        self.install()
        self.write('skills/source.md', 'source\n')
        self.stage_link('skills/entry.md', 'source.md')
        self.assertNotEqual(self.commit().returncode, 0)

    def test_custom_hook_survives_repeated_installation(self):
        self.git('config', 'core.hooksPath', 'custom-hooks')
        self.write('custom-hooks/pre-commit', '#!/bin/sh\necho ran >> custom-hook-calls\n')
        (self.root / 'custom-hooks/pre-commit').chmod(0o755)
        self.install()
        self.install()
        self.stage_hook('bash ~/.codex/agent.sh session')
        result = self.commit()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'custom-hook-calls').read_text(), 'ran\n')

    def test_shared_hook_directory_does_not_block_another_repository(self):
        self.git('config', 'core.hooksPath', str(self.root / 'shared-hooks'))
        self.install()
        other = self.root / 'other'
        other.mkdir()
        for args in [('init', '-q'), ('config', 'core.hooksPath', str(self.root / 'shared-hooks')),
                     ('config', 'user.name', 'Test'), ('config', 'user.email', 'test@example.invalid'),
                     ('config', 'commit.gpgSign', 'false'), ('commit', '--allow-empty', '-qm', 'initial')]:
            result = subprocess.run(['git', *args], cwd=other, env=self.env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
