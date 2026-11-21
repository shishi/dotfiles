#!/usr/bin/env python3
"""Resolve a distributed skill file to an optional, locally maintained source."""

import argparse
from contextlib import contextmanager
import errno
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tomllib


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


def codex_plugin_enabled(config_file, identity):
    config = tomllib.loads(config_file.read_text(encoding='utf-8'))
    return config.get('plugins', {}).get(identity, {}).get('enabled')


def codex_plugin_enabled_elsewhere(home, identity):
    # Codex は利用者の設定に、起動時に選んだ profile と、作業中の repo の設定を重ねる。どの profile を選んだかは
    # ここから分からないため、profile か repo の設定が有効にしている plugin は、利用者が止めた plugin と扱わない。
    folders = (Path.cwd(), *Path.cwd().parents)
    layers = (*home.glob('*.config.toml'), *(folder / '.codex/config.toml' for folder in folders))
    return any(layer.is_file() and codex_plugin_enabled(layer, identity) is True for layer in layers)


def check_plugin_enabled(source):
    for cache in source.parents:
        if cache.name != 'cache' or cache.parent.name != 'plugins':
            continue
        parts = source.relative_to(cache).parts
        if len(parts) < 3:
            continue
        marketplace, plugin = parts[:2]
        identity = f'{plugin}@{marketplace}'
        home = cache.parent.parent
        codex_config = home / 'config.toml'
        claude_settings = home / 'settings.json'
        if codex_config.is_file():
            enabled = codex_plugin_enabled(codex_config, identity)
            if enabled is False and codex_plugin_enabled_elsewhere(home, identity):
                enabled = True
        elif claude_settings.is_file():
            config = json.loads(claude_settings.read_text(encoding='utf-8'))
            enabled = config.get('enabledPlugins', {}).get(identity)
        else:
            continue
        if enabled is False:
            raise ValueError(f'Plugin is explicitly disabled: {identity}')


def source_location(source, original):
    try:
        return original, source.relative_to(original)
    except ValueError:
        pass
    # Only sibling versions in the registered distribution are interchangeable.
    if len(original.parents) >= 4 and original.parents[2].name == 'cache' and original.parents[3].name == 'plugins':
        try:
            parts = source.relative_to(original.parent).parts
        except ValueError:
            return None
        if len(parts) >= 1:
            return original.parent / parts[0], Path(*parts[1:])
    return None


def safe_file(root, relative):
    file = (root / relative).resolve()
    if not file.is_relative_to(root.resolve()) or Path(relative).is_absolute():
        raise ValueError(f'File escapes package root: {relative}')
    return file


def save_object(state, content):
    digest = hashlib.sha256(content).hexdigest()
    objects = state / 'objects'
    objects.mkdir(mode=0o700, parents=True, exist_ok=True)
    file = objects / digest
    if not file.exists():
        with tempfile.NamedTemporaryFile(dir=objects, delete=False) as handle:
            handle.write(content)
            temporary = Path(handle.name)
        os.replace(temporary, file)
    return digest


def read_object(state, digest):
    if digest is None:
        return None
    if len(digest) != 64 or any(c not in '0123456789abcdef' for c in digest):
        raise ValueError('Invalid repair object hash')
    content = (state / 'objects' / digest).read_bytes()
    if hashlib.sha256(content).hexdigest() != digest:
        raise ValueError(f'Corrupt repair object: {digest}')
    return content


@contextmanager
def registry_lock(registry):
    with registry.with_suffix('.lock').open('a+b') as handle:
        if os.name == 'nt':
            import msvcrt
            handle.write(b'\0')
            handle.flush()
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)
        else:
            import fcntl
            fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            if os.name == 'nt':
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(handle, fcntl.LOCK_UN)


def prepare(source, registry, baseline=None, drop=()):
    check_plugin_enabled(source)
    with registry_lock(registry):
        return prepare_locked(source, registry, baseline, drop)


