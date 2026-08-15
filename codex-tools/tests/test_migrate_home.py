from pathlib import Path
from contextlib import redirect_stderr, redirect_stdout
import io
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


CODEX_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CODEX_DIR))

import bootstrap_home as migrate_home


class BootstrapHomeTest(unittest.TestCase):
    @unittest.skipUnless(os.name == "nt", "Windows junction semantics")
    def test_is_junction_supports_python_311_path_api(self) -> None:
        class PathWithoutIsJunction:
            def __init__(self, path: Path) -> None:
                self.path = path

            def __fspath__(self) -> str:
                return os.fspath(self.path)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "target"
            junction = root / "junction"
            target.mkdir()
            migrate_home._create_junction(junction, target)

            self.assertTrue(
                migrate_home._is_junction(PathWithoutIsJunction(junction))
            )

    def test_is_junction_propagates_permission_errors(self) -> None:
        error = PermissionError("denied")
        with patch.object(migrate_home.os, "name", "nt"), patch.object(
            migrate_home.os, "lstat", side_effect=error
        ):
            with self.assertRaises(PermissionError) as raised:
                migrate_home._is_junction(Path("blocked"))

        self.assertIs(error, raised.exception)

    @unittest.skipUnless(os.name == "nt", "Windows read-only semantics")
    def test_remove_path_clears_readonly_top_level_file_on_windows(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            runtime = Path(directory) / "auth.json"
            runtime.write_text("{}", encoding="utf-8")
            runtime.chmod(stat.S_IREAD)

            error = None
            try:
                migrate_home._remove_path(runtime)
            except OSError as caught:
                error = caught

            self.assertIsNone(error)
            self.assertFalse(runtime.exists())

    def test_readonly_retry_does_not_change_permissions_off_windows(self) -> None:
        error = PermissionError("denied")
        with patch.object(migrate_home.os, "name", "posix"), patch.object(
            migrate_home.os, "chmod"
        ) as chmod:
            with self.assertRaises(PermissionError) as raised:
                migrate_home._retry_readonly_removal(
                    lambda _: None,
                    "runtime",
                    (PermissionError, error, None),
                )

        self.assertIs(error, raised.exception)
        chmod.assert_not_called()

    @unittest.skipUnless(os.name == "nt", "Windows read-only semantics")
    def test_remove_path_clears_readonly_files_on_windows(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            runtime = Path(directory) / "runtime"
            pack = runtime / ".git" / "objects" / "pack" / "cache.idx"
            pack.parent.mkdir(parents=True)
            pack.write_bytes(b"pack index")
            pack.chmod(stat.S_IREAD)

            error = None
            try:
                migrate_home._remove_path(runtime)
            except OSError as caught:
                error = caught

            self.assertIsNone(error)
            self.assertFalse(runtime.exists())

    def test_windows_process_check_detects_lowercase_tasklist_image(self) -> None:
        tasklist = subprocess.CompletedProcess(
            [],
            0,
            '"codex.exe","62612","Console","1","129,988 K"\n',
            "",
        )
        with patch.object(migrate_home.os, "name", "nt"), patch.object(
            migrate_home.subprocess, "run", return_value=tasklist
        ) as runner:
            running = migrate_home.default_process_running()

        self.assertTrue(running)
        self.assertEqual(
            ["tasklist", "/FI", "IMAGENAME eq Codex.exe", "/FO", "CSV", "/NH"],
            runner.call_args.args[0],
        )

    def test_migrate_rejects_codex_home_symlink_before_backup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            external_codex = root / "external-codex"
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            backup_root = root / "backups"
            external_codex.mkdir()
            codex_home.parent.mkdir(parents=True)
            codex_home.symlink_to(external_codex, target_is_directory=True)
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills").mkdir(parents=True)
            (external_codex / "config.toml").write_text("outside", encoding="utf-8")

            status = migrate_home.migrate(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_codex=repo_codex,
                backup_root=backup_root,
                process_running=lambda: False,
            )

            self.assertEqual(1, status)
            self.assertTrue(codex_home.is_symlink())
            self.assertEqual(
                "outside", (external_codex / "config.toml").read_text(encoding="utf-8")
            )
            self.assertFalse(backup_root.exists())

    def test_migrate_rejects_agents_skills_symlink_before_backup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            external_skills = root / "external-skills"
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            backup_root = root / "backups"
            codex_home.mkdir(parents=True)
            external_skills.mkdir()
            agents_skills.parent.mkdir(parents=True)
            agents_skills.symlink_to(external_skills, target_is_directory=True)
            (repo_codex / "skills").mkdir(parents=True)
            (external_skills / "outside.txt").write_text("outside", encoding="utf-8")

            status = migrate_home.migrate(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_codex=repo_codex,
                backup_root=backup_root,
                process_running=lambda: False,
            )

            self.assertEqual(1, status)
            self.assertTrue(agents_skills.is_symlink())
            self.assertEqual(
                "outside", (external_skills / "outside.txt").read_text(encoding="utf-8")
            )
            self.assertFalse(backup_root.exists())

    def test_migrate_rejects_missing_live_root_before_backup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            backup_root = root / "backups"
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills").mkdir(parents=True)

            status = migrate_home.migrate(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_codex=repo_codex,
                backup_root=backup_root,
                process_running=lambda: False,
            )

            self.assertEqual(1, status)
            self.assertFalse(codex_home.exists())
            self.assertFalse(backup_root.exists())

    def test_junction_command_rejects_cmd_metacharacters_before_launch(self) -> None:
        with patch.object(migrate_home.subprocess, "run") as runner:
            with self.assertRaisesRegex(OSError, "unsafe junction path"):
                migrate_home._create_junction(
                    Path("unsafe&destination"), Path("safe-target")
                )
            with self.assertRaisesRegex(OSError, "unsafe junction path"):
                migrate_home._create_junction(
                    Path("safe-destination"), Path("unsafe&target")
                )

        runner.assert_not_called()

    def test_copy_broken_directory_symlink_does_not_follow_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "missing-directory"
            source = root / "source-link"
            copy = root / "copy-link"
            source.symlink_to(target, target_is_directory=True)

            with patch.object(
                Path,
                "is_dir",
                side_effect=AssertionError("symlink target was followed"),
            ):
                migrate_home._copy_entry(source, copy)

            self.assertTrue(copy.is_symlink())
            self.assertEqual(source.readlink(), copy.readlink())
            if os.name == "nt":
                self.assertTrue(migrate_home._symlink_is_directory(copy))

    @unittest.skipUnless(os.name == "nt", "Windows symlink attribute test")
    def test_verify_copy_rejects_same_target_with_different_symlink_attributes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "missing-target"
            directory_link = root / "directory-link"
            file_link = root / "file-link"
            directory_link.symlink_to(target, target_is_directory=True)
            file_link.symlink_to(target, target_is_directory=False)

            self.assertEqual(directory_link.readlink(), file_link.readlink())
            self.assertFalse(migrate_home.verify_copy(directory_link, file_link))

    def test_unix_process_check_lowercase_hit_short_circuits(self) -> None:
        lower_hit = subprocess.CompletedProcess([], 0, "", "")
        with patch.object(migrate_home.os, "name", "posix"), patch.object(
            migrate_home.subprocess,
            "run",
            side_effect=(lower_hit, AssertionError("uppercase check must not run")),
        ) as runner:
            running = migrate_home.default_process_running()

        self.assertTrue(running)
        self.assertEqual(1, runner.call_count)
        self.assertEqual(["pgrep", "-x", "codex"], runner.call_args.args[0])

    def test_unix_process_check_detects_uppercase_exact_name(self) -> None:
        lower_miss = subprocess.CompletedProcess([], 1, "", "")
        upper_hit = subprocess.CompletedProcess([], 0, "", "")
        with patch.object(migrate_home.os, "name", "posix"), patch.object(
            migrate_home.subprocess, "run", side_effect=(lower_miss, upper_hit)
        ) as runner:
            running = migrate_home.default_process_running()

        self.assertTrue(running)
        self.assertEqual(
            [
                ["pgrep", "-x", "codex"],
                ["pgrep", "-x", "Codex"],
            ],
            [entry.args[0] for entry in runner.call_args_list],
        )

    def test_unix_process_check_returns_false_when_both_exact_names_miss(self) -> None:
        miss = subprocess.CompletedProcess([], 1, "", "")
        with patch.object(migrate_home.os, "name", "posix"), patch.object(
            migrate_home.subprocess, "run", side_effect=(miss, miss)
        ) as runner:
            running = migrate_home.default_process_running()

        self.assertFalse(running)
        self.assertEqual(2, runner.call_count)

    def test_restore_refuses_before_inspecting_backup_while_codex_is_running(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (codex_home / "live.txt").write_text("live codex", encoding="utf-8")
            (agents_skills / "live.txt").write_text(
                "live skills", encoding="utf-8"
            )

            status = migrate_home.restore(
                codex_home=codex_home,
                agents_skills=agents_skills,
                backup=root / "missing-backup",
                process_running=lambda: True,
            )

            self.assertEqual(1, status)
            self.assertEqual(
                "live codex", (codex_home / "live.txt").read_text(encoding="utf-8")
            )
            self.assertEqual(
                "live skills",
                (agents_skills / "live.txt").read_text(encoding="utf-8"),
            )

    def test_restore_rejects_incomplete_backup_without_mutating_live_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            backup = root / "backup"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (backup / "codex").mkdir(parents=True)
            (codex_home / "live.txt").write_text("live codex", encoding="utf-8")
            (agents_skills / "live.txt").write_text(
                "live skills", encoding="utf-8"
            )

            status = migrate_home.restore(
                codex_home=codex_home,
                agents_skills=agents_skills,
                backup=backup,
                process_running=lambda: False,
            )

            self.assertEqual(1, status)
            self.assertEqual(
                "live codex", (codex_home / "live.txt").read_text(encoding="utf-8")
            )
            self.assertEqual(
                "live skills",
                (agents_skills / "live.txt").read_text(encoding="utf-8"),
            )

    def test_restore_rejects_backup_root_symlink_before_live_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            real_backup = root / "real-backup"
            backup = root / "backup-link"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (real_backup / "codex").mkdir(parents=True)
            (real_backup / "agents-skills").mkdir(parents=True)
            backup.symlink_to(real_backup, target_is_directory=True)
            (codex_home / "live.txt").write_text("live codex", encoding="utf-8")
            (agents_skills / "live.txt").write_text(
                "live skills", encoding="utf-8"
            )

            status = migrate_home.restore(
                codex_home=codex_home,
                agents_skills=agents_skills,
                backup=backup,
                process_running=lambda: False,
                timestamp=lambda: "20260814-170000",
            )

            self.assertEqual(1, status)
            self.assertEqual(
                "live codex", (codex_home / "live.txt").read_text(encoding="utf-8")
            )
            self.assertEqual(
                "live skills",
                (agents_skills / "live.txt").read_text(encoding="utf-8"),
            )

    def test_restore_swaps_verified_backup_and_retains_previous_live_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            backup = root / "backup"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (backup / "codex").mkdir(parents=True)
            (backup / "agents-skills").mkdir(parents=True)
            (codex_home / "live.txt").write_text("live codex", encoding="utf-8")
            (agents_skills / "live.txt").write_text(
                "live skills", encoding="utf-8"
            )
            (backup / "codex" / "restored.txt").write_text(
                "backup codex", encoding="utf-8"
            )
            (backup / "agents-skills" / "restored.txt").write_text(
                "backup skills", encoding="utf-8"
            )
            previous_codex = codex_home.with_name(
                ".codex.pre-restore-20260814-140000"
            )
            previous_skills = agents_skills.with_name(
                "skills.pre-restore-20260814-140000"
            )
            stdout = io.StringIO()

            with redirect_stdout(stdout):
                status = migrate_home.restore(
                    codex_home=codex_home,
                    agents_skills=agents_skills,
                    backup=backup,
                    process_running=lambda: False,
                    timestamp=lambda: "20260814-140000",
                )

            self.assertEqual(0, status)
            self.assertEqual(
                "backup codex",
                (codex_home / "restored.txt").read_text(encoding="utf-8"),
            )
            self.assertEqual(
                "backup skills",
                (agents_skills / "restored.txt").read_text(encoding="utf-8"),
            )
            self.assertEqual(
                "live codex", (previous_codex / "live.txt").read_text(encoding="utf-8")
            )
            self.assertEqual(
                "live skills",
                (previous_skills / "live.txt").read_text(encoding="utf-8"),
            )
            self.assertTrue((backup / "codex" / "restored.txt").is_file())
            self.assertIn(str(previous_codex), stdout.getvalue())
            self.assertIn(str(previous_skills), stdout.getvalue())

    def test_restore_second_swap_failure_restores_both_original_live_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            backup = root / "backup"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (backup / "codex").mkdir(parents=True)
            (backup / "agents-skills").mkdir(parents=True)
            (codex_home / "live.txt").write_text("live codex", encoding="utf-8")
            (agents_skills / "live.txt").write_text(
                "live skills", encoding="utf-8"
            )
            (backup / "codex" / "restored.txt").write_text(
                "backup codex", encoding="utf-8"
            )
            (backup / "agents-skills" / "restored.txt").write_text(
                "backup skills", encoding="utf-8"
            )
            timestamp_value = "20260814-150000"
            codex_stage = codex_home.with_name(
                f".codex.restore-stage-{timestamp_value}"
            )
            skills_stage = agents_skills.with_name(
                f"skills.restore-stage-{timestamp_value}"
            )
            previous_codex = codex_home.with_name(
                f".codex.pre-restore-{timestamp_value}"
            )
            previous_skills = agents_skills.with_name(
                f"skills.pre-restore-{timestamp_value}"
            )
            failed = False

            def fail_second_swap(source: Path, destination: Path) -> None:
                nonlocal failed
                if source == skills_stage and destination == agents_skills and not failed:
                    failed = True
                    raise OSError("injected second swap failure")
                source.rename(destination)

            status = migrate_home.restore(
                codex_home=codex_home,
                agents_skills=agents_skills,
                backup=backup,
                process_running=lambda: False,
                timestamp=lambda: timestamp_value,
                rename_path=fail_second_swap,
            )

            self.assertEqual(1, status)
            self.assertEqual(
                "live codex", (codex_home / "live.txt").read_text(encoding="utf-8")
            )
            self.assertEqual(
                "live skills",
                (agents_skills / "live.txt").read_text(encoding="utf-8"),
            )
            self.assertFalse((codex_home / "restored.txt").exists())
            self.assertFalse((agents_skills / "restored.txt").exists())
            self.assertFalse(codex_stage.exists())
            self.assertFalse(skills_stage.exists())
            self.assertFalse(previous_codex.exists())
            self.assertFalse(previous_skills.exists())
            self.assertTrue((backup / "codex" / "restored.txt").is_file())

    def test_restore_stage_copy_failure_cleans_stages_without_mutating_live_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            backup = root / "backup"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (backup / "codex").mkdir(parents=True)
            (backup / "agents-skills").mkdir(parents=True)
            (codex_home / "live.txt").write_text("live codex", encoding="utf-8")
            (agents_skills / "live.txt").write_text(
                "live skills", encoding="utf-8"
            )
            (backup / "codex" / "restored.txt").write_text(
                "backup codex", encoding="utf-8"
            )
            timestamp_value = "20260814-160000"
            codex_stage = codex_home.with_name(
                f".codex.restore-stage-{timestamp_value}"
            )
            skills_stage = agents_skills.with_name(
                f"skills.restore-stage-{timestamp_value}"
            )

            def fail_second_stage_copy(source: Path, destination: Path) -> None:
                if source == backup / "agents-skills":
                    destination.mkdir()
                    (destination / "partial.txt").write_text(
                        "partial", encoding="utf-8"
                    )
                    raise OSError("injected stage copy failure")
                migrate_home._copy_tree(source, destination)

            status = migrate_home.restore(
                codex_home=codex_home,
                agents_skills=agents_skills,
                backup=backup,
                process_running=lambda: False,
                timestamp=lambda: timestamp_value,
                copy_tree=fail_second_stage_copy,
            )

            self.assertEqual(1, status)
            self.assertEqual(
                "live codex", (codex_home / "live.txt").read_text(encoding="utf-8")
            )
            self.assertEqual(
                "live skills",
                (agents_skills / "live.txt").read_text(encoding="utf-8"),
            )
            self.assertFalse(codex_stage.exists())
            self.assertFalse(skills_stage.exists())
            self.assertTrue((backup / "codex" / "restored.txt").is_file())

    def test_restore_process_start_after_verify_cleans_stages_and_keeps_live_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            backup = root / "backup"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (backup / "codex").mkdir(parents=True)
            (backup / "agents-skills").mkdir(parents=True)
            (codex_home / "live.txt").write_text("live codex", encoding="utf-8")
            (agents_skills / "live.txt").write_text(
                "live skills", encoding="utf-8"
            )
            (backup / "codex" / "restored.txt").write_text(
                "backup codex", encoding="utf-8"
            )
            (backup / "agents-skills" / "restored.txt").write_text(
                "backup skills", encoding="utf-8"
            )
            timestamp_value = "20260814-200000"
            codex_stage = codex_home.with_name(
                f".codex.restore-stage-{timestamp_value}"
            )
            skills_stage = agents_skills.with_name(
                f"skills.restore-stage-{timestamp_value}"
            )
            process_states = iter((False, True))

            status = migrate_home.restore(
                codex_home=codex_home,
                agents_skills=agents_skills,
                backup=backup,
                process_running=lambda: next(process_states),
                timestamp=lambda: timestamp_value,
            )

            self.assertEqual(1, status)
            self.assertEqual(
                "live codex", (codex_home / "live.txt").read_text(encoding="utf-8")
            )
            self.assertEqual(
                "live skills",
                (agents_skills / "live.txt").read_text(encoding="utf-8"),
            )
            self.assertFalse(codex_stage.exists())
            self.assertFalse(skills_stage.exists())
            self.assertTrue((backup / "codex" / "restored.txt").is_file())

    def test_restore_verify_exception_cleans_stages_without_mutating_live_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            backup = root / "backup"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (backup / "codex").mkdir(parents=True)
            (backup / "agents-skills").mkdir(parents=True)
            (codex_home / "live.txt").write_text("live codex", encoding="utf-8")
            (agents_skills / "live.txt").write_text(
                "live skills", encoding="utf-8"
            )
            timestamp_value = "20260814-220000"
            codex_stage = codex_home.with_name(
                f".codex.restore-stage-{timestamp_value}"
            )
            skills_stage = agents_skills.with_name(
                f"skills.restore-stage-{timestamp_value}"
            )
            stderr = io.StringIO()

            with patch.object(
                migrate_home,
                "verify_copy",
                side_effect=FileNotFoundError("injected verify disappearance"),
            ), redirect_stderr(stderr):
                status = migrate_home.restore(
                    codex_home=codex_home,
                    agents_skills=agents_skills,
                    backup=backup,
                    process_running=lambda: False,
                    timestamp=lambda: timestamp_value,
                )

            self.assertEqual(1, status)
            self.assertEqual(
                "live codex", (codex_home / "live.txt").read_text(encoding="utf-8")
            )
            self.assertEqual(
                "live skills",
                (agents_skills / "live.txt").read_text(encoding="utf-8"),
            )
            self.assertFalse(codex_stage.exists())
            self.assertFalse(skills_stage.exists())
            self.assertTrue(backup.is_dir())
            self.assertIn("injected verify disappearance", stderr.getvalue())

    def test_backup_inside_repository_root_is_rejected_before_creation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_root = root / "dotfiles"
            repo_codex = repo_root / "codex"
            backup_root = repo_root / "backups"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills").mkdir(parents=True)

            status = migrate_home.migrate(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_codex=repo_codex,
                backup_root=backup_root,
                process_running=lambda: False,
                timestamp=lambda: "20260814-100000",
            )

            self.assertEqual(1, status)
            self.assertFalse(backup_root.exists())

    def test_process_start_before_live_mutation_aborts_and_cleans_runtime_copy(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            backup_root = root / "backups"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills").mkdir(parents=True)
            (codex_home / "auth.json").write_text("runtime", encoding="utf-8")
            (agents_skills / "personal").mkdir()
            (agents_skills / "personal" / "SKILL.md").write_text(
                "personal", encoding="utf-8"
            )
            process_states = iter((False, True))

            status = migrate_home.migrate(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_codex=repo_codex,
                backup_root=backup_root,
                process_running=lambda: next(process_states),
                timestamp=lambda: "20260814-190000",
            )

            backup = backup_root / "codex-home-20260814-190000"
            self.assertEqual(1, status)
            self.assertFalse(codex_home.is_symlink())
            self.assertEqual(
                "runtime", (codex_home / "auth.json").read_text(encoding="utf-8")
            )
            self.assertFalse(agents_skills.is_symlink())
            self.assertEqual(
                "personal",
                (agents_skills / "personal" / "SKILL.md").read_text(
                    encoding="utf-8"
                ),
            )
            self.assertFalse((repo_codex / "auth.json").exists())
            self.assertTrue(backup.is_dir())

    @unittest.skipUnless(os.name == "nt", "Windows junction test")
    def test_verify_copy_compares_junction_type_and_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first_target = root / "first-target"
            second_target = root / "second-target"
            source = root / "source-junction"
            copy = root / "copy-junction"
            first_target.mkdir()
            second_target.mkdir()
            subprocess.run(
                ["cmd.exe", "/c", "mklink", "/J", str(source), str(first_target)],
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run(
                ["cmd.exe", "/c", "mklink", "/J", str(copy), str(first_target)],
                check=True,
                capture_output=True,
                text=True,
            )

            self.assertTrue(migrate_home.verify_copy(source, copy))
            os.rmdir(copy)
            subprocess.run(
                ["cmd.exe", "/c", "mklink", "/J", str(copy), str(second_target)],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertFalse(migrate_home.verify_copy(source, copy))

    def test_unknown_top_level_entry_is_backed_up_and_copied_from_stage(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            backup_root = root / "backups"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills").mkdir(parents=True)
            (codex_home / "unknown-new-state").write_text("unknown", encoding="utf-8")
            (codex_home / "hooks").mkdir()
            (codex_home / "hooks" / "legacy.sh").write_text(
                "legacy", encoding="utf-8"
            )
            staged_sources: list[Path] = []
            staged_legacy_hooks: list[bool] = []
            staging_ignore_contents: list[str | None] = []

            def copy_from_stage(source: Path, destination: Path) -> None:
                staged_sources.append(source)
                staged_legacy_hooks.append((source.parent / "hooks").exists())
                ignore = source.parents[1] / ".gitignore"
                staging_ignore_contents.append(
                    ignore.read_text(encoding="utf-8") if ignore.is_file() else None
                )
                migrate_home._copy_entry(source, destination)

            status = migrate_home.bootstrap(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_home=repo_codex,
                backup_root=backup_root,
                process_running=lambda: False,
                timestamp=lambda: "20260815-130000",
                copy_entry=copy_from_stage,
            )

            backup = backup_root / "codex-home-20260815-130000"
            self.assertEqual(0, status)
            self.assertEqual(
                "unknown",
                (backup / "codex" / "unknown-new-state").read_text(
                    encoding="utf-8"
                ),
            )
            self.assertEqual(1, len(staged_sources))
            self.assertIn("bootstrap-stage", staged_sources[0].parents[1].name)
            self.assertEqual([False], staged_legacy_hooks)
            self.assertEqual(["*\n"], staging_ignore_contents)
            self.assertEqual(
                "unknown",
                (repo_codex / "unknown-new-state").read_text(encoding="utf-8"),
            )

    def test_bootstrap_copies_unknown_runtime_and_overlays_repository_managed_paths(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_home = root / "dotfiles" / "codex"
            (codex_home / "browser").mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_home / "skills" / "managed").mkdir(parents=True)
            (codex_home / "browser" / "state.json").write_text(
                "runtime", encoding="utf-8"
            )
            (codex_home / "unknown-state").write_text(
                "unknown", encoding="utf-8"
            )
            (codex_home / "config.toml").write_text(
                "live", encoding="utf-8"
            )
            (repo_home / "config.toml").write_text(
                "managed", encoding="utf-8"
            )
            (repo_home / "skills" / "managed" / "SKILL.md").write_text(
                "managed skill", encoding="utf-8"
            )

            status = migrate_home.bootstrap(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_home=repo_home,
                backup_root=root / "backups",
                process_running=lambda: False,
                timestamp=lambda: "20260815-120000",
            )

            self.assertEqual(0, status)
            self.assertEqual(
                "runtime",
                (repo_home / "browser" / "state.json").read_text(
                    encoding="utf-8"
                ),
            )
            self.assertTrue((repo_home / "unknown-state").is_file())
            self.assertEqual(
                "managed",
                (repo_home / "config.toml").read_text(encoding="utf-8"),
            )
            self.assertEqual(
                "managed skill",
                (repo_home / "skills" / "managed" / "SKILL.md").read_text(
                    encoding="utf-8"
                ),
            )
            self.assertTrue(codex_home.is_symlink())

    def test_bootstrap_preserves_live_gitignore_without_weakening_git_boundary(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_root = root / "dotfiles"
            repo_home = repo_root / "codex"
            backup_root = root / "backups"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_home / "skills").mkdir(parents=True)
            (codex_home / "auth.json").write_text(
                "secret", encoding="utf-8"
            )
            (codex_home / ".gitignore").write_text(
                "!auth.json\n# live runtime rule\n", encoding="utf-8"
            )
            (repo_root / ".gitignore").write_text(
                "/codex/*\n!/codex/config.toml\n", encoding="utf-8"
            )
            subprocess.run(
                ["git", "init", "--quiet"],
                cwd=repo_root,
                check=True,
                capture_output=True,
                text=True,
            )

            status = migrate_home.bootstrap(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_home=repo_home,
                backup_root=backup_root,
                process_running=lambda: False,
                timestamp=lambda: "20260815-140000",
            )

            ignored = subprocess.run(
                ["git", "check-ignore", "--quiet", "--", "codex/auth.json"],
                cwd=repo_root,
                check=False,
                capture_output=True,
                text=True,
            )
            ignored_runtime_gitignore = subprocess.run(
                [
                    "git",
                    "check-ignore",
                    "--quiet",
                    "--",
                    "codex/.codex-runtime-gitignore",
                ],
                cwd=repo_root,
                check=False,
                capture_output=True,
                text=True,
            )
            backup = backup_root / "codex-home-20260815-140000"
            runtime_gitignore = repo_home / ".codex-runtime-gitignore"
            repository_gitignore = repo_home / ".gitignore"
            self.assertEqual(0, status)
            self.assertTrue(runtime_gitignore.is_file())
            self.assertEqual(
                "!auth.json\n# live runtime rule\n",
                runtime_gitignore.read_text(encoding="utf-8"),
            )
            self.assertTrue(repository_gitignore.is_file())
            self.assertNotIn(
                "!", repository_gitignore.read_text(encoding="utf-8")
            )
            self.assertEqual(0, ignored.returncode)
            self.assertEqual(0, ignored_runtime_gitignore.returncode)
            self.assertEqual(
                "!auth.json\n# live runtime rule\n",
                (backup / "codex" / ".gitignore").read_text(encoding="utf-8"),
            )
            self.assertEqual(
                "secret",
                (repo_home / "auth.json").read_text(encoding="utf-8"),
            )

    def test_bootstrap_preserves_existing_runtime_gitignore_on_name_collision(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_home = root / "dotfiles" / "codex"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_home / "skills").mkdir(parents=True)
            (codex_home / ".gitignore").write_text(
                "live gitignore", encoding="utf-8"
            )
            (codex_home / ".codex-runtime-gitignore").write_text(
                "existing runtime", encoding="utf-8"
            )

            status = migrate_home.bootstrap(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_home=repo_home,
                backup_root=root / "backups",
                process_running=lambda: False,
                timestamp=lambda: "20260815-150000",
            )

            self.assertEqual(0, status)
            self.assertEqual(
                "live gitignore",
                (repo_home / ".codex-runtime-gitignore").read_text(
                    encoding="utf-8"
                ),
            )
            collision_sidecar = (
                repo_home / ".codex-runtime-gitignore.pre-bootstrap"
            )
            self.assertTrue(collision_sidecar.is_file())
            self.assertEqual(
                "existing runtime",
                collision_sidecar.read_text(encoding="utf-8"),
            )

    def test_bootstrap_failure_restores_existing_repository_gitignore(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_home = root / "dotfiles" / "codex"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_home / "skills").mkdir(parents=True)
            (codex_home / "auth.json").write_text("secret", encoding="utf-8")
            (repo_home / ".gitignore").write_text(
                "original repository boundary", encoding="utf-8"
            )

            def fail_runtime_copy(source: Path, destination: Path) -> None:
                raise OSError("injected runtime copy failure")

            status = migrate_home.bootstrap(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_home=repo_home,
                backup_root=root / "backups",
                process_running=lambda: False,
                timestamp=lambda: "20260815-160000",
                copy_entry=fail_runtime_copy,
            )

            self.assertEqual(1, status)
            self.assertTrue((repo_home / ".gitignore").is_file())
            self.assertEqual(
                "original repository boundary",
                (repo_home / ".gitignore").read_text(encoding="utf-8"),
            )

    def test_success_migrates_models_cache_runtime_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            backup_root = root / "backups"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills").mkdir(parents=True)
            (codex_home / "models_cache.json").write_text(
                "{\"models\": []}",
                encoding="utf-8",
            )

            status = migrate_home.migrate(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_codex=repo_codex,
                backup_root=backup_root,
                process_running=lambda: False,
            )

            self.assertEqual(0, status)
            self.assertEqual(
                "{\"models\": []}",
                (repo_codex / "models_cache.json").read_text(encoding="utf-8"),
            )
            self.assertTrue(codex_home.is_symlink())

    def test_success_backs_up_copies_runtime_and_links_both_homes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            backup_root = root / "backups"
            external = root / "external"
            (codex_home / "sessions").mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills").mkdir(parents=True)
            external.mkdir()
            (external / "outside.txt").write_text("outside", encoding="utf-8")
            (codex_home / "config.toml").write_text("old config", encoding="utf-8")
            (codex_home / "auth.json").write_text("runtime auth", encoding="utf-8")
            (codex_home / "sessions" / "session.jsonl").write_text(
                "session", encoding="utf-8"
            )
            (codex_home / "sessions" / "external-link").symlink_to(
                external, target_is_directory=True
            )
            original_link_target = (
                codex_home / "sessions" / "external-link"
            ).readlink()
            original_junction_target = None
            if os.name == "nt":
                junction = codex_home / "sessions" / "external-junction"
                subprocess.run(
                    ["cmd.exe", "/c", "mklink", "/J", str(junction), str(external)],
                    check=True,
                    capture_output=True,
                    text=True,
                )
                original_junction_target = os.readlink(junction)
            (agents_skills / "old-skill").mkdir()
            (agents_skills / "old-skill" / "SKILL.md").write_text(
                "old skill", encoding="utf-8"
            )
            (repo_codex / "config.toml").write_text(
                "managed config", encoding="utf-8"
            )

            status = migrate_home.migrate(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_codex=repo_codex,
                backup_root=backup_root,
                process_running=lambda: False,
                timestamp=lambda: "20260813-120000",
            )

            backup = backup_root / "codex-home-20260813-120000"
            self.assertEqual(0, status)
            self.assertTrue(codex_home.is_symlink())
            self.assertEqual(repo_codex.resolve(), codex_home.resolve())
            self.assertTrue(agents_skills.is_symlink())
            self.assertEqual((repo_codex / "skills").resolve(), agents_skills.resolve())
            self.assertEqual(
                "managed config", (repo_codex / "config.toml").read_text(encoding="utf-8")
            )
            self.assertEqual("runtime auth", (repo_codex / "auth.json").read_text(encoding="utf-8"))
            self.assertEqual(
                "session",
                (repo_codex / "sessions" / "session.jsonl").read_text(encoding="utf-8"),
            )
            backup_link = backup / "codex" / "sessions" / "external-link"
            self.assertTrue(backup_link.is_symlink())
            self.assertEqual(original_link_target, backup_link.readlink())
            if original_junction_target is not None:
                backup_junction = backup / "codex" / "sessions" / "external-junction"
                self.assertTrue(migrate_home._is_junction(backup_junction))
                self.assertEqual(original_junction_target, os.readlink(backup_junction))
            self.assertEqual(
                "old skill",
                (backup / "agents-skills" / "old-skill" / "SKILL.md").read_text(
                    encoding="utf-8"
                ),
            )
            self.assertEqual(
                "old config",
                (backup / "live-codex-at-commit" / "config.toml").read_text(
                    encoding="utf-8"
                ),
            )
            self.assertEqual(
                "old skill",
                (
                    backup
                    / "live-agents-skills-at-commit"
                    / "old-skill"
                    / "SKILL.md"
                ).read_text(encoding="utf-8"),
            )

    def test_success_moves_nested_system_runtime_without_overwriting_personal_skill(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            system_runtime = codex_home / "skills" / ".system"
            external = root / "external"
            system_runtime.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills" / "personal").mkdir(parents=True)
            external.mkdir()
            (system_runtime / "runtime.txt").write_text("runtime", encoding="utf-8")
            (system_runtime / "external-link").symlink_to(
                external, target_is_directory=True
            )
            original_link_target = (system_runtime / "external-link").readlink()
            (codex_home / "skills" / "personal").mkdir()
            (codex_home / "skills" / "personal" / "SKILL.md").write_text(
                "old personal", encoding="utf-8"
            )
            (repo_codex / "skills" / "personal" / "SKILL.md").write_text(
                "managed personal", encoding="utf-8"
            )

            status = migrate_home.migrate(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_codex=repo_codex,
                backup_root=root / "backups",
                process_running=lambda: False,
                timestamp=lambda: "20260814-110000",
            )

            copied_system = repo_codex / "skills" / ".system"
            self.assertEqual(0, status)
            self.assertEqual(
                "runtime", (copied_system / "runtime.txt").read_text(encoding="utf-8")
            )
            self.assertTrue((copied_system / "external-link").is_symlink())
            self.assertEqual(
                original_link_target,
                (copied_system / "external-link").readlink(),
            )
            self.assertEqual(
                "managed personal",
                (repo_codex / "skills" / "personal" / "SKILL.md").read_text(
                    encoding="utf-8"
                ),
            )

    def test_nested_system_is_not_followed_through_skills_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            external_skills = root / "external-skills"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills").mkdir(parents=True)
            (external_skills / ".system").mkdir(parents=True)
            (external_skills / ".system" / "runtime.txt").write_text(
                "external runtime", encoding="utf-8"
            )
            (codex_home / "skills").symlink_to(
                external_skills, target_is_directory=True
            )

            status = migrate_home.migrate(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_codex=repo_codex,
                backup_root=root / "backups",
                process_running=lambda: False,
                timestamp=lambda: "20260814-120000",
            )

            self.assertEqual(0, status)
            self.assertFalse((repo_codex / "skills" / ".system").exists())
            self.assertEqual(
                "external runtime",
                (external_skills / ".system" / "runtime.txt").read_text(
                    encoding="utf-8"
                ),
            )

    def test_second_link_failure_rolls_back_live_and_journaled_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            backup_root = root / "backups"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills").mkdir(parents=True)
            (codex_home / "config.toml").write_text("old config", encoding="utf-8")
            (codex_home / "auth.json").write_text("runtime auth", encoding="utf-8")
            (agents_skills / "old-skill").mkdir()
            (agents_skills / "old-skill" / "SKILL.md").write_text(
                "old skill", encoding="utf-8"
            )
            (repo_codex / "config.toml").write_text(
                "managed config", encoding="utf-8"
            )
            calls = 0

            def fail_second_link(source: Path, destination: Path) -> None:
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError("second link failed")
                os.symlink(source, destination, target_is_directory=True)

            def snapshot_with_late_updates(source: Path, destination: Path) -> None:
                if source == codex_home:
                    (source / "late-codex.txt").write_text(
                        "latest codex", encoding="utf-8"
                    )
                if source == agents_skills:
                    (source / "late-skills.txt").write_text(
                        "latest skills", encoding="utf-8"
                    )
                source.rename(destination)

            status = migrate_home.migrate(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_codex=repo_codex,
                backup_root=backup_root,
                process_running=lambda: False,
                timestamp=lambda: "20260813-130000",
                link_directory=fail_second_link,
                rename_path=snapshot_with_late_updates,
            )

            backup = backup_root / "codex-home-20260813-130000"
            self.assertEqual(1, status)
            self.assertTrue(codex_home.is_dir())
            self.assertFalse(codex_home.is_symlink())
            self.assertEqual("old config", (codex_home / "config.toml").read_text(encoding="utf-8"))
            self.assertEqual("runtime auth", (codex_home / "auth.json").read_text(encoding="utf-8"))
            self.assertEqual(
                "latest codex",
                (codex_home / "late-codex.txt").read_text(encoding="utf-8"),
            )
            self.assertTrue(agents_skills.is_dir())
            self.assertFalse(agents_skills.is_symlink())
            self.assertEqual(
                "old skill",
                (agents_skills / "old-skill" / "SKILL.md").read_text(encoding="utf-8"),
            )
            self.assertEqual(
                "latest skills",
                (agents_skills / "late-skills.txt").read_text(encoding="utf-8"),
            )
            self.assertFalse((repo_codex / "auth.json").exists())
            self.assertEqual("managed config", (repo_codex / "config.toml").read_text(encoding="utf-8"))
            self.assertTrue(backup.is_dir())

    def test_second_live_snapshot_rename_failure_restores_first_snapshot_update(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            backup_root = root / "backups"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills").mkdir(parents=True)
            (codex_home / "auth.json").write_text("runtime", encoding="utf-8")
            (agents_skills / "personal").mkdir()
            (agents_skills / "personal" / "SKILL.md").write_text(
                "personal", encoding="utf-8"
            )

            def fail_second_snapshot_rename(source: Path, destination: Path) -> None:
                if source == codex_home:
                    (source / "late-update.txt").write_text(
                        "latest", encoding="utf-8"
                    )
                    source.rename(destination)
                    return
                if source == agents_skills:
                    raise OSError("injected second snapshot rename failure")
                source.rename(destination)

            status = migrate_home.migrate(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_codex=repo_codex,
                backup_root=backup_root,
                process_running=lambda: False,
                timestamp=lambda: "20260814-210000",
                rename_path=fail_second_snapshot_rename,
            )

            backup = backup_root / "codex-home-20260814-210000"
            self.assertEqual(1, status)
            self.assertFalse(codex_home.is_symlink())
            self.assertEqual(
                "latest", (codex_home / "late-update.txt").read_text(encoding="utf-8")
            )
            self.assertFalse(agents_skills.is_symlink())
            self.assertEqual(
                "personal",
                (agents_skills / "personal" / "SKILL.md").read_text(
                    encoding="utf-8"
                ),
            )
            self.assertFalse((repo_codex / "auth.json").exists())
            self.assertTrue((backup / "codex" / "auth.json").is_file())
            self.assertFalse((backup / "live-codex-at-commit").exists())

    def test_journal_cleanup_failure_still_restores_both_live_directories(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            backup_root = root / "backups"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills").mkdir(parents=True)
            (codex_home / "config.toml").write_text("old config", encoding="utf-8")
            (codex_home / "auth.json").write_text("runtime auth", encoding="utf-8")
            (agents_skills / "old-skill").mkdir()
            (agents_skills / "old-skill" / "SKILL.md").write_text(
                "old skill", encoding="utf-8"
            )
            calls = 0

            def fail_second_link(source: Path, destination: Path) -> None:
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError("second link failed")
                os.symlink(source, destination, target_is_directory=True)

            def fail_journal_cleanup(path: Path) -> None:
                if path == repo_codex / "auth.json":
                    raise OSError("injected journal cleanup failure")
                migrate_home._remove_path(path)

            stderr = io.StringIO()
            with redirect_stderr(stderr):
                status = migrate_home.migrate(
                    codex_home=codex_home,
                    agents_skills=agents_skills,
                    repo_codex=repo_codex,
                    backup_root=backup_root,
                    process_running=lambda: False,
                    timestamp=lambda: "20260814-130000",
                    link_directory=fail_second_link,
                    remove_path=fail_journal_cleanup,
                )

            backup = backup_root / "codex-home-20260814-130000"
            self.assertEqual(1, status)
            self.assertFalse(codex_home.is_symlink())
            self.assertEqual(
                "old config", (codex_home / "config.toml").read_text(encoding="utf-8")
            )
            self.assertFalse(agents_skills.is_symlink())
            self.assertEqual(
                "old skill",
                (agents_skills / "old-skill" / "SKILL.md").read_text(
                    encoding="utf-8"
                ),
            )
            self.assertEqual(
                "runtime auth", (repo_codex / "auth.json").read_text(encoding="utf-8")
            )
            self.assertTrue(backup.is_dir())
            self.assertIn(str(repo_codex / "auth.json"), stderr.getvalue())
            self.assertIn("injected journal cleanup failure", stderr.getvalue())

    def test_plugin_failure_after_commit_keeps_verified_links(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills").mkdir(parents=True)
            (codex_home / "config.toml").write_text("old config", encoding="utf-8")
            (repo_codex / "config.toml").write_text("managed config", encoding="utf-8")

            status = migrate_home.migrate(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_codex=repo_codex,
                backup_root=root / "backups",
                process_running=lambda: False,
                timestamp=lambda: "20260813-140000",
                plugin_reconciler=lambda: 7,
            )

            self.assertEqual(7, status)
            self.assertTrue(codex_home.is_symlink())
            self.assertEqual(repo_codex.resolve(), codex_home.resolve())
            self.assertTrue(agents_skills.is_symlink())
            self.assertEqual((repo_codex / "skills").resolve(), agents_skills.resolve())

    def test_migrate_notifies_filesystem_commit_once_before_plugin_reconcile(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills").mkdir(parents=True)
            events: list[str] = []

            def reconcile_plugins() -> int:
                events.append("plugins")
                return 7

            status = migrate_home.migrate(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_codex=repo_codex,
                backup_root=root / "backups",
                process_running=lambda: False,
                timestamp=lambda: "20260814-180000",
                plugin_reconciler=reconcile_plugins,
                on_filesystem_commit=lambda: events.append("filesystem"),
            )

            self.assertEqual(7, status)
            self.assertEqual(["filesystem", "plugins"], events)

    def test_migrate_plugin_launch_exception_returns_nonzero_after_commit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills").mkdir(parents=True)
            events: list[str] = []

            def fail_plugin_launch() -> int:
                raise FileNotFoundError("injected plugin launcher missing")

            status = migrate_home.migrate(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_codex=repo_codex,
                backup_root=root / "backups",
                process_running=lambda: False,
                timestamp=lambda: "20260814-230000",
                plugin_reconciler=fail_plugin_launch,
                on_filesystem_commit=lambda: events.append("filesystem"),
            )

            self.assertEqual(1, status)
            self.assertEqual(["filesystem"], events)
            self.assertTrue(codex_home.is_symlink())
            self.assertTrue(agents_skills.is_symlink())

    def test_main_refuses_before_migration_while_codex_is_running(self) -> None:
        with patch.object(
            migrate_home, "default_process_running", return_value=True
        ), patch.object(migrate_home, "migrate") as migrate_mock:
            status = migrate_home.main([])

        self.assertEqual(1, status)
        migrate_mock.assert_not_called()

    def test_main_wires_restore_backup_after_process_gate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake_home = root / "home"
            backup = root / "backup"
            with patch.object(
                migrate_home, "default_process_running", return_value=False
            ) as process_detector, patch.object(
                migrate_home.Path, "home", return_value=fake_home
            ), patch.object(
                migrate_home, "restore", return_value=0
            ) as restore_mock:
                status = migrate_home.main(["--restore", str(backup)])

        self.assertEqual(0, status)
        call = restore_mock.call_args.kwargs
        self.assertEqual(fake_home / ".codex", call["codex_home"])
        self.assertEqual(fake_home / ".agents" / "skills", call["agents_skills"])
        self.assertEqual(backup, call["backup"])
        self.assertIs(process_detector, call["process_running"])

    def test_main_restore_rechecks_real_process_detector_before_live_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake_home = root / "home"
            codex_home = fake_home / ".codex"
            agents_skills = fake_home / ".agents" / "skills"
            backup = root / "backup"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (backup / "codex").mkdir(parents=True)
            (backup / "agents-skills").mkdir(parents=True)
            (codex_home / "live.txt").write_text("live codex", encoding="utf-8")
            (agents_skills / "live.txt").write_text(
                "live skills", encoding="utf-8"
            )
            (backup / "codex" / "restored.txt").write_text(
                "backup codex", encoding="utf-8"
            )
            (backup / "agents-skills" / "restored.txt").write_text(
                "backup skills", encoding="utf-8"
            )

            with patch.object(
                migrate_home,
                "default_process_running",
                side_effect=(False, False, True),
            ) as process_detector, patch.object(
                migrate_home.Path, "home", return_value=fake_home
            ):
                status = migrate_home.main(["--restore", str(backup)])

            self.assertEqual(1, status)
            self.assertEqual(3, process_detector.call_count)
            self.assertEqual(
                "live codex", (codex_home / "live.txt").read_text(encoding="utf-8")
            )
            self.assertEqual(
                "live skills",
                (agents_skills / "live.txt").read_text(encoding="utf-8"),
            )
            self.assertEqual([], list(fake_home.glob(".codex.restore-stage-*")))
            self.assertEqual(
                [], list((fake_home / ".agents").glob("skills.restore-stage-*"))
            )
            self.assertTrue((backup / "codex" / "restored.txt").is_file())

    def test_main_wires_real_home_repo_backup_and_plugin_step(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fake_home = Path(directory) / "home"
            with patch.object(
                migrate_home, "default_process_running", return_value=False
            ), patch.object(
                migrate_home.Path, "home", return_value=fake_home
            ), patch.object(
                migrate_home, "migrate", return_value=0
            ) as migrate_mock:
                status = migrate_home.main([])

        self.assertEqual(0, status)
        call = migrate_mock.call_args.kwargs
        self.assertEqual(fake_home / ".codex", call["codex_home"])
        self.assertEqual(fake_home / ".agents" / "skills", call["agents_skills"])
        self.assertEqual(CODEX_DIR.parent / "codex", call["repo_codex"])
        self.assertEqual(fake_home / ".codex-backups", call["backup_root"])
        self.assertFalse(call["process_running"]())
        self.assertTrue(callable(call["plugin_reconciler"]))

    def test_main_prints_exact_restore_command_after_filesystem_failure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fake_home = Path(directory) / "home"

            def fail_after_backup(**kwargs: object) -> int:
                backup_root = kwargs["backup_root"]
                timestamp = kwargs["timestamp"]
                assert isinstance(backup_root, Path)
                backup = backup_root / f"codex-home-{timestamp()}"
                backup.mkdir(parents=True)
                return 1

            stderr = io.StringIO()
            with patch.object(
                migrate_home, "default_process_running", return_value=False
            ), patch.object(
                migrate_home.Path, "home", return_value=fake_home
            ), patch.object(
                migrate_home, "migrate", side_effect=fail_after_backup
            ), redirect_stderr(stderr):
                status = migrate_home.main([])

            backups = list((fake_home / ".codex-backups").iterdir())
            self.assertEqual(1, len(backups))
            expected = (
                f'bash "{CODEX_DIR / "bootstrap-home.sh"}" '
                f'--restore "{backups[0]}"'
            )
            self.assertEqual(1, status)
            self.assertIn(expected, stderr.getvalue())

    def test_main_plugin_failure_uses_commit_callback_and_prints_retry_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake_home = root / "home"
            link_target = root / "repo-codex"
            (link_target / "skills").mkdir(parents=True)

            def fail_plugins_after_commit(**kwargs: object) -> int:
                backup_root = kwargs["backup_root"]
                timestamp = kwargs["timestamp"]
                assert isinstance(backup_root, Path)
                backup = backup_root / f"codex-home-{timestamp()}"
                backup.mkdir(parents=True)
                codex_home = fake_home / ".codex"
                agents_skills = fake_home / ".agents" / "skills"
                codex_home.parent.mkdir(parents=True, exist_ok=True)
                agents_skills.parent.mkdir(parents=True, exist_ok=True)
                codex_home.symlink_to(link_target, target_is_directory=True)
                agents_skills.symlink_to(
                    link_target / "skills", target_is_directory=True
                )
                kwargs["on_filesystem_commit"]()
                return 7

            stderr = io.StringIO()
            with patch.object(
                migrate_home, "default_process_running", return_value=False
            ), patch.object(
                migrate_home.Path, "home", return_value=fake_home
            ), patch.object(
                migrate_home, "migrate", side_effect=fail_plugins_after_commit
            ), redirect_stderr(stderr):
                status = migrate_home.main([])

            self.assertEqual(7, status)
            self.assertIn(
                f'bash "{CODEX_DIR / "install-plugins.sh"}"', stderr.getvalue()
            )
            self.assertNotIn("--restore", stderr.getvalue())

    def test_main_plugin_subprocess_exception_prints_retry_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fake_home = Path(directory) / "home"

            def launch_plugins_after_commit(**kwargs: object) -> int:
                kwargs["on_filesystem_commit"]()
                return kwargs["plugin_reconciler"]()

            stderr = io.StringIO()
            with patch.object(
                migrate_home, "default_process_running", return_value=False
            ), patch.object(
                migrate_home.Path, "home", return_value=fake_home
            ), patch.object(
                migrate_home, "migrate", side_effect=launch_plugins_after_commit
            ), patch.object(
                migrate_home.subprocess,
                "run",
                side_effect=FileNotFoundError("injected bash missing"),
            ), redirect_stderr(stderr):
                status = migrate_home.main([])

            self.assertEqual(1, status)
            self.assertIn("injected bash missing", stderr.getvalue())
            self.assertIn(
                f'bash "{CODEX_DIR / "install-plugins.sh"}"', stderr.getvalue()
            )
            self.assertNotIn("--restore", stderr.getvalue())

    def test_main_filesystem_failure_with_residual_links_prints_restore_command(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake_home = root / "home"
            link_target = root / "repo-codex"
            (link_target / "skills").mkdir(parents=True)

            def fail_rollback_with_residual_links(**kwargs: object) -> int:
                backup_root = kwargs["backup_root"]
                timestamp = kwargs["timestamp"]
                assert isinstance(backup_root, Path)
                backup = backup_root / f"codex-home-{timestamp()}"
                backup.mkdir(parents=True)
                codex_home = fake_home / ".codex"
                agents_skills = fake_home / ".agents" / "skills"
                codex_home.parent.mkdir(parents=True, exist_ok=True)
                agents_skills.parent.mkdir(parents=True, exist_ok=True)
                codex_home.symlink_to(link_target, target_is_directory=True)
                agents_skills.symlink_to(
                    link_target / "skills", target_is_directory=True
                )
                return 1

            stderr = io.StringIO()
            with patch.object(
                migrate_home, "default_process_running", return_value=False
            ), patch.object(
                migrate_home.Path, "home", return_value=fake_home
            ), patch.object(
                migrate_home,
                "migrate",
                side_effect=fail_rollback_with_residual_links,
            ), redirect_stderr(stderr):
                status = migrate_home.main([])

            backups = list((fake_home / ".codex-backups").iterdir())
            self.assertEqual(1, len(backups))
            expected = (
                f'bash "{CODEX_DIR / "bootstrap-home.sh"}" '
                f'--restore "{backups[0]}"'
            )
            self.assertEqual(1, status)
            self.assertIn(expected, stderr.getvalue())
            self.assertNotIn("install-plugins.sh", stderr.getvalue())

    def test_broken_symlink_collision_is_rejected_before_backup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            backup_root = root / "backups"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills").mkdir(parents=True)
            (codex_home / "auth.json").write_text("runtime", encoding="utf-8")
            collision = repo_codex / "auth.json"
            collision.symlink_to(repo_codex / "missing-target")

            status = migrate_home.migrate(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_codex=repo_codex,
                backup_root=backup_root,
                process_running=lambda: False,
            )

            self.assertEqual(1, status)
            self.assertTrue(collision.is_symlink())
            self.assertFalse(backup_root.exists())
            self.assertTrue((codex_home / "auth.json").is_file())

    def test_partial_runtime_copy_is_journaled_and_cleaned(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            codex_home = root / "home" / ".codex"
            agents_skills = root / "home" / ".agents" / "skills"
            repo_codex = root / "dotfiles" / "codex"
            backup_root = root / "backups"
            codex_home.mkdir(parents=True)
            agents_skills.mkdir(parents=True)
            (repo_codex / "skills").mkdir(parents=True)
            (codex_home / "auth.json").write_text("runtime", encoding="utf-8")
            (repo_codex / "config.toml").write_text("managed", encoding="utf-8")

            def partial_copy(source: Path, destination: Path) -> None:
                destination.write_text("partial", encoding="utf-8")
                raise OSError("copy failed")

            status = migrate_home.migrate(
                codex_home=codex_home,
                agents_skills=agents_skills,
                repo_codex=repo_codex,
                backup_root=backup_root,
                process_running=lambda: False,
                timestamp=lambda: "20260813-150000",
                copy_entry=partial_copy,
            )

            self.assertEqual(1, status)
            self.assertTrue((codex_home / "auth.json").is_file())
            self.assertFalse((repo_codex / "auth.json").exists())
            self.assertEqual("managed", (repo_codex / "config.toml").read_text(encoding="utf-8"))
            self.assertTrue(
                (backup_root / "codex-home-20260813-150000" / "codex" / "auth.json").is_file()
            )


if __name__ == "__main__":
    unittest.main()
