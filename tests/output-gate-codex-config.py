#!/usr/bin/env python3
"""出力ゲートが Codex の config.toml に書くマシン固有の行を、足す・外す処理を確かめる。"""
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest

REPO = Path(__file__).resolve().parents[1]
TOOL = REPO / 'agent-shared/bin/output-gate-codex-config.py'
FEATURES = {'token_budget': False, 'context_management': False, 'output_token_replay': False,
            'enable_request_compression': False}


class ConfigTests(unittest.TestCase):
    def setUp(self):
        self.path = Path(tempfile.mkdtemp()) / 'config.toml'

    def run_tool(self, *args):
        result = subprocess.run([sys.executable, '-I', str(TOOL), *args, str(self.path)],
                                capture_output=True, text=True, encoding='utf-8')
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def parsed(self):
        return tomllib.loads(self.path.read_text(encoding='utf-8'))

    def test_apply_inserts_top_level_key_and_features(self):
        self.path.write_text('model = "m"\n\n[features]\nhooks = true\n\n[tui]\nx = 1\n', encoding='utf-8')
        self.assertEqual(self.run_tool('apply', '--port', '18800'), 'changed')
        data = self.parsed()
        self.assertEqual(data['openai_base_url'], 'http://127.0.0.1:18800/backend-api/codex')
        self.assertEqual(data['model'], 'm')
        self.assertEqual(data['features'], dict(FEATURES, hooks=True))
        self.assertEqual(data['tui'], {'x': 1})

    def test_apply_is_idempotent(self):
        self.path.write_text('model = "m"\n[features]\nhooks = true\n', encoding='utf-8')
        self.run_tool('apply', '--port', '18800')
        before = self.path.read_bytes()
        self.assertEqual(self.run_tool('apply', '--port', '18800'), 'unchanged')
        self.assertEqual(self.path.read_bytes(), before)

    def test_apply_without_features_is_idempotent(self):
        self.path.write_text('model = "m"\n', encoding='utf-8')
        self.run_tool('apply', '--port', '18800')
        before = self.path.read_bytes()
        self.assertEqual(self.run_tool('apply', '--port', '18800'), 'unchanged')
        self.assertEqual(self.path.read_bytes(), before)

    def test_apply_updates_port(self):
        self.path.write_text('model = "m"\n', encoding='utf-8')
        self.run_tool('apply', '--port', '18800')
        self.run_tool('apply', '--port', '18801')
        self.assertEqual(self.parsed()['openai_base_url'], 'http://127.0.0.1:18801/backend-api/codex')
        self.assertEqual(self.path.read_text(encoding='utf-8').count('openai_base_url'), 1)

    def test_apply_without_features_table_appends_it(self):
        self.path.write_text('[tui]\nx = 1\n', encoding='utf-8')
        self.run_tool('apply', '--port', '18800')
        self.assertEqual(self.parsed()['features'], FEATURES)
        self.assertEqual(self.parsed()['tui'], {'x': 1})

    def test_apply_overrides_enabled_feature(self):
        self.path.write_text('[features]\nenable_request_compression = true\n', encoding='utf-8')
        self.run_tool('apply', '--port', '18800')
        self.assertIs(self.parsed()['features']['enable_request_compression'], False)

    def test_remove_restores_other_content(self):
        original = 'model = "m"\n\n[features]\nhooks = true\n\n[tui]\nx = 1\n'
        self.path.write_text(original, encoding='utf-8')
        self.run_tool('apply', '--port', '18800')
        self.assertEqual(self.run_tool('remove'), 'changed')
        self.assertEqual(self.path.read_text(encoding='utf-8'), original)

    def test_refuses_edit_that_would_change_other_settings(self):
        # 行単位の編集では、複数行の文字列の中の行を表の見出しと区別できない。書いた結果が意図した設定に
        # ならないなら、書かずに失敗する。
        original = 'developer_instructions = """\n[features]\n"""\n\n[tui]\nx = 1\n'
        self.path.write_text(original, encoding='utf-8')
        result = subprocess.run([sys.executable, '-I', str(TOOL), 'apply', '--port', '18800', str(self.path)],
                                capture_output=True, text=True, encoding='utf-8')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.path.read_text(encoding='utf-8'), original)

    def test_crlf_is_kept(self):
        self.path.write_bytes(b'model = "m"\r\n[features]\r\nhooks = true\r\n')
        self.run_tool('apply', '--port', '18800')
        raw = self.path.read_bytes()
        self.assertNotIn(b'\n', raw.replace(b'\r\n', b''))


if __name__ == '__main__':
    unittest.main()
