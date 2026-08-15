#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tomllib
from typing import Protocol


APP_SUPPLIED_MARKETPLACES = {
    "openai-bundled",
    "openai-primary-runtime",
    "openai-api-curated",
}
GIT_MARKETPLACE_KEYS = {"source_type", "source"}
GIT_MARKETPLACE_RUNTIME_METADATA = {"last_updated", "last_revision"}


class Runner(Protocol):
    def run(self, args: list[str]): ...


class SubprocessRunner:
    def run(self, args: list[str]):
        return subprocess.run(
            args,
            capture_output=True,
            text=True,
            check=False,
        )


def dotfiles_root() -> Path:
    return Path(__file__).resolve().parent.parent


def reconcile(*, config_path: Path, runner: Runner, codex_path: str | None) -> int:
    if codex_path is None:
        return 0

    try:
        config = tomllib.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError):
        return 1
    desired_marketplaces = config.get("marketplaces", {})
    desired_plugins = config.get("plugins", {})
    if not isinstance(desired_marketplaces, dict) or not isinstance(
        desired_plugins, dict
    ):
        return 1
    desired_git_marketplaces = {}
    for name, desired in desired_marketplaces.items():
        if name in APP_SUPPLIED_MARKETPLACES:
            continue
        if (
            not isinstance(desired, dict)
            or not GIT_MARKETPLACE_KEYS <= set(desired)
            or set(desired) - GIT_MARKETPLACE_KEYS - GIT_MARKETPLACE_RUNTIME_METADATA
        ):
            return 1
        if not isinstance(desired["source"], str):
            return 1
        if desired["source_type"] != "git":
            return 1
        desired_git_marketplaces[name] = {
            key: desired[key] for key in GIT_MARKETPLACE_KEYS
        }
    for plugin_id, desired in desired_plugins.items():
        if (
            not isinstance(desired, dict)
            or set(desired) != {"enabled"}
            or not isinstance(desired["enabled"], bool)
        ):
            return 1
        if "@" not in plugin_id:
            return 1
        marketplace_name = plugin_id.rsplit("@", 1)[-1]
        if (
            desired["enabled"]
            and marketplace_name not in APP_SUPPLIED_MARKETPLACES
            and marketplace_name not in desired_marketplaces
        ):
            return 1

    return _reconcile_with_restore(
        config_path=config_path,
        runner=runner,
        codex_path=codex_path,
        desired_marketplaces=desired_git_marketplaces,
        desired_plugins=desired_plugins,
    )


def _reconcile_with_restore(
    *,
    config_path: Path,
    runner: Runner,
    codex_path: str,
    desired_marketplaces: dict,
    desired_plugins: dict,
) -> int:
    original = config_path.read_bytes()
    descriptor, backup_name = tempfile.mkstemp(
        dir=config_path.parent,
        prefix=f".{config_path.name}.restore-",
    )
    backup_path = Path(backup_name)
    with os.fdopen(descriptor, "wb") as backup:
        backup.write(original)
        backup.flush()
        os.fsync(backup.fileno())
    try:
        status = _run_reconciliation(
            runner=runner,
            codex_path=codex_path,
            desired_marketplaces=desired_marketplaces,
            desired_plugins=desired_plugins,
        )
    except Exception as error:
        print(f"install-plugins: ERROR reconciliation failed: {error}", file=sys.stderr)
        status = 1
    try:
        os.replace(backup_path, config_path)
    except OSError as error:
        backup_absolute = backup_path.resolve()
        config_absolute = config_path.resolve()
        print(
            f"install-plugins: ERROR config restore failed: {error}\n"
            f"backup retained at: {backup_absolute}\n"
            f'restore with: "{sys.executable}" "{Path(__file__).resolve()}" '
            f'--restore "{backup_absolute}" "{config_absolute}"',
            file=sys.stderr,
        )
        return 1
    return status


def _run_reconciliation(
    *,
    runner: Runner,
    codex_path: str,
    desired_marketplaces: dict,
    desired_plugins: dict,
) -> int:
    marketplace_result = runner.run(
        [codex_path, "plugin", "marketplace", "list", "--json"]
    )
    if marketplace_result.returncode != 0:
        return 1
    marketplaces = {
        item["name"]: item for item in json.loads(marketplace_result.stdout)["marketplaces"]
    }
    required_marketplaces = {
        plugin_id.rsplit("@", 1)[-1]
        for plugin_id, desired in desired_plugins.items()
        if desired["enabled"]
        and plugin_id.rsplit("@", 1)[-1] not in APP_SUPPLIED_MARKETPLACES
    }

    for name, desired in desired_marketplaces.items():
        if name not in marketplaces:
            if name not in required_marketplaces:
                continue
            result = runner.run(
                [
                    codex_path,
                    "plugin",
                    "marketplace",
                    "add",
                    desired["source"],
                ]
            )
            if result.returncode != 0:
                return 1
            continue
        actual = marketplaces[name].get("marketplaceSource", {})
        if actual.get("sourceType") != desired["source_type"]:
            return 1
        if actual.get("source") != desired["source"]:
            return 1
    plugin_result = runner.run([codex_path, "plugin", "list", "--json"])
    if plugin_result.returncode != 0:
        return 1
    installed = {
        item["pluginId"] for item in json.loads(plugin_result.stdout)["installed"]
    }
    for plugin_id, desired in desired_plugins.items():
        marketplace_name = plugin_id.rsplit("@", 1)[-1]
        if marketplace_name in APP_SUPPLIED_MARKETPLACES:
            if desired["enabled"] and plugin_id not in installed:
                print(
                    f"install-plugins: WARN app-supplied plugin unavailable: {plugin_id}",
                    file=sys.stderr,
                )
            continue
        if desired["enabled"] and plugin_id not in installed:
            result = runner.run([codex_path, "plugin", "add", plugin_id])
            if result.returncode != 0:
                return 1
        elif not desired["enabled"] and plugin_id in installed:
            result = runner.run([codex_path, "plugin", "remove", plugin_id])
            if result.returncode != 0:
                return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    arguments = sys.argv[1:] if argv is None else argv
    if len(arguments) == 3 and arguments[0] == "--restore":
        try:
            os.replace(Path(arguments[1]), Path(arguments[2]))
        except OSError as error:
            print(f"install-plugins: ERROR restore failed: {error}", file=sys.stderr)
            return 1
        return 0
    if arguments:
        return 2
    return reconcile(
        config_path=dotfiles_root() / "codex" / "config.toml",
        runner=SubprocessRunner(),
        codex_path=shutil.which("codex"),
    )


if __name__ == "__main__":
    raise SystemExit(main())
