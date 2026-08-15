from pathlib import Path
from contextlib import redirect_stderr, redirect_stdout
import io
import os
import sys
import tempfile
import unittest
from unittest.mock import patch


CODEX_TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CODEX_TOOLS))

import promote_worktree_home as promotion


class PromoteWorktreeHomeTest(unittest.TestCase):
    def make_layout(self, root: Path) -> dict[str, Path]:
        repo = root / "dotfiles"
        (repo / ".git").mkdir(parents=True)
        worktree = repo / ".worktrees" / "codex-home-tools-split"
        worktree.mkdir(parents=True)
        (worktree / ".git").write_text("gitdir: linked-worktree", encoding="utf-8")
        source = worktree / "codex"
        (source / "skills" / "runtime-skill").mkdir(parents=True)
        (source / "auth.json").write_text("runtime auth", encoding="utf-8")
        (source / "skills" / "runtime-skill" / "SKILL.md").write_text(
            "runtime skill", encoding="utf-8"
        )
        main_home = repo / "codex"
        (main_home / "skills" / "managed-skill").mkdir(parents=True)
        (main_home / "config.toml").write_text("managed config", encoding="utf-8")
        user_home = root / "home"
        (user_home / ".agents").mkdir(parents=True)
        live_home = user_home / ".codex"
        live_skills = user_home / ".agents" / "skills"
        os.symlink(source, live_home, target_is_directory=True)
        os.symlink(source / "skills", live_skills, target_is_directory=True)
        return {
            "repo": repo,
            "source": source,
            "main_home": main_home,
            "user_home": user_home,
            "live_home": live_home,
            "live_skills": live_skills,
            "backup_root": root / "external-backups",
        }

    def test_promotes_full_home_and_repoints_both_links(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            paths = self.make_layout(Path(directory))

            backup = promotion.promote(
                repo_root=paths["repo"],
                user_home=paths["user_home"],
                backup_root=paths["backup_root"],
                timestamp=lambda: "20260816-120000",
            )

            self.assertEqual(
                "runtime auth",
                (paths["main_home"] / "auth.json").read_text(encoding="utf-8"),
            )
            self.assertEqual(
                "runtime skill",
                (
                    paths["main_home"]
                    / "skills"
                    / "runtime-skill"
                    / "SKILL.md"
                ).read_text(encoding="utf-8"),
            )
            self.assertEqual(paths["main_home"].resolve(), paths["live_home"].resolve())
            self.assertEqual(
                (paths["main_home"] / "skills").resolve(),
                paths["live_skills"].resolve(),
            )
            self.assertTrue(paths["live_home"].is_symlink())
            self.assertTrue(paths["live_skills"].is_symlink())
            self.assertEqual(
                "managed config",
                (backup / "main-codex-before-promotion" / "config.toml").read_text(
                    encoding="utf-8"
                ),
            )
            self.assertEqual(
                "runtime auth",
                (backup / "worktree-codex" / "auth.json").read_text(
                    encoding="utf-8"
                ),
            )
            self.assertTrue((paths["source"] / "auth.json").is_file())
            self.assertEqual([], list(paths["repo"].glob(".codex.promote-*")))

    def test_main_refuses_while_codex_is_running(self) -> None:
        stderr = io.StringIO()
        with patch.object(
            promotion, "default_process_running", return_value=True
        ), patch.object(promotion, "promote") as promote, redirect_stderr(stderr):
            status = promotion.main([])

        self.assertEqual(1, status)
        promote.assert_not_called()
        self.assertIn("close Codex before promotion", stderr.getvalue())

    def test_refuses_source_without_worktree_metadata_before_backup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            paths = self.make_layout(Path(directory))
            (paths["source"].parent / ".git").unlink()

            with self.assertRaisesRegex(promotion.PromotionError, "linked worktree"):
                promotion.promote(
                    repo_root=paths["repo"],
                    user_home=paths["user_home"],
                    backup_root=paths["backup_root"],
                    timestamp=lambda: "20260816-120000",
                )

            self.assertFalse(paths["backup_root"].exists())
            self.assertEqual(
                "managed config",
                (paths["main_home"] / "config.toml").read_text(encoding="utf-8"),
            )

    def test_refuses_junction_source_before_backup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            paths = self.make_layout(Path(directory))

            with patch.object(
                promotion,
                "_is_junction",
                side_effect=lambda path: path == paths["source"],
            ):
                with self.assertRaisesRegex(promotion.PromotionError, "real directory"):
                    promotion.promote(
                        repo_root=paths["repo"],
                        user_home=paths["user_home"],
                        backup_root=paths["backup_root"],
                        timestamp=lambda: "20260816-120000",
                    )

            self.assertFalse(paths["backup_root"].exists())

    def test_refuses_unexpected_live_skills_link_before_backup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            paths = self.make_layout(Path(directory))
            unexpected = Path(directory) / "unexpected-skills"
            unexpected.mkdir()
            paths["live_skills"].unlink()
            os.symlink(unexpected, paths["live_skills"], target_is_directory=True)

            with self.assertRaisesRegex(promotion.PromotionError, "live shared skills"):
                promotion.promote(
                    repo_root=paths["repo"],
                    user_home=paths["user_home"],
                    backup_root=paths["backup_root"],
                    timestamp=lambda: "20260816-120000",
                )

            self.assertFalse(paths["backup_root"].exists())
            self.assertEqual(unexpected.resolve(), paths["live_skills"].resolve())

    def test_link_switch_failure_rolls_back_and_retains_recovery_copies(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            paths = self.make_layout(Path(directory))
            real_symlink = os.symlink

            def fail_promoted_home_link(
                target: str | os.PathLike[str],
                link: str | os.PathLike[str],
                target_is_directory: bool = False,
            ) -> None:
                if (
                    Path(target) == paths["main_home"]
                    and ".codex.promote-new-" in Path(link).name
                ):
                    raise OSError("injected home link failure")
                real_symlink(
                    target,
                    link,
                    target_is_directory=target_is_directory,
                )

            with patch.object(
                promotion.os, "symlink", side_effect=fail_promoted_home_link
            ):
                with self.assertRaisesRegex(
                    promotion.PromotionError, "injected home link failure"
                ):
                    promotion.promote(
                        repo_root=paths["repo"],
                        user_home=paths["user_home"],
                        backup_root=paths["backup_root"],
                        timestamp=lambda: "20260816-120000",
                    )

            self.assertEqual(paths["source"].resolve(), paths["live_home"].resolve())
            self.assertEqual(
                (paths["source"] / "skills").resolve(),
                paths["live_skills"].resolve(),
            )
            self.assertEqual(
                "managed config",
                (paths["main_home"] / "config.toml").read_text(encoding="utf-8"),
            )
            backup = paths["backup_root"] / "codex-home-promotion-20260816-120000"
            self.assertTrue((backup / "worktree-codex" / "auth.json").is_file())
            stages = list(paths["repo"].glob(".codex.promote-stage-*"))
            self.assertEqual(1, len(stages))
            self.assertTrue((stages[0] / "auth.json").is_file())
            self.assertEqual([], list(paths["repo"].glob(".codex.promote-rollback-*")))

    def test_symlink_creation_failure_preserves_original_links(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            paths = self.make_layout(Path(directory))

            with patch.object(
                promotion.os,
                "symlink",
                side_effect=OSError("symlink privilege unavailable"),
            ):
                with self.assertRaisesRegex(
                    promotion.PromotionError, "symlink privilege unavailable"
                ):
                    promotion.promote(
                        repo_root=paths["repo"],
                        user_home=paths["user_home"],
                        backup_root=paths["backup_root"],
                        timestamp=lambda: "20260816-120000",
                    )

            self.assertTrue(paths["live_home"].is_symlink())
            self.assertTrue(paths["live_skills"].is_symlink())
            self.assertEqual(paths["source"].resolve(), paths["live_home"].resolve())
            self.assertEqual(
                (paths["source"] / "skills").resolve(),
                paths["live_skills"].resolve(),
            )

    def test_cleanup_failure_keeps_successful_cutover_and_warns(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            paths = self.make_layout(Path(directory))
            stderr = io.StringIO()

            with patch.object(
                promotion,
                "_remove_path",
                side_effect=OSError("rollback cleanup denied"),
            ), redirect_stderr(stderr):
                backup = promotion.promote(
                    repo_root=paths["repo"],
                    user_home=paths["user_home"],
                    backup_root=paths["backup_root"],
                    timestamp=lambda: "20260816-120000",
                )

            self.assertTrue((backup / "main-codex-before-promotion").is_dir())
            self.assertEqual(paths["main_home"].resolve(), paths["live_home"].resolve())
            self.assertEqual(
                (paths["main_home"] / "skills").resolve(),
                paths["live_skills"].resolve(),
            )
            self.assertEqual(1, len(list(paths["repo"].glob(".codex.promote-rollback-*"))))
            self.assertIn("cleanup retained artifacts", stderr.getvalue())

    def test_stage_verification_failure_never_starts_cutover(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            paths = self.make_layout(Path(directory))
            with patch.object(
                promotion, "verify_copy", side_effect=(True, True, False)
            ):
                with self.assertRaisesRegex(
                    promotion.PromotionError, "staged Codex home verification failed"
                ):
                    promotion.promote(
                        repo_root=paths["repo"],
                        user_home=paths["user_home"],
                        backup_root=paths["backup_root"],
                        timestamp=lambda: "20260816-120000",
                    )

            self.assertEqual(paths["source"].resolve(), paths["live_home"].resolve())
            self.assertEqual(
                (paths["source"] / "skills").resolve(),
                paths["live_skills"].resolve(),
            )
            self.assertEqual(
                "managed config",
                (paths["main_home"] / "config.toml").read_text(encoding="utf-8"),
            )
            self.assertEqual(1, len(list(paths["repo"].glob(".codex.promote-stage-*"))))

    def test_main_wires_repository_home_and_external_backup(self) -> None:
        fake_home = Path("C:/temporary-user-home")
        backup = fake_home / ".codex-backups" / "retained"
        stdout = io.StringIO()
        with patch.object(
            promotion, "default_process_running", return_value=False
        ), patch.object(
            promotion.Path, "home", return_value=fake_home
        ), patch.object(
            promotion, "promote", return_value=backup
        ) as promote, redirect_stdout(stdout):
            status = promotion.main([])

        self.assertEqual(0, status)
        promote.assert_called_once_with(
            repo_root=Path(promotion.__file__).resolve().parent.parent,
            user_home=fake_home,
            backup_root=fake_home / ".codex-backups",
        )
        self.assertIn(str(backup), stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
