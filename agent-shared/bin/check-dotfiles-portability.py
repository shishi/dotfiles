#!/usr/bin/env python3
"""Reject nonportable symlinks and new literal absolute hook arguments in the Git index."""

from collections import Counter
import json
import ntpath
import os
import posixpath
import shlex
import subprocess
import sys


def git(*args, check=True):
    return subprocess.run(['git', *args], capture_output=True, check=check).stdout


def absolute(path):
    return posixpath.isabs(path) or ntpath.isabs(path) or bool(ntpath.splitdrive(path)[0])


def hook_commands(data):
    result = Counter()
    for entries in data.get('hooks', {}).values():
        for entry in entries:
            for hook in entry.get('hooks', []):
                for field in ('command', 'commandWindows'):
                    if isinstance(hook.get(field), str):
                        result[field, hook[field]] += 1
    return result


def absolute_arguments(command, windows):
    lexer = shlex.shlex(command, posix=not windows, punctuation_chars=';&|<>()')
    lexer.whitespace_split = True
    for word in lexer:
        word = word.strip('\'"') if windows else word
        if not absolute(word) and '=' in word:
            word = word.split('=', 1)[1].strip('\'"')
        if absolute(word) and word != posixpath.devnull:
            yield word


def main():
    root = git('rev-parse', '--show-toplevel').decode().strip()
    os.chdir(root)
    index = {}
    for entry in git('ls-files', '--stage', '-z').split(b'\0'):
        if entry:
            metadata, path = entry.split(b'\t', 1)
            mode, oid, stage = metadata.decode().split()
            if stage != '0':
                raise ValueError('Resolve unmerged index entries before committing')
            index[os.fsdecode(path)] = mode, oid
    changed = [os.fsdecode(path) for path in git(
        'diff', '--cached', '--name-only', '--diff-filter=ACMRT', '-z').split(b'\0') if path]
    errors = []

    def check_link(path):
        visited = set()
        while path in index and index[path][0] == '120000':
            if path in visited:
                return 'symlink cycle'
            visited.add(path)
            target = os.fsdecode(git('cat-file', 'blob', index[path][1]))
            if absolute(target):
                return 'absolute symlink target; use a runtime-resolved pointer or a repository-relative link'
            path = posixpath.normpath(posixpath.join(posixpath.dirname(path), target))
            if path == '..' or path.startswith('../'):
                return 'symlink target escapes the repository'
        if path not in index and not any(name.startswith(path + '/') for name in index):
            return 'symlink target is absent from the index'
        return None

    for path in changed:
        if index[path][0] == '120000':
            error = check_link(path)
            if error:
                errors.append(f'{path}: {error}')
        elif path in ('claude/settings.json', 'codex/hooks.json'):
            try:
                current = json.loads(git('cat-file', 'blob', index[path][1]))
                previous = git('show', f'HEAD:{path}', check=False)
                old_commands = hook_commands(json.loads(previous)) if previous else Counter()
                for field, command in hook_commands(current) - old_commands:
                    if any(absolute_arguments(command, field == 'commandWindows')):
                        errors.append(f'{path}: {field} contains a literal absolute path; resolve it from the environment')
            except (ValueError, TypeError, AttributeError) as error:
                errors.append(f'{path}: invalid hook configuration: {error}')
    if errors:
        print('dotfiles portability: commit rejected\n' + '\n'.join(errors), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'dotfiles portability: cannot validate the index: {error}', file=sys.stderr)
        sys.exit(1)
