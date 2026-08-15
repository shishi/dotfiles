#!/usr/bin/env python3
from datetime import datetime
import hashlib
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
from typing import Callable


MANAGED_NAMES = {
    "AGENTS.md",
    "config.toml",
    "agents",
    "rules",
    "hooks",
    "hooks.json",
    "skills",
}
REPOSITORY_EXCLUDED_NAMES = {".gitignore"}


def default_process_running() -> bool:
    if os.name == "nt":
        result = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq Codex.exe", "/FO", "CSV", "/NH"],
            capture_output=True,
            text=True,
            check=False,
        )
        return result.returncode == 0 and '"codex.exe"' in result.stdout.casefold()
    for process_name in ("codex", "Codex"):
        result = subprocess.run(
            ["pgrep", "-x", process_name],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            return True
    return False


def _is_junction(path: Path) -> bool:
    if os.name != "nt":
        return False
    try:
        return (
            os.lstat(path).st_reparse_tag
            == stat.IO_REPARSE_TAG_MOUNT_POINT
        )
    except FileNotFoundError:
        return False


def _kind(path: Path) -> str:
    if path.is_symlink():
        return "symlink"
    if _is_junction(path):
        return "junction"
    if path.is_dir():
        return "directory"
    if path.is_file():
        return "file"
    return "other"


def _lexists(path: Path) -> bool:
    return path.exists() or path.is_symlink() or _is_junction(path)


def _symlink_is_directory(path: Path) -> bool:
    if os.name != "nt":
        return False
    attributes = os.lstat(path).st_file_attributes
    return bool(attributes & stat.FILE_ATTRIBUTE_DIRECTORY)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


_CMD_META_CHARACTERS = frozenset("&|<>^()%!\"'\r\n")


def _checked_cmd_path(path: str | os.PathLike[str]) -> str:
    value = os.fspath(path)
    if any(character in value for character in _CMD_META_CHARACTERS):
        raise OSError(f"unsafe junction path for cmd.exe: {value!r}")
    return value


def _create_junction(
    destination: Path,
    target: Path | str,
    run_command: Callable[..., subprocess.CompletedProcess[str]] | None = None,
) -> None:
    command_runner = run_command or subprocess.run
    result = command_runner(
        [
            "cmd.exe",
            "/d",
            "/c",
            "mklink",
            "/J",
            _checked_cmd_path(destination),
            _checked_cmd_path(target),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise OSError(result.stderr or result.stdout or "junction copy failed")


def verify_copy(source: Path, copy: Path) -> bool:
    if _kind(source) != _kind(copy):
        return False
    kind = _kind(source)
    if kind == "symlink":
        return os.readlink(source) == os.readlink(copy) and (
            os.name != "nt"
            or _symlink_is_directory(source) == _symlink_is_directory(copy)
        )
    if kind == "junction":
        return os.readlink(source) == os.readlink(copy)
    if kind == "file":
        return source.stat().st_size == copy.stat().st_size and _sha256(source) == _sha256(copy)
    if kind == "directory":
        source_entries = {entry.name: entry for entry in source.iterdir()}
        copy_entries = {entry.name: entry for entry in copy.iterdir()}
        return source_entries.keys() == copy_entries.keys() and all(
            verify_copy(entry, copy_entries[name])
            for name, entry in source_entries.items()
        )
    return False


def _copy_entry(source: Path, destination: Path) -> None:
    if source.is_symlink():
        os.symlink(
            os.readlink(source),
            destination,
            target_is_directory=_symlink_is_directory(source),
        )
    elif _is_junction(source):
        _create_junction(destination, os.readlink(source))
    elif source.is_dir():
        _copy_tree(source, destination)
    else:
        shutil.copy2(source, destination)


def _copy_tree(source: Path, destination: Path) -> None:
    destination.mkdir()
    for entry in source.iterdir():
        _copy_entry(entry, destination / entry.name)
    shutil.copystat(source, destination, follow_symlinks=False)


def _create_directory_link(source: Path, destination: Path) -> None:
    os.symlink(source, destination, target_is_directory=True)


def _retry_readonly_removal(
    function: Callable[[str], None],
    path: str,
    error_info: tuple[type[BaseException], BaseException, object],
) -> None:
    error = error_info[1]
    if os.name != "nt" or not isinstance(error, PermissionError):
        raise error
    os.chmod(path, stat.S_IWRITE)
    function(path)


def _remove_path(path: Path) -> None:
    if path.is_symlink() or _is_junction(path):
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path, onerror=_retry_readonly_removal)
    elif path.exists():
        try:
            path.unlink()
        except PermissionError as error:
            _retry_readonly_removal(
                os.unlink,
                str(path),
                (type(error), error, error.__traceback__),
            )


def _rollback(
    *,
    codex_home: Path,
    agents_skills: Path,
    backup: Path,
    journal: list[Path],
    restore_live: bool,
    remove_path: Callable[[Path], None] = _remove_path,
    codex_snapshot: Path | None = None,
    agents_skills_snapshot: Path | None = None,
    rename_path: Callable[[Path, Path], None] | None = None,
) -> bool:
    failed = False

    def attempt(action: str, path: Path, operation: Callable[[], None]) -> bool:
        nonlocal failed
        try:
            operation()
            return True
        except OSError as error:
            failed = True
            print(
                f"migrate-home: rollback {action} failed for {path}: {error}",
                file=sys.stderr,
            )
            return False

    if restore_live:
        rename_entry = rename_path or (
            lambda source, destination: source.rename(destination)
        )
        restore_specs = (
            (codex_home, codex_snapshot, backup / "codex"),
            (agents_skills, agents_skills_snapshot, backup / "agents-skills"),
        )
        for live, snapshot, _ in restore_specs:
            if snapshot is not None:
                attempt("remove", live, lambda live=live: remove_path(live))
        for live, snapshot, verified_copy in restore_specs:
            if snapshot is None:
                continue
            restored = attempt(
                "rename",
                snapshot,
                lambda snapshot=snapshot, live=live: rename_entry(snapshot, live),
            )
            if not restored and not _lexists(live):
                attempt(
                    "copy",
                    live,
                    lambda verified_copy=verified_copy, live=live: _copy_tree(
                        verified_copy, live
                    ),
                )
    for path in reversed(journal):
        attempt("journal cleanup", path, lambda path=path: remove_path(path))
    return not failed


def _persist_journal(path: Path, entries: list[Path]) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as journal:
        journal.writelines(f"{entry.resolve()}\n" for entry in entries)
        journal.flush()
        os.fsync(journal.fileno())


def restore(
    *,
    codex_home: Path,
    agents_skills: Path,
    backup: Path,
    process_running: Callable[[], bool],
    timestamp: Callable[[], str] | None = None,
    rename_path: Callable[[Path, Path], None] | None = None,
    copy_tree: Callable[[Path, Path], None] | None = None,
) -> int:
    if process_running():
        return 1
    backup_sources = (backup / "codex", backup / "agents-skills")
    if (
        backup.is_symlink()
        or _is_junction(backup)
        or not backup.is_dir()
        or any(
            source.is_symlink() or _is_junction(source) or not source.is_dir()
            for source in backup_sources
        )
    ):
        print(
            f"migrate-home: restore backup is incomplete or unsafe: {backup}",
            file=sys.stderr,
        )
        return 1

    timestamp_value = (timestamp or (lambda: datetime.now().strftime("%Y%m%d-%H%M%S")))()
    codex_stage = codex_home.with_name(f"{codex_home.name}.restore-stage-{timestamp_value}")
    skills_stage = agents_skills.with_name(
        f"{agents_skills.name}.restore-stage-{timestamp_value}"
    )
    previous_codex = codex_home.with_name(
        f"{codex_home.name}.pre-restore-{timestamp_value}"
    )
    previous_skills = agents_skills.with_name(
        f"{agents_skills.name}.pre-restore-{timestamp_value}"
    )
    reserved_paths = (codex_stage, skills_stage, previous_codex, previous_skills)
    if any(_lexists(path) for path in reserved_paths):
        print("migrate-home: restore staging path already exists", file=sys.stderr)
        return 1

    def cleanup_stages() -> None:
        for stage in (codex_stage, skills_stage):
            if not _lexists(stage):
                continue
            try:
                _remove_path(stage)
            except OSError as error:
                print(
                    f"migrate-home: restore stage cleanup failed for {stage}: {error}",
                    file=sys.stderr,
                )

    codex_home.parent.mkdir(parents=True, exist_ok=True)
    agents_skills.parent.mkdir(parents=True, exist_ok=True)
    copy_backup = copy_tree or _copy_tree
    try:
        copy_backup(backup / "codex", codex_stage)
        copy_backup(backup / "agents-skills", skills_stage)
    except OSError as error:
        print(f"migrate-home: restore staging failed: {error}", file=sys.stderr)
        cleanup_stages()
        return 1
    try:
        stages_verified = verify_copy(
            backup / "codex", codex_stage
        ) and verify_copy(backup / "agents-skills", skills_stage)
    except OSError as error:
        print(
            f"migrate-home: restore staging verification failed: {error}",
            file=sys.stderr,
        )
        cleanup_stages()
        return 1
    if not stages_verified:
        print("migrate-home: restore staging verification failed", file=sys.stderr)
        cleanup_stages()
        return 1
    if process_running():
        cleanup_stages()
        return 1

    had_codex = _lexists(codex_home)
    had_skills = _lexists(agents_skills)
    rename_entry = rename_path or (lambda source, destination: source.rename(destination))
    saved_codex = False
    saved_skills = False
    swapped_codex = False
    swapped_skills = False
    try:
        if had_codex:
            rename_entry(codex_home, previous_codex)
            saved_codex = True
        if had_skills:
            rename_entry(agents_skills, previous_skills)
            saved_skills = True
        rename_entry(codex_stage, codex_home)
        swapped_codex = True
        rename_entry(skills_stage, agents_skills)
        swapped_skills = True
    except OSError as error:
        print(f"migrate-home: restore swap failed: {error}", file=sys.stderr)

        def rollback(action: str, path: Path, operation: Callable[[], None]) -> None:
            try:
                operation()
            except OSError as rollback_error:
                print(
                    f"migrate-home: restore rollback {action} failed for "
                    f"{path}: {rollback_error}",
                    file=sys.stderr,
                )

        if swapped_codex:
            rollback("remove", codex_home, lambda: _remove_path(codex_home))
        if swapped_skills:
            rollback("remove", agents_skills, lambda: _remove_path(agents_skills))
        if saved_codex:
            rollback(
                "rename",
                previous_codex,
                lambda: rename_entry(previous_codex, codex_home),
            )
        if saved_skills:
            rollback(
                "rename",
                previous_skills,
                lambda: rename_entry(previous_skills, agents_skills),
            )
        for stage in (codex_stage, skills_stage):
            if _lexists(stage):
                rollback("cleanup", stage, lambda stage=stage: _remove_path(stage))
        return 1

    if had_codex:
        print(f"migrate-home: previous Codex home retained at {previous_codex}")
    if had_skills:
        print(f"migrate-home: previous personal skills retained at {previous_skills}")
    return 0


def bootstrap(
    *,
    codex_home: Path,
    agents_skills: Path,
    repo_home: Path,
    backup_root: Path,
    process_running: Callable[[], bool],
    timestamp: Callable[[], str] | None = None,
    link_directory: Callable[[Path, Path], None] | None = None,
    plugin_reconciler: Callable[[], int] | None = None,
    copy_entry: Callable[[Path, Path], None] | None = None,
    remove_path: Callable[[Path], None] | None = None,
    on_filesystem_commit: Callable[[], None] | None = None,
    rename_path: Callable[[Path, Path], None] | None = None,
) -> int:
    if process_running():
        return 1
    if _kind(codex_home) != "directory" or _kind(agents_skills) != "directory":
        return 1
    runtime_entries = [
        path.relative_to(codex_home)
        for path in codex_home.iterdir()
        if path.name not in MANAGED_NAMES
        and path.name not in REPOSITORY_EXCLUDED_NAMES
    ]
    nested_system = codex_home / "skills" / ".system"
    managed_skills = nested_system.parent
    if (
        not managed_skills.is_symlink()
        and not _is_junction(managed_skills)
        and managed_skills.is_dir()
        and _lexists(nested_system)
    ):
        runtime_entries.append(nested_system.relative_to(codex_home))
    if any(_lexists(repo_home / path) for path in runtime_entries):
        return 1
    timestamp_value = (timestamp or (lambda: datetime.now().strftime("%Y%m%d-%H%M%S")))()
    backup = backup_root / f"codex-home-{timestamp_value}"
    journal: list[Path] = []
    live_mutation_started = False
    create_link = link_directory or _create_directory_link
    copy_runtime = copy_entry or _copy_entry
    remove_runtime = remove_path or _remove_path
    rename_live = rename_path or (
        lambda source, destination: source.rename(destination)
    )
    codex_snapshot: Path | None = None
    agents_skills_snapshot: Path | None = None
    stage_root = repo_home.with_name(
        f".{repo_home.name}.bootstrap-stage-{timestamp_value}"
    )
    suffix = 0
    while _lexists(stage_root):
        suffix += 1
        stage_root = repo_home.with_name(
            f".{repo_home.name}.bootstrap-stage-{timestamp_value}-{suffix}"
        )
    stage = stage_root / "home"
    try:
        if backup.resolve().is_relative_to(repo_home.parent.resolve()):
            return 1
        backup.mkdir(parents=True)
        _copy_tree(codex_home, backup / "codex")
        _copy_tree(agents_skills, backup / "agents-skills")
        if not verify_copy(codex_home, backup / "codex"):
            return 1
        if not verify_copy(agents_skills, backup / "agents-skills"):
            return 1

        stage_root.mkdir()
        (stage_root / ".gitignore").write_text("*\n", encoding="utf-8")
        _copy_tree(backup / "codex", stage)
        if not verify_copy(backup / "codex", stage):
            raise OSError("full Codex home staging verification failed")

        for name in REPOSITORY_EXCLUDED_NAMES:
            excluded = stage / name
            if _lexists(excluded):
                _remove_path(excluded)

        for name in MANAGED_NAMES:
            source = repo_home / name
            destination = stage / name
            if _lexists(destination):
                _remove_path(destination)
            if not _lexists(source):
                continue
            _copy_entry(source, destination)
            if not verify_copy(source, destination):
                raise OSError(f"managed overlay verification failed: {name}")

        staged_system = stage / "skills" / ".system"
        backup_system = backup / "codex" / "skills" / ".system"
        if nested_system.relative_to(codex_home) in runtime_entries:
            _copy_entry(backup_system, staged_system)
            if not verify_copy(backup_system, staged_system):
                raise OSError("skills/.system staging verification failed")

        for source in runtime_entries:
            destination = repo_home / source
            journal.append(destination)
            _persist_journal(backup / "transaction-journal.txt", journal)
            copy_runtime(stage / source, destination)
            if not verify_copy(stage / source, destination):
                raise OSError(f"runtime copy verification failed: {source}")

        _remove_path(stage_root)

        if process_running():
            _rollback(
                codex_home=codex_home,
                agents_skills=agents_skills,
                backup=backup,
                journal=journal,
                restore_live=False,
                remove_path=remove_runtime,
            )
            return 1
        live_mutation_started = True
        pending_codex_snapshot = backup / "live-codex-at-commit"
        rename_live(codex_home, pending_codex_snapshot)
        codex_snapshot = pending_codex_snapshot
        pending_agents_skills_snapshot = backup / "live-agents-skills-at-commit"
        rename_live(agents_skills, pending_agents_skills_snapshot)
        agents_skills_snapshot = pending_agents_skills_snapshot
        create_link(repo_home, codex_home)
        create_link(repo_home / "skills", agents_skills)
        if codex_home.resolve() != repo_home.resolve():
            raise OSError("Codex home link verification failed")
        if agents_skills.resolve() != (repo_home / "skills").resolve():
            raise OSError("personal skills link verification failed")
    except OSError:
        _rollback(
            codex_home=codex_home,
            agents_skills=agents_skills,
            backup=backup,
            journal=journal,
            restore_live=live_mutation_started,
            remove_path=remove_runtime,
            codex_snapshot=codex_snapshot,
            agents_skills_snapshot=agents_skills_snapshot,
            rename_path=rename_live,
        )
        if _lexists(stage_root):
            try:
                _remove_path(stage_root)
            except OSError as cleanup_error:
                print(
                    f"migrate-home: stage cleanup failed for {stage_root}: "
                    f"{cleanup_error}",
                    file=sys.stderr,
                )
        return 1
    if on_filesystem_commit is not None:
        on_filesystem_commit()
    if plugin_reconciler is not None:
        try:
            return plugin_reconciler()
        except OSError as error:
            print(
                f"migrate-home: plugin reconciliation launch failed: {error}",
                file=sys.stderr,
            )
            return 1
    return 0


def migrate(
    *,
    codex_home: Path,
    agents_skills: Path,
    repo_codex: Path,
    backup_root: Path,
    process_running: Callable[[], bool],
    timestamp: Callable[[], str] | None = None,
    link_directory: Callable[[Path, Path], None] | None = None,
    plugin_reconciler: Callable[[], int] | None = None,
    copy_entry: Callable[[Path, Path], None] | None = None,
    remove_path: Callable[[Path], None] | None = None,
    on_filesystem_commit: Callable[[], None] | None = None,
    rename_path: Callable[[Path, Path], None] | None = None,
) -> int:
    return bootstrap(
        codex_home=codex_home,
        agents_skills=agents_skills,
        repo_home=repo_codex,
        backup_root=backup_root,
        process_running=process_running,
        timestamp=timestamp,
        link_directory=link_directory,
        plugin_reconciler=plugin_reconciler,
        copy_entry=copy_entry,
        remove_path=remove_path,
        on_filesystem_commit=on_filesystem_commit,
        rename_path=rename_path,
    )


def main(argv: list[str] | None = None) -> int:
    arguments = sys.argv[1:] if argv is None else argv
    restore_backup: Path | None = None
    if arguments:
        if len(arguments) == 2 and arguments[0] == "--restore":
            restore_backup = Path(arguments[1])
        else:
            return 2
    if default_process_running():
        print("migrate-home: ERROR close Codex before migration", file=sys.stderr)
        return 1
    user_home = Path.home()
    codex_home = user_home / ".codex"
    agents_skills = user_home / ".agents" / "skills"
    if restore_backup is not None:
        return restore(
            codex_home=codex_home,
            agents_skills=agents_skills,
            backup=restore_backup,
            process_running=default_process_running,
        )
    tools_dir = Path(__file__).resolve().parent
    repo_codex = tools_dir.parent / "codex"
    backup_root = user_home / ".codex-backups"
    timestamp_value = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = backup_root / f"codex-home-{timestamp_value}"
    filesystem_committed = False

    def mark_filesystem_committed() -> None:
        nonlocal filesystem_committed
        filesystem_committed = True

    def run_plugins() -> int:
        try:
            return subprocess.run(
                ["bash", str(tools_dir / "install-plugins.sh")],
                check=False,
            ).returncode
        except OSError as error:
            print(
                f"migrate-home: plugin launcher failed: {error}",
                file=sys.stderr,
            )
            return 1

    status = migrate(
        codex_home=codex_home,
        agents_skills=agents_skills,
        repo_codex=repo_codex,
        backup_root=backup_root,
        process_running=default_process_running,
        timestamp=lambda: timestamp_value,
        plugin_reconciler=run_plugins,
        on_filesystem_commit=mark_filesystem_committed,
    )
    if backup.exists():
        print(f"migrate-home: backup retained at {backup}")
    if status == 0:
        print("migrate-home: filesystem and plugins converged")
    elif filesystem_committed:
        print(
            f"migrate-home: plugin reconciliation failed; retry: "
            f'bash "{tools_dir / "install-plugins.sh"}"',
            file=sys.stderr,
        )
    else:
        if backup.exists():
            print(
                "migrate-home: migration failed; restore with: "
                f'bash "{tools_dir / "bootstrap-home.sh"}" --restore "{backup}"',
                file=sys.stderr,
            )
        else:
            print(
                "migrate-home: migration failed before a backup was retained",
                file=sys.stderr,
            )
    return status


if __name__ == "__main__":
    raise SystemExit(main())