def prepare_locked(source, registry, baseline, drop):
    before = registry.read_bytes()
    data = json.loads(before)
    packages = []
    for item in data['packages']:
        original = Path(item['original_root']).expanduser().resolve()
        location = source_location(source, original)
        if original == source or ('repairs' in item and location and location[0] == source and location[1] == Path('.')):
            packages.append(item)
    if len(packages) != 1:
        raise ValueError('--prepare requires one registered original package root')
    package = packages[0]
    if baseline and 'repairs' in package:
        raise ValueError('--baseline is only for the first preparation; prepared repairs already retain their baseline')
    base = baseline or source
    upstream = fingerprints(base)
    if (baseline or 'repairs' not in package) and upstream != package['fingerprints']:
        raise ValueError('Baseline does not match registered fingerprints; recover the original bytes before preparing')
    if not base.is_dir():
        raise ValueError('Baseline package is missing')
    effective = Path(package['effective_root']).expanduser().resolve()
    if not effective.is_dir():
        raise ValueError(f'Maintained package is missing: {effective}')
    local = fingerprints(effective)
    if set(drop) - package.get('repairs', {}).keys():
        raise ValueError('--drop-repair must name an existing repair')
    if any(local.get(relative) != upstream.get(relative) for relative in drop):
        raise ValueError('Remove the selected repair from the maintained copy before dropping it')
    if 'repairs' in package and not baseline:
        stale = [relative for relative in upstream.keys() | local.keys()
                 if upstream.get(relative) != package['fingerprints'].get(relative)
                 and local.get(relative) == package['effective_fingerprints'].get(relative)
                 and upstream.get(relative) != local.get(relative)]
        if stale:
            raise ValueError(f'Maintained repair is based on an older distribution: {", ".join(sorted(stale))}; rebuild it from the current package')
        with tempfile.TemporaryDirectory(dir=registry.parent) as directory:
            for relative, repair in package['repairs'].items():
                if relative in drop:
                    continue
                file = safe_file(base, relative)
                current = file.read_bytes() if file.is_file() else None
                file = safe_file(effective, relative)
                candidate = file.read_bytes() if file.is_file() else None
                previous_base = read_object(registry.parent, repair['base'])
                previous_repair = read_object(registry.parent, repair['local'])
                retained = merge_repair(candidate, previous_base, previous_repair,
                                        relative, Path(directory), favor_current=candidate != current)
                if retained != candidate:
                    raise ValueError(f'Maintained copy lost a repair: {relative}; port every repair or explicitly use --drop-repair for an intentional removal')
                retained = merge_repair(candidate, previous_base, current,
                                        relative, Path(directory), favor_current=True)
                if retained != candidate:
                    raise ValueError(f'Maintained copy lost an upstream change: {relative}; rebuild it from the current package')
    repairs = {}
    for relative in sorted(upstream.keys() | local.keys()):
        old, new = upstream.get(relative), local.get(relative)
        if old != new:
            repairs[relative] = {
                'base': save_object(registry.parent, safe_file(base, relative).read_bytes()) if old else None,
                'local': save_object(registry.parent, safe_file(effective, relative).read_bytes()) if new else None,
            }
            if repairs[relative] != {'base': old, 'local': new}:
                raise ValueError('Source changed while preparing; retry with a stable snapshot')
    package['repairs'] = repairs
    package['effective_fingerprints'] = local
    package['fingerprints'] = upstream
    package['original_root'] = str(source)
    validate(effective, repairs, package.get('checks', []))
    if registry.read_bytes() != before:
        raise ValueError('Registry changed while preparing; retry with the current registry')
    with tempfile.NamedTemporaryFile(mode='w', dir=registry.parent, delete=False, encoding='utf-8') as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write('\n')
        temporary = Path(handle.name)
    os.chmod(temporary, registry.stat().st_mode & 0o777)
    os.replace(temporary, registry)
    return {'prepared': True, 'repairs': len(repairs), 'path': str(source)}


