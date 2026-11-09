import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class SecretsScanTest(unittest.TestCase):
    def test_nested_invocation_checks_untracked_files_at_repository_root(self):
        self.assertIsNotNone(shutil.which("gitleaks"))
        skill = (ROOT / "codex/skills/secrets-scan/SKILL.md").read_text()
        steps = "\n".join(re.findall(r"^ *```bash\n(.*?)^ *``` *$", skill, re.DOTALL | re.MULTILINE))
        self.assertTrue(steps)
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo / "sub").mkdir()
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            subprocess.run(["git", "-C", str(repo), "-c", "user.name=Fixture",
                            "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgSign=false",
                            "commit", "--allow-empty", "-qm", "fixture"], check=True)
            (repo / ".gitleaks.toml").write_text(
                "[[rules]]\nid = 'fixture'\ndescription = 'synthetic fixture'\n"
                "regex = '''audit-secret-[0-9]{6}'''\n")
            (repo / "clean.txt").write_text("ordinary text\n")
            clean = subprocess.run(["bash", "-c", steps], cwd=repo / "sub", capture_output=True)
            self.assertEqual(clean.returncode, 0, clean.stderr.decode())
            (repo / "secret.txt").write_text("audit-secret-123456\n")
            root_result = subprocess.run(["bash", "-c", steps], cwd=repo, capture_output=True)
            nested_result = subprocess.run(["bash", "-c", steps], cwd=repo / "sub", capture_output=True)
            self.assertNotEqual(root_result.returncode, 0)
            self.assertNotEqual(nested_result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
