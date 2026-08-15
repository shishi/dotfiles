#!/usr/bin/env python3
from datetime import datetime
import os
from pathlib import Path
import re
import sys
from typing import Callable

from bootstrap_home import (
    _copy_tree,
    _is_junction,
    _lexists,
    _remove_path,
    default_process_running,
    verify_copy,
)


WORKTREE_NAME = "codex-home-tools-split"


class PromotionError(RuntimeError):
    pass


def _default_timestamp() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def _expected_paths(repo_root: Path, user_home: Path) -> tuple[Path, Path, Path, Path]:
    source = repo_root / ".worktrees" / WORKTREE_NAME / "codex"
    main_home = repo_root / "codex"
    live_home = user_home / ".codex"
    live_skills = user_home / ".agents" / "skills"
    return source, main_home, live_home, live_skills


def _require_directory(path: Path, description: str) -> None:
    if path.is_symlink() or _is_junction(path) or not path.is_dir():
        raise PromotionError(f"{description} must be a real directory: {path}")


def _require_link(path: Path, expected: Path, description: str) -> str:
    if not path.is_symlink():
        raise PromotionError(f"{description} must be a symlink: {path}")
    try:
        actual = path.resolve(strict=True)
        expected_resolved = expected.resolve(strict=True)
    except OSError as error:
        raise PromotionError(f"{description} cannot be resolved: {path}: {error}") from error
    if os.path.normcase(str(actual)) != os.path.normcase(str(expected_resolved)):
        raise PromotionError(
            f"{description} points to {actual}, expected {expected_resolved}"
        )
    return os.readlink(path)


def _validated_timestamp(timestamp: Callable[[], str]) -> str:
    value = timestamp()
    if not re.fullmatch(r"[0-9]{8}-[0-9]{6}", value):
        raise PromotionError(f"invalid promotion timestamp: {value!r}")
    return value


def _stage_link(path: Path, target: Path) -> None:
    os.symlink(target, path, target_is_directory=True)
    _require_link(path, target, f"staged link {path}")


def _swap_staged_link(
    live: Path,
    expected_old: Path,
    staged: Path,
    snapshot: Path,
    new_target: Path,
) -> None:
    _require_link(live, expected_old, f"live link {live}")
    live.rename(snapshot)
    try:
        staged.rename(live)
    except BaseException:
        snapshot.rename(live)
        raise
    _require_link(live, new_target, f"promoted link {live}")


def _rollback_link_swap(live: Path, staged: Path, snapshot: Path) -> None:
    if not _lexists(snapshot):
        return
    if _lexists(live):
        if _lexists(staged):
            raise PromotionError(f"link rollback stage already exists: {staged}")
        live.rename(staged)
    snapshot.rename(live)


