import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "agent-shared/bin/resolve-skill-source.py"


class SkillSourceTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.upstream = self.root / "upstream"
        self.effective = self.root / "effective"
        self.state = self.root / "state"
        for folder in (self.upstream, self.effective, self.state):
            folder.mkdir()
        (self.upstream / "SKILL.md").write_text("original\n")
        (self.effective / "SKILL.md").write_text("repaired\n")

    def register(self):
        registry = {"packages": [{
            "original_root": str(self.upstream), "effective_root": str(self.effective),
            "fingerprints": {file.relative_to(self.upstream).as_posix(): hashlib.sha256(file.read_bytes()).hexdigest()
                             for file in self.upstream.rglob('*') if file.is_file()},
        }]}
        (self.state / "registry.json").write_text(json.dumps(registry))

    def resolve(self, path, **environment):
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(path)], cwd=self.root,
            env={**os.environ, **environment, "AGENT_SKILL_OVERRIDES_DIR": str(self.state)},
            capture_output=True, text=True,
        )

    def test_absent_registry_preserves_the_original_source(self):
        result = self.resolve(self.upstream / "SKILL.md")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["path"], str(self.upstream / "SKILL.md"))
        self.assertFalse(json.loads(result.stdout)["overridden"])

    def test_matching_source_uses_the_repaired_copy(self):
        self.register()
        result = self.resolve(self.upstream / "SKILL.md")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["path"], str(self.effective / "SKILL.md"))
        self.assertTrue(json.loads(result.stdout)["overridden"])

    def test_changed_upstream_does_not_reuse_an_old_repair(self):
        self.register()
        (self.upstream / "SKILL.md").write_text("new release\n")
        result = self.resolve(self.upstream / "SKILL.md")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["path"], str(self.upstream / "SKILL.md"))
        self.assertEqual(json.loads(result.stdout)["reason"], "upstream-changed")

    def test_new_upstream_files_invalidate_the_old_copy(self):
        self.register()
        (self.upstream / "new-helper.py").write_text("print('new')\n")
        result = self.resolve(self.upstream / "SKILL.md")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["reason"], "upstream-changed")

    def test_unrelated_prefix_is_not_an_override(self):
        self.register()
        neighbor = self.root / "upstream-other"
        neighbor.mkdir()
        (neighbor / "SKILL.md").write_text("another package\n")
        result = self.resolve(neighbor / "SKILL.md")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(json.loads(result.stdout)["overridden"])

    def test_missing_repaired_file_is_not_reported_as_applied(self):
        self.register()
        (self.effective / "SKILL.md").unlink()
        result = self.resolve(self.upstream / "SKILL.md")
        self.assertNotEqual(result.returncode, 0)

    def cached_skill(self, product):
        agent_home = self.root / product
        self.upstream = agent_home / 'plugins/cache/example-market/example-plugin/1.0'
        self.upstream.mkdir(parents=True)
        (self.upstream / 'SKILL.md').write_text('original\n')
        return agent_home

    def test_disabled_codex_plugin_cannot_resolve_a_retained_override(self):
        agent_home = self.cached_skill('codex')
        (agent_home / 'config.toml').write_text('[plugins."example-plugin@example-market"]\nenabled = false\n')
        self.register()
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('disabled', result.stderr)
        self.assertEqual(result.stdout, '')

    def test_codex_plugin_enabled_by_a_profile_resolves(self):
        agent_home = self.cached_skill('codex')
        (agent_home / 'config.toml').write_text('[plugins."example-plugin@example-market"]\nenabled = false\n')
        (agent_home / 'work.config.toml').write_text('[plugins."example-plugin@example-market"]\nenabled = true\n')
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["path"], str(self.upstream / 'SKILL.md'))

    def test_codex_plugin_enabled_by_the_project_resolves(self):
        agent_home = self.cached_skill('codex')
        (agent_home / 'config.toml').write_text('[plugins."example-plugin@example-market"]\nenabled = false\n')
        project = self.root / 'project'
        (project / '.codex').mkdir(parents=True)
        (project / 'nested').mkdir()
        (project / '.codex/config.toml').write_text('[plugins."example-plugin@example-market"]\nenabled = true\n')
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(self.upstream / 'SKILL.md')], cwd=project / 'nested',
            env={**os.environ, "AGENT_SKILL_OVERRIDES_DIR": str(self.state)}, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["path"], str(self.upstream / 'SKILL.md'))

    def test_disabled_claude_plugin_cannot_resolve_without_a_registry(self):
        agent_home = self.cached_skill('claude')
        (agent_home / 'settings.json').write_text(json.dumps({
            'enabledPlugins': {'example-plugin@example-market': False},
        }))
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('disabled', result.stderr)

    def test_disabled_plugin_root_cannot_resolve_a_retained_override(self):
        agent_home = self.cached_skill('codex')
        (agent_home / 'config.toml').write_text('[plugins."example-plugin@example-market"]\nenabled = false\n')
        self.register()
        result = self.resolve(self.upstream)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('disabled', result.stderr)

    def test_enabled_cached_plugin_still_resolves_its_override(self):
        agent_home = self.cached_skill('codex')
        (agent_home / 'config.toml').write_text('[plugins."example-plugin@example-market"]\nenabled = true\n')
        self.register()
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['path'], str(self.effective / 'SKILL.md'))

    def test_utf8_plugin_config_resolves_in_a_non_utf8_locale(self):
        agent_home = self.cached_skill('codex')
        (agent_home / 'config.toml').write_text(
            '# 日本語の設定\n[plugins."example-plugin@example-market"]\nenabled = true\n', encoding='utf-8')
        self.register()
        result = self.resolve(self.upstream / 'SKILL.md', LC_ALL='C', PYTHONUTF8='0', PYTHONCOERCECLOCALE='0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['path'], str(self.effective / 'SKILL.md'))

    def prepare(self):
        self.register()
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(self.upstream), '--prepare'],
            env={**os.environ, 'AGENT_SKILL_OVERRIDES_DIR': str(self.state)},
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_readme_update_preserves_repair_and_new_upstream_files(self):
        self.prepare()
        (self.upstream / 'README.md').write_text('new documentation\n')
        (self.upstream / 'helper.py').write_text('print("new helper")\n')
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertEqual(result.returncode, 0, result.stderr)
        resolved = json.loads(result.stdout)
        self.assertTrue(resolved['overridden'])
        self.assertEqual(Path(resolved['path']).read_text(), 'repaired\n')
        self.assertEqual((Path(resolved['package_root']) / 'README.md').read_text(), 'new documentation\n')
        self.assertEqual((Path(resolved['package_root']) / 'helper.py').read_text(), 'print("new helper")\n')
        self.assertEqual((self.upstream / 'SKILL.md').read_text(), 'original\n')

    def test_new_version_merges_disjoint_changes_and_survives_old_cache_removal(self):
        self.cached_skill('codex')
        original = 'original\n' + 'unchanged\n' * 20 + 'old ending\n'
        (self.upstream / 'SKILL.md').write_text(original)
        (self.effective / 'SKILL.md').write_text('repaired\n' + 'unchanged\n' * 20 + 'old ending\n')
        self.prepare()
        newer = self.upstream.parent / '2.0'
        newer.mkdir()
        (newer / 'SKILL.md').write_text('original\n' + 'unchanged\n' * 20 + 'new ending\n')
        (self.upstream / 'SKILL.md').unlink()
        self.upstream.rmdir()
        result = self.resolve(newer / 'SKILL.md')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(json.loads(result.stdout)['path']).read_text(), 'repaired\n' + 'unchanged\n' * 20 + 'new ending\n')

    def test_upstream_absorbed_repair_returns_current_distribution(self):
        self.prepare()
        (self.upstream / 'SKILL.md').write_text('repaired\n')
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(json.loads(result.stdout)['overridden'])
        self.assertEqual(json.loads(result.stdout)['path'], str(self.upstream / 'SKILL.md'))

    def test_conflicting_update_is_explicit_failure_and_can_resume(self):
        self.prepare()
        (self.upstream / 'SKILL.md').write_text('conflicting new instructions\n')
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SKILL.md', result.stderr)
        self.assertEqual(result.stdout, '')
        self.assertEqual((self.effective / 'SKILL.md').read_text(), 'repaired\n')
        (self.upstream / 'SKILL.md').write_text('original\n')
        self.assertEqual(self.resolve(self.upstream / 'SKILL.md').returncode, 0)

    def test_registered_behavior_check_runs_before_publication(self):
        self.prepare()
        registry = self.state / 'registry.json'
        data = json.loads(registry.read_text())
        data['packages'][0]['checks'] = [[sys.executable, '-c', 'from pathlib import Path; assert not Path("bad").exists()']]
        registry.write_text(json.dumps(data))
        (self.upstream / 'bad').write_text('incompatible dependency\n')
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('validation', result.stderr.lower())
        self.assertEqual(result.stdout, '')
        (self.upstream / 'bad').unlink()
        self.assertEqual(self.resolve(self.upstream / 'SKILL.md').returncode, 0)

    def test_new_python_syntax_error_is_not_published(self):
        self.prepare()
        (self.upstream / 'helper.py').write_text('def broken(:\n')
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('helper.py', result.stderr)

    def test_tampered_prepared_repair_is_rejected(self):
        self.prepare()
        (self.effective / 'SKILL.md').write_text('changed without preparing\n')
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertNotEqual(result.returncode, 0)

    def test_version_family_does_not_cross_marketplaces(self):
        self.cached_skill('codex')
        self.prepare()
        unrelated = self.upstream.parents[2] / 'another-market/example-plugin/2.0'
        unrelated.mkdir(parents=True)
        (unrelated / 'SKILL.md').write_text('unrelated distribution\n')
        result = self.resolve(unrelated / 'SKILL.md')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(json.loads(result.stdout)['overridden'])

    def test_newline_conversion_does_not_conflict_with_a_repair(self):
        (self.upstream / 'SKILL.md').write_bytes(b'original\r\n' + b'unchanged\r\n' * 20)
        (self.effective / 'SKILL.md').write_bytes(b'repaired\r\n' + b'unchanged\r\n' * 20)
        self.prepare()
        (self.upstream / 'SKILL.md').write_bytes(b'original\n' + b'unchanged\n' * 20 + b'new tail\n')
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(json.loads(result.stdout)['path']).read_bytes(), b'repaired\n' + b'unchanged\n' * 20 + b'new tail\n')

    def test_conflict_can_be_reprepared_against_current_version(self):
        self.cached_skill('codex')
        self.prepare()
        newer = self.upstream.parent / '2.0'
        newer.mkdir()
        (newer / 'SKILL.md').write_text('new conflicting behavior\n')
        self.assertNotEqual(self.resolve(newer / 'SKILL.md').returncode, 0)
        (self.effective / 'SKILL.md').write_text('new behavior with repair\n')
        result = subprocess.run([sys.executable, str(SCRIPT), str(newer), '--prepare'],
            env={**os.environ, 'AGENT_SKILL_OVERRIDES_DIR': str(self.state)}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.resolve(newer / 'SKILL.md')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(json.loads(result.stdout)['path']).read_text(), 'new behavior with repair\n')

    def test_preparing_missing_maintained_copy_fails(self):
        self.register()
        (self.effective / 'SKILL.md').unlink()
        self.effective.rmdir()
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.upstream), '--prepare'],
            env={**os.environ, 'AGENT_SKILL_OVERRIDES_DIR': str(self.state)}, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('repairs', json.loads((self.state / 'registry.json').read_text())['packages'][0])

    def test_reprepare_cannot_turn_unported_upstream_files_into_repairs(self):
        self.prepare()
        (self.upstream / 'new-helper.py').write_text('print("new upstream feature")\n')
        (self.effective / 'SKILL.md').write_text('updated repair\n')
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.upstream), '--prepare'],
            env={**os.environ, 'AGENT_SKILL_OVERRIDES_DIR': str(self.state)}, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('new-helper.py', result.stderr)
        self.assertNotIn('new-helper.py', json.loads((self.state / 'registry.json').read_text())['packages'][0]['repairs'])

    def test_json_validation_reports_the_affected_file(self):
        self.prepare()
        (self.upstream / 'settings.json').write_text('invalid json\n')
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('settings.json', result.stderr)

    def test_reprepare_rejects_unported_changes_in_another_repaired_file(self):
        tail = 'unchanged\n' * 20
        (self.upstream / 'second.md').write_text('original second\n' + tail)
        (self.effective / 'second.md').write_text('repaired second\n' + tail)
        self.prepare()
        (self.upstream / 'SKILL.md').write_text('new conflicting behavior\n')
        (self.upstream / 'second.md').write_text('original second\n' + tail + 'upstream addition\n')
        (self.effective / 'SKILL.md').write_text('new behavior with repair\n')
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.upstream), '--prepare'],
            env={**os.environ, 'AGENT_SKILL_OVERRIDES_DIR': str(self.state)}, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('second.md', result.stderr)

    def test_reprepare_preserves_each_repair_unless_explicitly_removed(self):
        (self.upstream / 'second.md').write_text('original second\n')
        (self.effective / 'second.md').write_text('repaired second\n')
        self.prepare()
        (self.effective / 'SKILL.md').write_text('updated repair\n')
        (self.effective / 'second.md').write_text('original second\n')
        command = [sys.executable, str(SCRIPT), str(self.upstream), '--prepare']
        environment = {**os.environ, 'AGENT_SKILL_OVERRIDES_DIR': str(self.state)}
        result = subprocess.run(command, env=environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('second.md', result.stderr)
        result = subprocess.run([*command, '--drop-repair', 'second.md'], env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertEqual(result.returncode, 0, result.stderr)
        root = Path(json.loads(result.stdout)['package_root'])
        self.assertEqual((root / 'SKILL.md').read_text(), 'updated repair\n')
        self.assertEqual((root / 'second.md').read_text(), 'original second\n')

    def test_old_baseline_cannot_bypass_reprepare_preservation(self):
        self.prepare()
        baseline = self.root / 'baseline'
        baseline.mkdir()
        (baseline / 'SKILL.md').write_text('original\n')
        (self.effective / 'SKILL.md').write_text('original\n')
        registry = self.state / 'registry.json'
        before = registry.read_bytes()
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.upstream), '--prepare', '--baseline', str(baseline)],
            env={**os.environ, 'AGENT_SKILL_OVERRIDES_DIR': str(self.state)}, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(registry.read_bytes(), before)

    def test_reprepare_rejects_dropped_repair_inside_an_edited_file(self):
        middle = 'unchanged\n' * 20
        (self.upstream / 'SKILL.md').write_text('original heading\n' + middle + 'original ending\n')
        (self.effective / 'SKILL.md').write_text('repaired heading\n' + middle + 'repaired ending\n')
        self.prepare()
        (self.upstream / 'SKILL.md').write_text('new upstream heading\n' + middle + 'original ending\n')
        (self.effective / 'SKILL.md').write_text('new heading with repair\n' + middle + 'original ending\n')
        registry = self.state / 'registry.json'
        before = registry.read_bytes()
        command = [sys.executable, str(SCRIPT), str(self.upstream), '--prepare']
        environment = {**os.environ, 'AGENT_SKILL_OVERRIDES_DIR': str(self.state)}
        result = subprocess.run(command, env=environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SKILL.md', result.stderr)
        self.assertEqual(registry.read_bytes(), before)
        expected = 'new heading with repair\n' + middle + 'repaired ending\n'
        (self.effective / 'SKILL.md').write_text(expected)
        result = subprocess.run(command, env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(json.loads(result.stdout)['path']).read_text(), expected)

    def test_reprepare_rejects_dropped_upstream_change_inside_an_edited_file(self):
        middle = 'unchanged\n' * 20
        (self.upstream / 'SKILL.md').write_text('original heading\n' + middle + 'original ending\n')
        (self.effective / 'SKILL.md').write_text('repaired heading\n' + middle + 'original ending\n')
        self.prepare()
        (self.upstream / 'SKILL.md').write_text('original heading\n' + middle + 'new upstream ending\n')
        (self.effective / 'SKILL.md').write_text('updated repaired heading\n' + middle + 'original ending\n')
        registry = self.state / 'registry.json'
        before = registry.read_bytes()
        command = [sys.executable, str(SCRIPT), str(self.upstream), '--prepare']
        environment = {**os.environ, 'AGENT_SKILL_OVERRIDES_DIR': str(self.state)}
        result = subprocess.run(command, env=environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SKILL.md', result.stderr)
        self.assertEqual(registry.read_bytes(), before)
        expected = 'updated repaired heading\n' + middle + 'new upstream ending\n'
        (self.effective / 'SKILL.md').write_text(expected)
        result = subprocess.run(command, env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(json.loads(result.stdout)['path']).read_text(), expected)

    def test_reprepare_requires_explicit_removal_of_a_conflicting_repair(self):
        self.prepare()
        (self.upstream / 'SKILL.md').write_text('new upstream behavior\n')
        (self.effective / 'SKILL.md').write_text('new upstream behavior\n')
        registry = self.state / 'registry.json'
        before = registry.read_bytes()
        command = [sys.executable, str(SCRIPT), str(self.upstream), '--prepare']
        environment = {**os.environ, 'AGENT_SKILL_OVERRIDES_DIR': str(self.state)}
        result = subprocess.run(command, env=environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(registry.read_bytes(), before)
        result = subprocess.run([*command, '--drop-repair', 'SKILL.md'],
            env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(json.loads(result.stdout)['path']).read_text(), 'new upstream behavior\n')

    def test_reprepare_allows_binary_repair_edits_without_weakening_refresh(self):
        (self.upstream / 'asset.bin').write_bytes(b'\x00original asset')
        (self.effective / 'asset.bin').write_bytes(b'\x00repaired asset')
        self.prepare()
        expected = b'\x00improved repaired asset'
        (self.effective / 'asset.bin').write_bytes(expected)
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.upstream), '--prepare'],
            env={**os.environ, 'AGENT_SKILL_OVERRIDES_DIR': str(self.state)}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.resolve(self.upstream / 'asset.bin')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(json.loads(result.stdout)['path']).read_bytes(), expected)
        (self.upstream / 'asset.bin').write_bytes(b'\x00new upstream asset')
        result = self.resolve(self.upstream / 'asset.bin')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('asset.bin', result.stderr)

    def test_reprepare_preserves_mixed_newlines_when_editing_a_repair(self):
        (self.upstream / 'SKILL.md').write_bytes(b'original\r\nunchanged\n')
        (self.effective / 'SKILL.md').write_bytes(b'repaired\r\nunchanged\n')
        self.prepare()
        expected = b'improved repair\r\nunchanged\n'
        (self.effective / 'SKILL.md').write_bytes(expected)
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.upstream), '--prepare'],
            env={**os.environ, 'AGENT_SKILL_OVERRIDES_DIR': str(self.state)}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.resolve(self.upstream / 'SKILL.md')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(json.loads(result.stdout)['path']).read_bytes(), expected)
        self.assertEqual((self.effective / 'SKILL.md').read_bytes(), expected)

    def test_concurrent_preparations_preserve_both_registrations(self):
        self.register()
        registry = self.state / 'registry.json'
        data = json.loads(registry.read_text())
        other = self.root / 'other'
        fixed = self.root / 'other-fixed'
        other.mkdir()
        fixed.mkdir()
        (other / 'SKILL.md').write_text('original\n')
        (fixed / 'SKILL.md').write_text('another repair\n')
        data['packages'].append({**data['packages'][0], 'original_root': str(other), 'effective_root': str(fixed)})
        registry.write_text(json.dumps(data))
        spec = importlib.util.spec_from_file_location('concurrent_resolver', SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        save = module.save_object
        barrier = threading.Barrier(2)
        seen = threading.local()

        def synchronize(state, content):
            if not getattr(seen, 'started', False):
                seen.started = True
                try:
                    barrier.wait(timeout=1)
                except threading.BrokenBarrierError:
                    pass
            return save(state, content)

        with patch.object(module, 'save_object', synchronize), ThreadPoolExecutor(2) as pool:
            futures = [pool.submit(module.prepare, root, registry) for root in [self.upstream, other]]
            for future in futures:
                future.result(timeout=10)
        self.assertTrue(all('repairs' in package for package in json.loads(registry.read_text())['packages']))


if __name__ == "__main__":
    unittest.main()
