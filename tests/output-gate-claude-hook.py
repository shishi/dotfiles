#!/usr/bin/env python3
"""mod を使えない環境向けの、出力ゲートの Claude Code の hook (MessageDisplay と UserPromptSubmit) を確かめる。"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest

REPO = Path(__file__).resolve().parents[1]
# 入口の output-gate-claude.sh は Python を探して起動するだけなので、本体を直接起動する。
HOOK = REPO / 'agent-shared/hooks/lib/output-gate-claude.py'


class ClaudeHookTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.state = self.tmp / 'state'
        (self.state / 'output-gate').mkdir(parents=True)
        (self.state / 'output-gate' / 'claude-enabled').write_text('', encoding='utf-8')
        self.transcript = self.tmp / 'transcript.jsonl'
        self.transcript.write_text(json.dumps({'type': 'user', 'message': {'role': 'user', 'content': '設定を教えて'}},
                                              ensure_ascii=False) + '\n', encoding='utf-8')
        self.calls = self.tmp / 'calls.jsonl'
        self.checker = self.tmp / 'checker.py'
        self.checker.write_text(textwrap.dedent(f'''\
            import json, os, sys
            payload = json.load(sys.stdin)
            open({str(self.calls)!r}, 'a', encoding='utf-8').write(json.dumps(payload, ensure_ascii=False) + "\\n")
            if os.environ.get('FAKE_CHECK_NO_REASON'):
                print(json.dumps({{"status": "unchecked", "text": payload["draft"]}}))
            elif os.environ.get('FAKE_CHECK_FAIL'):
                print(json.dumps({{"status": "unchecked", "reason": "fake",
                                   "text": "[出力ゲート: 検査できませんでした — fake]\\n\\n" + payload["draft"]}}))
            else:
                print(json.dumps({{"status": "checked", "text": payload["draft"].replace("効く", "速い"),
                                   "reason": None, "applied": 1}}))
            '''), encoding='utf-8')

    def hook(self, mode, event, **env_extra):
        env = dict(os.environ, XDG_STATE_HOME=str(self.state),
                   OUTPUT_GATE_CHECK_CMD=json.dumps([sys.executable, '-I', str(self.checker)]))
        env.pop('AGENT_DELEGATED_SESSION', None)
        env.update(env_extra)
        base = {'session_id': 's1', 'transcript_path': str(self.transcript), 'cwd': str(self.tmp)}
        result = subprocess.run([sys.executable, '-I', str(HOOK), mode], input=json.dumps({**base, **event}, ensure_ascii=False),
                                capture_output=True, text=True, encoding='utf-8', env=env, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout) if result.stdout.strip() else None

    def display(self, delta, final, index=0, message='m1', **env):
        return self.hook('display', {'hook_event_name': 'MessageDisplay', 'turn_id': 't1', 'message_id': message,
                                     'index': index, 'final': final, 'delta': delta}, **env)

    @staticmethod
    def shown(out):
        return out['hookSpecificOutput']['displayContent']

    def checker_calls(self):
        return [json.loads(l) for l in self.calls.read_text(encoding='utf-8').splitlines()] if self.calls.exists() else []

    def test_final_flush_shows_the_corrected_answer(self):
        out = self.display('これは効く。', final=True)
        self.assertEqual(self.shown(out), 'これは速い。')
        call = self.checker_calls()[0]
        self.assertEqual((call['cli'], call['draft'], call['latest_user']), ('claude', 'これは効く。', '設定を教えて'))

    def test_lines_are_held_until_the_message_ends(self):
        self.assertEqual(self.shown(self.display('一行目は効く。\n', final=False)), '')
        out = self.display('二行目も効く。', final=True, index=1)
        self.assertEqual(self.shown(out), '一行目は速い。\n二行目も速い。')
        self.assertEqual(len(self.checker_calls()), 1)

    def test_correction_is_told_to_claude_at_the_next_prompt_once(self):
        self.display('これは効く。', final=True)
        out = self.hook('prompt', {'hook_event_name': 'UserPromptSubmit', 'prompt': '次'})
        context = out['hookSpecificOutput']['additionalContext']
        self.assertIn('これは速い。', context)
        self.assertIsNone(self.hook('prompt', {'hook_event_name': 'UserPromptSubmit', 'prompt': '次'}))

    def test_unchanged_answer_records_no_correction(self):
        self.assertEqual(self.shown(self.display('問題ありません。', final=True)), '問題ありません。')
        self.assertIsNone(self.hook('prompt', {'hook_event_name': 'UserPromptSubmit', 'prompt': '次'}))

    def test_failed_check_shows_the_original_with_the_reason(self):
        out = self.display('これは効く。', final=True, FAKE_CHECK_FAIL='1')
        self.assertTrue(self.shown(out).startswith('[出力ゲート: 検査できませんでした'))
        self.assertTrue(self.shown(out).endswith('これは効く。'))

    def test_disabled_machine_does_nothing(self):
        (self.state / 'output-gate' / 'claude-enabled').unlink()
        self.assertIsNone(self.display('これは効く。', final=True))
        self.assertEqual(self.checker_calls(), [])

    def test_sessions_where_the_mod_runs_are_left_to_the_mod(self):
        # mod は印に今のターンの識別子を書く。同じターンの回答なら、この hook は何もしない。
        marker = self.state / 'output-gate' / 'claude-mod' / 's1'
        marker.parent.mkdir(parents=True)
        marker.write_text('t1', encoding='utf-8')
        self.assertIsNone(self.display('これは効く。', final=True))
        self.assertEqual(self.checker_calls(), [])

    def test_unchecked_result_without_reason_gets_one(self):
        out = self.display('これは効く。', final=True, FAKE_CHECK_NO_REASON='1')
        self.assertTrue(self.shown(out).startswith('[出力ゲート: 検査できませんでした'))
        self.assertTrue(self.shown(out).endswith('これは効く。'))

    def test_marker_of_another_turn_is_ignored(self):
        # 以前 mod が動いたセッションを、mod の無い環境で再開した場合は、印が前のターンのものなので検査する。
        marker = self.state / 'output-gate' / 'claude-mod' / 's1'
        marker.parent.mkdir(parents=True)
        marker.write_text('t0', encoding='utf-8')
        self.assertEqual(self.shown(self.display('これは効く。', final=True)), 'これは速い。')

    def test_old_session_files_are_cleaned_up_at_a_prompt(self):
        old_dir = self.state / 'output-gate' / 'claude-display' / 'old-session'
        old_dir.mkdir(parents=True)
        (old_dir / 'm9.txt').write_text('途中', encoding='utf-8')
        old_marker = self.state / 'output-gate' / 'claude-mod' / 'old-session'
        old_marker.parent.mkdir(parents=True)
        old_marker.write_text('', encoding='utf-8')
        week = old_marker.stat().st_mtime - 8 * 86400
        for path in (old_dir / 'm9.txt', old_dir, old_marker):
            os.utime(path, (week, week))
        self.hook('prompt', {'hook_event_name': 'UserPromptSubmit', 'prompt': '次'})
        self.assertFalse(old_dir.exists())
        self.assertFalse(old_marker.exists())

    def test_correction_of_a_long_idle_session_is_still_told(self):
        self.display('これは効く。', final=True)
        session_dir = self.state / 'output-gate' / 'claude-display' / 's1'
        week = session_dir.stat().st_mtime - 8 * 86400
        for path in (session_dir / 'corrections.txt', session_dir):
            os.utime(path, (week, week))
        out = self.hook('prompt', {'hook_event_name': 'UserPromptSubmit', 'prompt': '次'})
        self.assertIn('これは速い。', out['hookSpecificOutput']['additionalContext'])

    def test_delegated_sessions_are_not_checked(self):
        self.assertIsNone(self.display('これは効く。', final=True, AGENT_DELEGATED_SESSION='1'))
        self.assertEqual(self.checker_calls(), [])

    def test_subagent_messages_are_not_checked(self):
        out = self.hook('display', {'hook_event_name': 'MessageDisplay', 'turn_id': 't1', 'message_id': 'm2',
                                    'index': 0, 'final': True, 'delta': 'これは効く。', 'agent_id': 'a1'})
        self.assertIsNone(out)


if __name__ == '__main__':
    unittest.main()
