import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


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
            "fingerprints": {"SKILL.md": hashlib.sha256((self.upstream / "SKILL.md").read_bytes()).hexdigest()},
        }]}
        (self.state / "registry.json").write_text(json.dumps(registry))

    def resolve(self, path):
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(path)],
            env={**os.environ, "AGENT_SKILL_OVERRIDES_DIR": str(self.state)},
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


if __name__ == "__main__":
    unittest.main()
