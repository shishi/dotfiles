#!/usr/bin/env python3
"""mod を使えない環境向けの、出力ゲートの Claude Code の hook (MessageDisplay と UserPromptSubmit) を確かめる。"""
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from unittest import mock

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
        event = {'hook_event_name': 'MessageDisplay', 'turn_id': 't1', 'message_id': message, 'final': final,
                 'delta': delta}
        if index is not None:
            event['index'] = index
        return self.hook('display', event, **env)

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

    def test_a_marker_naming_another_turn_id_still_leaves_the_answer_to_the_mod(self):
        # 対話 CLI の MessageDisplay の turn_id は、mod の turnId と別に作られる値なので、印の中身とは一致しない。
        marker = self.state / 'output-gate' / 'claude-mod' / 's1'
        marker.parent.mkdir(parents=True)
        marker.write_text('mod-turn', encoding='utf-8')
        self.assertIsNone(self.display('これは効く。', final=True))
        self.assertEqual(self.checker_calls(), [])

    def test_a_marker_removed_in_the_middle_of_a_message_keeps_it_with_the_mod(self):
        # ターン中に送られた入力の UserPromptSubmit が、回答の表示の途中で印を消す場合。後半だけを検査しない。
        marker = self.state / 'output-gate' / 'claude-mod' / 's1'
        marker.parent.mkdir(parents=True)
        marker.write_text('mod-turn', encoding='utf-8')
        self.assertIsNone(self.display('一行目は効く。\n', final=False))
        self.hook('prompt', {'hook_event_name': 'UserPromptSubmit', 'prompt': '追加の依頼'})
        self.assertIsNone(self.display('二行目も効く。', final=True, index=1))
        self.assertEqual(self.checker_calls(), [])

    def test_a_call_without_an_index_is_taken_as_the_first(self):
        # SDK 経由は index 0 の最後の呼び出しだけ。index が欠けた入力も、その回答の最初の断片として扱って検査する。
        self.assertEqual(self.shown(self.display('これは効く。', final=True, index=None)), 'これは速い。')

    def test_calls_running_side_by_side_are_put_together_in_index_order(self):
        # 対話 CLI は同じ回答の呼び出しを最大 3 件並べて動かす。最後の呼び出しが先に動き、前の断片が逆順に届いても、
        # 最後の呼び出しは全ての断片を待ち、index の順に組み立てて検査する。
        with ThreadPoolExecutor(max_workers=1) as pool:
            last = pool.submit(self.display, '三行目も効く。', True, 2)
            time.sleep(0.5)
            self.assertEqual(self.shown(self.display('二行目も効く。\n', final=False, index=1)), '')
            self.assertEqual(self.shown(self.display('一行目は効く。\n', final=False, index=0)), '')
            self.assertEqual(self.shown(last.result()), '一行目は速い。\n二行目も速い。\n三行目も速い。')
        self.assertEqual([c['draft'] for c in self.checker_calls()], ['一行目は効く。\n二行目も効く。\n三行目も効く。'])

    def test_a_part_already_put_together_is_not_shown_again(self):
        # 組み立てに使った index の呼び出しが後から動いても、その行をもう一度見せない (二重に表示しない)。
        self.display('一行目は効く。\n', final=False, index=0)
        self.assertEqual(self.shown(self.display('二行目も効く。', final=True, index=1)), '一行目は速い。\n二行目も速い。')
        self.assertEqual(self.shown(self.display('一行目は効く。\n', final=False, index=0)), '')

    def test_a_failure_while_putting_the_answer_together_shows_the_held_text_with_the_reason(self):
        # 状態ディレクトリを扱えない (Windows で別のプロセスが開いているなど) ときも、hook ごと落ちずに、
        # 手元の原文に理由を添えて見せる。
        self.display('一行目は効く。\n', final=False, index=0)
        parts = self.state / 'output-gate' / 'claude-display' / 's1' / 'm1'
        (parts / '1.part').mkdir()   # 最後の呼び出しの行を書けなくする
        out = self.display('二行目も効く。', final=True, index=1)
        self.assertTrue(self.shown(out).startswith('[出力ゲート: 検査できませんでした'))
        self.assertTrue(self.shown(out).endswith('一行目は効く。\n二行目も効く。'))

    def test_a_part_written_while_a_failed_final_call_takes_the_lock_is_not_lost(self):
        # 失敗の経路の最後の呼び出しが錠を取る直前に、前の index の呼び出しが行を書いて '' を返しても、その行を失わない。
        self.display('一行目は効く。\n', final=False, index=0)
        session_dir = self.state / 'output-gate' / 'claude-display' / 's1'
        (session_dir / 'm1' / '2.part').mkdir()   # 最後の呼び出しの行を書けなくして、失敗の経路に入れる
        spec = importlib.util.spec_from_file_location('output_gate_claude_race', HOOK)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        real_lock, shown, late = module.message_lock, [], []

        def lock_after_a_late_part(path, *args, **kwargs):
            if kwargs.get('wait') is not None and not late:   # 失敗の経路が錠を取る直前に割り込む
                late.append(self.display('二行目も効く。\n', final=False, index=1))
            return real_lock(path, *args, **kwargs)

        module.message_lock = lock_after_a_late_part
        module.emit = shown.append
        event = {'session_id': 's1', 'message_id': 'm1', 'index': 2, 'final': True, 'delta': '三行目も効く。'}
        module.display(event, session_dir, mod_runs=False)
        self.assertEqual(self.shown(late[0]), '')
        self.assertTrue(self.shown(shown[0]).endswith('一行目は効く。\n二行目も効く。\n三行目も効く。'))

    def test_a_part_after_a_failed_final_call_is_still_shown(self):
        # 最後の呼び出しが失敗の経路で表示した後に、前の index の呼び出しが動いても、その行を隠したままにしない。
        self.display('一行目は効く。\n', final=False, index=0)
        parts = self.state / 'output-gate' / 'claude-display' / 's1' / 'm1'
        (parts / '2.part').mkdir()
        out = self.display('三行目も効く。', final=True, index=2)
        self.assertTrue(self.shown(out).endswith('一行目は効く。\n三行目も効く。'))
        self.assertEqual(self.shown(self.display('二行目も効く。\n', final=False, index=1)), '二行目も効く。\n')

    def test_a_part_that_does_not_arrive_in_time_is_not_dropped(self):
        # 上限まで待っても断片が揃わなければ、検査せずに手元の原文全体を理由付きで見せる。遅れて届いた断片は
        # そのまま見せる (隠したままにしない)。
        self.display('一行目は効く。\n', final=False, index=0)
        out = self.display('三行目も効く。', final=True, index=2)
        self.assertTrue(self.shown(out).startswith('[出力ゲート: 検査できませんでした'))
        self.assertTrue(self.shown(out).endswith('一行目は効く。\n三行目も効く。'))
        self.assertEqual(self.shown(self.display('二行目も効く。\n', final=False, index=1)), '二行目も効く。\n')
        self.assertEqual(self.checker_calls(), [])

    def test_a_marker_written_in_the_middle_of_a_message_does_not_drop_the_held_lines(self):
        self.assertEqual(self.shown(self.display('一行目は効く。\n', final=False)), '')
        marker = self.state / 'output-gate' / 'claude-mod' / 's1'
        marker.parent.mkdir(parents=True)
        marker.write_text('mod-turn', encoding='utf-8')
        out = self.display('二行目も効く。', final=True, index=1)
        self.assertEqual(self.shown(out), '一行目は速い。\n二行目も速い。')

    def test_a_marker_from_before_the_latest_prompt_is_ignored(self):
        # 以前 mod が動いたセッションを、mod の無い環境で再開した場合: 利用者の入力で印が消え、mod が書き直さないので検査する。
        marker = self.state / 'output-gate' / 'claude-mod' / 's1'
        marker.parent.mkdir(parents=True)
        marker.write_text('mod-turn', encoding='utf-8')
        self.hook('prompt', {'hook_event_name': 'UserPromptSubmit', 'prompt': '次'})
        self.assertEqual(self.shown(self.display('これは効く。', final=True)), 'これは速い。')

    def test_only_the_end_of_a_long_transcript_is_read(self):
        # 検査役に渡すのは直近の発言と最新の利用者の発言だけなので、記録の前の方は読まない。渡す内容は変えない。
        filler = {'type': 'user', 'message': {'role': 'user', 'content': [
            {'type': 'tool_result', 'tool_use_id': 'toolu_1', 'content': 'x' * 1000}]}}
        answers = [{'type': 'assistant', 'message': {'role': 'assistant', 'content': [{'type': 'text', 'text': f'回答{i}'}]}}
                   for i in range(12)]
        self.record(*[filler] * 4000, {'type': 'user', 'message': {'role': 'user', 'content': '最新の依頼'}}, *answers)
        spec = importlib.util.spec_from_file_location('output_gate_claude', HOOK)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        read = [0]

        class CountingFile:
            def __init__(self, f):
                self.f = f

            def __enter__(self):
                return self

            def __exit__(self, *error):
                self.f.close()

            def seek(self, *args):
                return self.f.seek(*args)

            def read(self, *args):
                data = self.f.read(*args)
                read[0] += len(data)
                return data

        class CountingPath(type(Path())):
            def read_text(self, *args, **kwargs):
                text = super().read_text(*args, **kwargs)
                read[0] += len(text.encode('utf-8'))
                return text

            def open(self, *args, **kwargs):
                return CountingFile(super().open(*args, **kwargs))

        module.Path = CountingPath
        checker = json.dumps([sys.executable, '-I', str(self.checker)])
        with mock.patch.dict(os.environ, {'OUTPUT_GATE_CHECK_CMD': checker}):
            module.check('これは効く。', str(self.transcript))
        call = self.checker_calls()[0]
        self.assertEqual(call['latest_user'], '最新の依頼')
        self.assertEqual(call['conversation'], [{'role': 'assistant', 'text': f'回答{i}'} for i in range(2, 12)])
        self.assertLess(read[0], self.transcript.stat().st_size // 4)

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

    def record(self, *entries):
        with open(self.transcript, 'a', encoding='utf-8') as f:
            for entry in entries:
                f.write(json.dumps(entry, ensure_ascii=False) + '\n')

    # Claude Code が API のエラーを回答の形で会話記録に書いた行 (2.1.302 の実際の行から、判定に使わない欄を省いた)。
    ENGINE_ERROR = {'type': 'assistant', 'isApiErrorMessage': True, 'error': 'invalid_request',
                    'message': {'id': '00000000-0000-4000-8000-000000000001', 'model': '<synthetic>', 'role': 'assistant',
                                'stop_reason': 'stop_sequence', 'type': 'message',
                                'content': [{'type': 'text', 'text': 'Prompt is too long'}]}}

    def test_text_claude_code_wrote_itself_is_shown_as_is(self):
        # Desktop などの SDK 経由では、Claude Code が作った API エラーの回答にも MessageDisplay が呼ばれる。
        self.record(self.ENGINE_ERROR)
        self.assertEqual(self.shown(self.display('Prompt is too long', final=True)), 'Prompt is too long')
        self.assertEqual(self.checker_calls(), [])
        self.assertIsNone(self.hook('prompt', {'hook_event_name': 'UserPromptSubmit', 'prompt': '次'}))

    def test_an_engine_message_of_an_earlier_prompt_does_not_exempt_the_answer(self):
        # 前の入力のターンに同じ文字列のエラーがあっても、今のターンの回答は検査する。
        self.record(self.ENGINE_ERROR, {'type': 'user', 'message': {'role': 'user', 'content': '続けて'}})
        self.display('Prompt is too long', final=True)
        self.assertEqual(len(self.checker_calls()), 1)

    def test_subagent_messages_are_not_checked(self):
        out = self.hook('display', {'hook_event_name': 'MessageDisplay', 'turn_id': 't1', 'message_id': 'm2',
                                    'index': 0, 'final': True, 'delta': 'これは効く。', 'agent_id': 'a1'})
        self.assertIsNone(out)


if __name__ == '__main__':
    unittest.main()
