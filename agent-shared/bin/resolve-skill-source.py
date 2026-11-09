#!/usr/bin/env python3
"""Resolve a distributed skill file to an optional, locally maintained source."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys


VOLATILE_PARTS = {".git", "__pycache__", ".in_use", ".orphaned_at"}


def fingerprints(root):
    result = {}
    for file in sorted(root.rglob("*")):
        relative = file.relative_to(root)
        if any(part in VOLATILE_PARTS for part in relative.parts) or file.suffix in {".pyc", ".pyo"}:
            continue
        if file.is_file():
            result[relative.as_posix()] = hashlib.sha256(file.read_bytes()).hexdigest()
    return result


def resolve(source, registry):
    result = {"path": str(source), "overridden": False, "reason": "unregistered"}
    if not registry.is_file():
        return {**result, "reason": "no-registry"}
    data = json.loads(registry.read_text())
    matches = []
    for package in data["packages"]:
        original = Path(package["original_root"]).expanduser().resolve()
        try:
            relative = source.relative_to(original)
        except ValueError:
            continue
        matches.append((len(original.parts), original, relative, package))
    if not matches:
        return result
    _, original, relative, package = max(matches, key=lambda match: match[0])
    if fingerprints(original) != package["fingerprints"]:
        return {**result, "reason": "upstream-changed"}
    effective_root = Path(package["effective_root"]).expanduser().resolve()
    effective = (effective_root / relative).resolve()
    if not effective.exists():
        raise ValueError(f"Maintained source is missing: {effective}")
    return {"path": str(effective), "package_root": str(effective_root),
            "overridden": True, "reason": "maintained-source"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path, help="Actual source path from the current skill catalog")
    args = parser.parse_args()
    state = Path(os.environ.get("AGENT_SKILL_OVERRIDES_DIR", str(Path.home() / ".agent-shared/skill-overrides")))
    try:
        result = resolve(args.path.expanduser().resolve(), state / "registry.json")
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Skill source resolution failed: {error}\n")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