def promote(
    *,
    repo_root: Path,
    user_home: Path,
    backup_root: Path,
    timestamp: Callable[[], str] = _default_timestamp,
) -> Path:
    repo_root = repo_root.resolve(strict=True)
    user_home = user_home.resolve(strict=True)
    backup_root = backup_root.resolve(strict=False)
    source, main_home, live_home, live_skills = _expected_paths(repo_root, user_home)

    repository_metadata = repo_root / ".git"
    if (
        repository_metadata.is_symlink()
        or _is_junction(repository_metadata)
        or not repository_metadata.is_dir()
    ):
        raise PromotionError(f"repository root is not a main checkout: {repo_root}")
    worktree_metadata = source.parent / ".git"
    if (
        worktree_metadata.is_symlink()
        or _is_junction(worktree_metadata)
        or not (worktree_metadata.is_file() or worktree_metadata.is_dir())
    ):
        raise PromotionError(
            f"worktree source is not an actual linked worktree: {source.parent}"
        )
    _require_directory(source, "worktree Codex source")
    _require_directory(source / "skills", "worktree skills source")
    _require_directory(main_home, "main Codex home")
    _require_link(live_home, source, "live Codex home")
    _require_link(live_skills, source / "skills", "live shared skills")
    if backup_root == repo_root or backup_root.is_relative_to(repo_root):
        raise PromotionError(f"backup root must be outside the repository: {backup_root}")

    timestamp_value = _validated_timestamp(timestamp)
    backup = backup_root / f"codex-home-promotion-{timestamp_value}"
    stage = main_home.with_name(f".codex.promote-stage-{timestamp_value}")
    rollback = main_home.with_name(f".codex.promote-rollback-{timestamp_value}")
    link_specs = (
        (
            live_skills,
            source / "skills",
            main_home / "skills",
            live_skills.with_name(f"{live_skills.name}.promote-new-{timestamp_value}"),
            live_skills.with_name(f"{live_skills.name}.promote-old-{timestamp_value}"),
        ),
        (
            live_home,
            source,
            main_home,
            live_home.with_name(f"{live_home.name}.promote-new-{timestamp_value}"),
            live_home.with_name(f"{live_home.name}.promote-old-{timestamp_value}"),
        ),
    )
    transaction_paths = [backup, stage, rollback]
    for _, _, _, staged_link, snapshot_link in link_specs:
        transaction_paths.extend((staged_link, snapshot_link))
    for path in transaction_paths:
        if _lexists(path):
            raise PromotionError(f"promotion path already exists: {path}")

    backup.mkdir(parents=True)
    _copy_tree(source, backup / "worktree-codex")
    if not verify_copy(source, backup / "worktree-codex"):
        raise PromotionError("worktree backup verification failed")
    _copy_tree(main_home, backup / "main-codex-before-promotion")
    if not verify_copy(main_home, backup / "main-codex-before-promotion"):
        raise PromotionError("main Codex snapshot verification failed")

    _copy_tree(source, stage)
    if not verify_copy(source, stage):
        raise PromotionError("staged Codex home verification failed")

    main_moved = False
    stage_installed = False
    try:
        main_home.rename(rollback)
        main_moved = True
        stage.rename(main_home)
        stage_installed = True
        if not verify_copy(source, main_home):
            raise PromotionError("installed Codex home verification failed")
        for _, _, new_target, staged_link, _ in link_specs:
            _stage_link(staged_link, new_target)
        for live, expected_old, new_target, staged_link, snapshot_link in link_specs:
            _swap_staged_link(
                live,
                expected_old,
                staged_link,
                snapshot_link,
                new_target,
            )
    except BaseException as original_error:
        rollback_errors: list[str] = []
        for live, _, _, staged_link, snapshot_link in reversed(link_specs):
            try:
                _rollback_link_swap(live, staged_link, snapshot_link)
            except BaseException as error:
                rollback_errors.append(f"restore {live}: {error}")
        if stage_installed:
            try:
                main_home.rename(stage)
                stage_installed = False
            except BaseException as error:
                rollback_errors.append(f"retain failed install at {stage}: {error}")
        if main_moved and not stage_installed:
            try:
                rollback.rename(main_home)
                main_moved = False
            except BaseException as error:
                rollback_errors.append(f"restore main Codex home: {error}")
        detail = f"promotion failed: {original_error}"
        if rollback_errors:
            detail += "; rollback errors: " + "; ".join(rollback_errors)
        raise PromotionError(detail) from original_error

    cleanup_errors: list[str] = []
    for _, _, _, _, snapshot_link in link_specs:
        try:
            snapshot_link.unlink()
        except OSError as error:
            cleanup_errors.append(f"{snapshot_link}: {error}")
    try:
        _remove_path(rollback)
    except OSError as error:
        cleanup_errors.append(f"{rollback}: {error}")
    if cleanup_errors:
        print(
            "promote-worktree-home: cleanup retained artifacts: "
            + "; ".join(cleanup_errors),
            file=sys.stderr,
        )
    return backup


def main(arguments: list[str] | None = None) -> int:
    if arguments is None:
        arguments = sys.argv[1:]
    if arguments:
        print("promote-worktree-home: no arguments are supported", file=sys.stderr)
        return 2
    if default_process_running():
        print(
            "promote-worktree-home: close Codex before promotion",
            file=sys.stderr,
        )
        return 1
    tools_dir = Path(__file__).resolve().parent
    repo_root = tools_dir.parent
    user_home = Path.home()
    try:
        backup = promote(
            repo_root=repo_root,
            user_home=user_home,
            backup_root=user_home / ".codex-backups",
        )
    except (OSError, PromotionError) as error:
        print(f"promote-worktree-home: {error}", file=sys.stderr)
        return 1
    print("promote-worktree-home: promotion complete")
    print(f"promote-worktree-home: backup retained at {backup}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
