#!/usr/bin/env python3
"""出力ゲートの mod がターンのファイルの置き換えと掃除に使う Python (register.ts の FILE_OPS) を、
一時ディレクトリで実際に動かして確かめる。mod の試験 (claude plugin test) はプロセスを起動できないため、ここで見る。"""
import ast
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
MODULE = REPO / 'claude/mods/output-gate/hooks/register.ts'


def file_ops():
    """register.ts の `const FILE_OPS = ['...', ...].join('\\n')` から、Python のコードを取り出す。"""
    source = MODULE.read_text(encoding='utf-8')
    match = re.search(r"const FILE_OPS = \[(.*?)\]\.join\('\\n'\)", source, re.S)
    if match is None:
        raise AssertionError(f'{MODULE} に FILE_OPS の行の並びが無い')
    lines = re.findall(r"'(?:[^'\\]|\\.)*'", match.group(1))
    return '\n'.join(ast.literal_eval(line) for line in lines)


class FileOpsTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix='output-gate-fileops-'))

    def write(self, *parts, text='x'):
        path = self.dir.joinpath(*parts)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')
        return path

    def run_ops(self, ops):
        # mod と同じく、パスは区切りを / にして渡す。
        result = subprocess.run([sys.executable, '-I', '-c', file_ops(), json.dumps(ops)],
                                capture_output=True, text=True, encoding='utf-8')
        self.assertEqual(result.returncode, 0, result.stderr)

    def path(self, *parts):
        return self.dir.joinpath(*parts).as_posix()

    def test_replaces_the_temporary_file(self):
        self.write('cur', 'a.json.tmp', text='new')
        self.write('cur', 'a.json', text='old')
        self.run_ops({'replace': [[self.path('cur', 'a.json.tmp'), self.path('cur', 'a.json')]], 'remove': [], 'rmdir': []})
        self.assertEqual(sorted(p.name for p in (self.dir / 'cur').iterdir()), ['a.json'])
        self.assertEqual((self.dir / 'cur' / 'a.json').read_text(encoding='utf-8'), 'new')

    def test_removes_files_and_ignores_missing_ones(self):
        self.write('cur', 'old.json')
        self.write('cur', 'keep.json')
        self.run_ops({'replace': [], 'remove': [self.path('cur', 'old.json'), self.path('missing.json')], 'rmdir': []})
        self.assertEqual(sorted(p.name for p in (self.dir / 'cur').iterdir()), ['keep.json'])

    def test_removes_only_empty_directories(self):
        self.write('stale', 'b.json')
        self.write('partial', 'c.json')
        self.write('partial', 'keep.json')
        self.run_ops({'replace': [], 'remove': [self.path('stale', 'b.json'), self.path('partial', 'c.json')],
                      'rmdir': [self.path('stale'), self.path('partial'), self.path('absent')]})
        self.assertFalse((self.dir / 'stale').exists())
        self.assertEqual(sorted(p.name for p in (self.dir / 'partial').iterdir()), ['keep.json'])

    def test_accepts_requests_without_rmdir(self):
        self.write('cur', 'old.json')
        self.run_ops({'replace': [], 'remove': [self.path('cur', 'old.json')]})
        self.assertEqual(list((self.dir / 'cur').iterdir()), [])


if __name__ == '__main__':
    unittest.main()