def merge_repair(current, base, local, relative, scratch, *, favor_current=False):
    if current == base or current == local:
        return local
    if base == local:
        return current
    if None in (current, base, local):
        if not favor_current:
            raise ValueError(f'Repair conflict (file added/deleted): {relative}')
    # Git cannot compare binary hunks; repreparation still permits explicit edits.
    if favor_current and any(b'\0' in (content or b'') for content in (current, base, local)):
        return current
    crlf = current is not None and b'\r\n' in current and b'\n' not in current.replace(b'\r\n', b'')
    for name, content in [('current', current), ('base', base), ('local', local)]:
        (scratch / name).write_bytes((content or b'').replace(b'\r\n', b'\n'))
    # Repreparation may edit conflicting repairs, but must retain disjoint changes.
    options = ['--ours'] if favor_current else []
    result = subprocess.run(['git', 'merge-file', '-p', *options, str(scratch / 'current'), str(scratch / 'base'), str(scratch / 'local')], capture_output=True)
    if result.returncode != 0:
        raise ValueError(f'Repair conflict: {relative}; update the maintained repair against the current distribution and prepare it again')
    # Normalization is for comparison, not for rewriting the maintained bytes.
    if favor_current and result.stdout == (current or b'').replace(b'\r\n', b'\n'):
        return current
    if current is None and not result.stdout:
        return None
    return result.stdout.replace(b'\n', b'\r\n') if crlf else result.stdout


def validate(root, files, checks):
    for relative in files:
        file = safe_file(root, relative)
        if not file.is_file():
            continue
        if file.suffix == '.py':
            try:
                compile(file.read_bytes(), relative, 'exec')
            except SyntaxError as error:
                raise ValueError(f'Syntax validation failed: {relative}: {error}') from error
        elif file.suffix == '.json':
            try:
                json.loads(file.read_bytes())
            except ValueError as error:
                raise ValueError(f'Syntax validation failed: {relative}: {error}') from error
        elif file.suffix in {'.js', '.mjs', '.cjs', '.sh'}:
            # Windows では名前だけの 'bash' が PATH より先に System32 の WSL bash を選び、
            # Windows のパスを読めずに正しいスクリプトも失敗させるので、PATH の順で探した bash を使う
            # (PATH でも System32 が Git Bash より前にあると WSL の bash になる)
            command = [shutil.which('bash') or 'bash', '-n'] if file.suffix == '.sh' else ['node', '--check']
            result = subprocess.run([*command, str(file)], capture_output=True)
            if result.returncode != 0:
                raise ValueError(f'Syntax validation failed: {relative}: {result.stderr.decode(errors="replace")[:2000]}')
    for command in checks:
        if not isinstance(command, list) or not command or not all(isinstance(arg, str) for arg in command):
            raise ValueError('Validation checks must be nonempty argv arrays')
        args = [arg.replace('{package_root}', str(root)) for arg in command]
        result = subprocess.run(args, cwd=root, capture_output=True, timeout=300)
        if result.returncode != 0:
            raise ValueError(f'Repair validation failed (exit {result.returncode}): {(result.stdout + result.stderr).decode(errors="replace")[:2000]}')


def refresh(original, package, registry):
    state = registry.parent
    effective = Path(package['effective_root']).expanduser().resolve()
    if not effective.is_dir():
        raise ValueError(f'Maintained package is missing: {effective}')
    if fingerprints(effective) != package['effective_fingerprints']:
        raise ValueError('Maintained repair changed; prepare it before use')
    upstream = fingerprints(original)
    if not original.is_dir():
        raise ValueError(f'Current distribution is missing: {original}')
    checks = package.get('checks', [])
    key = hashlib.sha256(json.dumps([str(original), upstream, package['repairs'], checks,
        hashlib.sha256(Path(__file__).read_bytes()).hexdigest()], sort_keys=True).encode()).hexdigest()
    cache = state / 'rebased' / key
    receipt = cache / 'validation.json'
    if receipt.is_file():
        result = json.loads(receipt.read_text())
        if fingerprints(cache / 'package') == result['fingerprints']:
            return cache / 'package', result['changed']
        raise ValueError('Validated repair cache changed; remove that generated cache and resolve again')
    cache.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=cache.parent) as directory:
        work = Path(directory)
        candidate = work / 'package'
        shutil.copytree(original, candidate, ignore=lambda _, names: [n for n in names if n in VOLATILE_PARTS or n.endswith(('.pyc', '.pyo'))])
        scratch = work / 'merge'
        scratch.mkdir()
        for relative, repair in package['repairs'].items():
            current_file = safe_file(original, relative)
            current = current_file.read_bytes() if current_file.is_file() else None
            content = merge_repair(current, read_object(state, repair['base']), read_object(state, repair['local']), relative, scratch)
            destination = safe_file(candidate, relative)
            if content is None:
                if destination.exists():
                    destination.unlink()
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(content)
                if current is None:
                    shutil.copymode(safe_file(effective, relative), destination)
        merged = fingerprints(candidate)
        changed = merged != upstream
        files = {name for name in merged if merged[name] != package['fingerprints'].get(name)}
        validate(candidate, files, checks)
        if fingerprints(candidate) != merged:
            raise ValueError('Validation changed package files')
        if fingerprints(original) != upstream:
            raise ValueError('Distribution changed during repair; resolve again')
        (work / 'validation.json').write_text(json.dumps({'fingerprints': merged, 'changed': changed}) + '\n')
        scratch_files = work / 'merge'
        shutil.rmtree(scratch_files)
        try:
            os.rename(work, cache)
        except OSError as error:
            if error.errno not in {errno.EEXIST, errno.ENOTEMPTY}:
                raise
            if not receipt.is_file() or json.loads(receipt.read_text())['fingerprints'] != merged:
                raise ValueError('Concurrent repair produced a different result')
    return cache / 'package', changed


def resolve(source, registry):
    check_plugin_enabled(source)
    result = {"path": str(source), "overridden": False, "reason": "unregistered"}
    if not registry.is_file():
        return {**result, "reason": "no-registry"}
    data = json.loads(registry.read_text(encoding='utf-8'))
    matches = []
    for package in data["packages"]:
        original = Path(package["original_root"]).expanduser().resolve()
        location = source_location(source, original) if 'repairs' in package else None
        if location is None:
            try:
                location = original, source.relative_to(original)
            except ValueError:
                continue
        current, relative = location
        matches.append((len(original.parts), current, relative, package))
    if not matches:
        return result
    _, original, relative, package = max(matches, key=lambda match: match[0])
    if 'repairs' in package:
        root, changed = refresh(original, package, registry)
        if not changed:
            return {**result, 'reason': 'upstream-fixed'}
        path = safe_file(root, relative)
        if not path.exists():
            raise ValueError(f'Maintained source is missing: {path}')
        return {'path': str(path), 'package_root': str(root), 'overridden': True, 'reason': 'rebased-source'}
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
    parser.add_argument('--prepare', action='store_true', help='Capture the registered repair as a portable delta')
    parser.add_argument('--baseline', type=Path, help='Verified original snapshot when the registered distribution was updated or removed')
    parser.add_argument('--drop-repair', action='append', default=[], metavar='FILE', help='Explicitly remove a repair while preparing the current maintained copy')
    args = parser.parse_args()
    state = Path(os.environ.get("AGENT_SKILL_OVERRIDES_DIR", str(Path.home() / ".agent-shared/skill-overrides")))
    try:
        if (args.baseline or args.drop_repair) and not args.prepare:
            raise ValueError('--baseline and --drop-repair require --prepare')
        source = args.path.expanduser().resolve()
        result = prepare(source, state / 'registry.json', args.baseline.expanduser().resolve() if args.baseline else None, args.drop_repair) if args.prepare else resolve(source, state / 'registry.json')
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f"Skill source resolution failed: {error}\n")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
