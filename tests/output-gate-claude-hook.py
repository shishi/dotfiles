#!/usr/bin/env python3
"""mod を使えない環境向けの、出力ゲートの Claude Code の hook (MessageDisplay と UserPromptSubmit) を確かめる。"""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
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
            elif os.environ.get('FAKE_CHECK_FINDINGS') and payload.get("final"):
                findings = [{{"kind": "unverified_claim", "source": "draft", "excerpt": payload["draft"],
                              "evidence": [{{"id": None, "state": "absent"}}]}}]
                unmet = "出力ゲート: 次の点は確かめられていません\\n- 未確認"
                marked = payload["draft"] + "\\n\\n---\\n" + unmet
                # 未達がある間は、何回目の検査でも指摘を返す (検査処理の契約)。
                message = None if payload.get("continuation") == "none" else "出力ゲートの指摘: 確かめてから答え直して"
                print(json.dumps({{"status": "checked", "text": marked, "findings": findings, "agent_message": message,
                                   "fallback_text": None if message is None else "[保存できない]\\n\\n" + marked,
                                   "unmet_text": unmet, "reason": None, "applied": 0}}))
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
        self.assertEqual((call['origin'], call['draft'], call['latest_user']), ('claude', 'これは効く。', '設定を教えて'))
        self.assertNotIn('cli', call)

    def test_an_answer_without_its_line_in_the_transcript_is_checked_as_the_final_answer(self):
        # 会話記録に同じ応答の行が無い (まだ書かれていない) 応答は、未達の判定を落とさないよう最終回答として扱う。
        self.display('これは効く。', final=True)
        call = self.checker_calls()[0]
        self.assertEqual((call['final'], call['continuation'], call['round']), (True, 'display', 0))

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

    def test_conversation_history_survives_many_assistant_messages(self):
        self.transcript.write_text('', encoding='utf-8')
        filler = {'type': 'user', 'message': {'role': 'user', 'content': [
            {'type': 'tool_result', 'tool_use_id': 'toolu_1', 'content': 'x' * 1000}]}}
        answers = [{'type': 'assistant', 'message': {'role': 'assistant', 'content': [{'type': 'text', 'text': f'回答{i}'}]}}
                   for i in range(12)]
        earlier = [{'type': 'user', 'message': {'role': 'user', 'content': text}} for text in
                   ['A と B を修正して', 'この作業の push は許可する', 'B も忘れずに']]
        self.record(*earlier, *[filler] * 4000,
                    {'type': 'user', 'message': {'role': 'user', 'content': '許可は取り消す。C の説明だけして'}}, *answers)
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
        recent, latest_user = module.message_texts(str(self.transcript))
        self.assertEqual(latest_user, '許可は取り消す。C の説明だけして')
        self.assertEqual([m['text'] for m in recent if m['role'] == 'user'],
                         ['A と B を修正して', 'この作業の push は許可する', 'B も忘れずに',
                          '許可は取り消す。C の説明だけして'])
        self.assertEqual(recent[-12:], [{'role': 'assistant', 'text': f'回答{i}'} for i in range(12)])
        self.display('C を説明する', final=True)
        collected = self.checker_calls()[-1]
        self.assertEqual([{k: m[k] for k in ('role', 'text')} for m in collected['recent_messages']], recent)
        self.assertEqual(len({source['native_id'] for source in collected['sources']}), len(recent))
        self.assertEqual([source['fields']['text'] for source in collected['sources']], [m['text'] for m in recent])

    def test_input_sent_while_working_joins_the_request(self):
        # 作業中に送られた入力は、会話記録に queued_command の添付として残る。ターンを始めた入力とつないで依頼にする。
        queued = {'type': 'attachment', 'attachment': {'type': 'queued_command', 'prompt': 'テストも回して',
                                                       'origin': {'kind': 'human'}}}
        other = {'type': 'attachment', 'attachment': {'type': 'queued_command', 'prompt': '自動の続き',
                                                      'origin': {'kind': 'task-notification'}}}
        self.record({'type': 'user', 'message': {'role': 'user', 'content': '設定を直して'}},
                    {'type': 'assistant', 'message': {'role': 'assistant', 'content': [{'type': 'text', 'text': '直すよ'}]}},
                    queued, other)
        spec = importlib.util.spec_from_file_location('output_gate_claude', HOOK)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        recent, latest_user = module.message_texts(str(self.transcript))
        self.assertEqual(latest_user, '設定を直して\n\nテストも回して')
        self.assertEqual(recent[-1], {'role': 'user', 'text': 'テストも回して'})

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

    # 会話記録の行 (Claude Code 2.1.302 の行から、判定に使わない欄を省いた形)。応答は内容のブロックごとに 1 行で、
    # 同じ応答の行は message.id と stop_reason が同じ。
    @staticmethod
    def user(text, uuid, minutes_ago=0):
        when = time.strftime('%Y-%m-%dT%H:%M:%S.000Z', time.gmtime(time.time() - minutes_ago * 60))
        return {'type': 'user', 'uuid': uuid, 'timestamp': when, 'message': {'role': 'user', 'content': text}}

    @staticmethod
    def call(message_id, call_id, name, tool_input):
        return {'type': 'assistant', 'message': {'id': message_id, 'role': 'assistant', 'stop_reason': 'tool_use',
                                                 'content': [{'type': 'tool_use', 'id': call_id, 'name': name,
                                                              'input': tool_input}]}}

    @staticmethod
    def result(call_id, tool_use_result, content='', is_error=False):
        return {'type': 'user', 'toolUseResult': tool_use_result,
                'message': {'role': 'user', 'content': [{'type': 'tool_result', 'tool_use_id': call_id,
                                                         'content': content, 'is_error': is_error}]}}

    @staticmethod
    def answer(message_id, text, stop_reason='end_turn'):
        return {'type': 'assistant', 'message': {'id': message_id, 'role': 'assistant', 'stop_reason': stop_reason,
                                                 'content': [{'type': 'text', 'text': text}]}}

    BASH_OK = {'stdout': 'a.txt\n', 'stderr': '', 'interrupted': False, 'isImage': False, 'noOutputExpected': False}

    def stop(self, message, active=False, **env):
        return self.hook('stop', {'hook_event_name': 'Stop', 'stop_hook_active': active,
                                  'last_assistant_message': message}, **env)

    def session_file(self, name):
        return self.state / 'output-gate' / 'claude-display' / 's1' / name

    @staticmethod
    def pair_name(message):
        return hashlib.sha256(re.sub(r'\s+', '', message).encode('utf-8')).hexdigest()

    def test_evidence_is_built_from_the_transcript_of_the_turn(self):
        self.transcript.write_text('', encoding='utf-8')
        self.record(self.user('ファイルを作って確かめて', 'u1'),
                    self.call('r1', 'tb1', 'Bash', {'command': 'ls', 'description': '一覧'}),
                    self.result('tb1', self.BASH_OK, 'a.txt'),
                    self.call('r2', 'tb2', 'Bash', {'command': 'false'}),
                    self.result('tb2', 'Error: Exit code 1\nboom', 'Exit code 1\nboom', is_error=True),
                    self.call('r3', 'tw1', 'Write', {'file_path': 'b.txt', 'content': 'x'}),
                    self.result('tw1', {'type': 'create', 'filePath': 'b.txt', 'content': 'x'}, 'File created'))
        self.display('作って確かめたよ', final=True)
        evidence = {item['id']: item for item in self.checker_calls()[0]['evidence']}
        self.assertEqual(list(evidence), ['tb1', 'tb2', 'tw1'])
        self.assertEqual((evidence['tb1']['tool'], evidence['tb1']['command']), ('Bash', 'ls'))
        self.assertIn('a.txt', evidence['tb1']['output'])
        self.assertFalse(evidence['tb1'].get('failed'))
        self.assertTrue(evidence['tb2']['failed'])
        self.assertEqual(evidence['tb2']['exit_code'], 1)
        self.assertTrue(evidence['tb2']['output'].startswith('Error: Exit code 1'))
        self.assertEqual((evidence['tw1']['tool'], evidence['tw1']['input']['file_path']), ('Write', 'b.txt'))
        # 組み立てた結果はモデルが見た文字列と形が違うことを、検査役への入力に書く。
        self.assertTrue(all('toolUseResult' in item['note'] for item in evidence.values()))

    def test_a_transcript_that_does_not_reach_the_latest_input_marks_the_gap(self):
        # 先頭が欠けた記録: 利用者の入力の行が無い。
        self.transcript.write_text('', encoding='utf-8')
        self.record(self.call('r1', 'tb1', 'Bash', {'command': 'ls'}), self.result('tb1', self.BASH_OK))
        self.display('一覧を見たよ', final=True)
        evidence = self.checker_calls()[0]['evidence']
        self.assertTrue(evidence[0]['unavailable'])
        self.assertEqual([item['id'] for item in evidence[1:]], ['tb1'])

    def test_the_read_limit_marks_the_gap(self):
        # 読む範囲の上限で利用者の入力まで遡れない場合も、取得できなかった範囲の印を付ける。
        self.transcript.write_text('', encoding='utf-8')
        self.record(self.user('調べて', 'u1'), *[self.result(f'old{i}', 'x' * 1000) for i in range(50)],
                    self.call('r1', 'tb1', 'Bash', {'command': 'ls'}), self.result('tb1', self.BASH_OK))
        module = self.load_hook()
        module.READ_LIMIT = 4000
        turns = module.read_turns(str(self.transcript), 'mt')
        self.assertTrue(turns['evidence'][0]['unavailable'])
        self.assertEqual(turns['evidence'][-1]['id'], 'tb1')

    def load_hook(self):
        spec = importlib.util.spec_from_file_location('output_gate_claude_unit', HOOK)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_checker_and_stop_waits_cover_the_shared_budget_and_cleanup(self):
        for override, expected in [(None, 3640), ('720', 760)]:
            with self.subTest(timeout=override), mock.patch.dict(os.environ, clear=False):
                if override is None:
                    os.environ.pop('OUTPUT_GATE_TIMEOUT', None)
                else:
                    os.environ['OUTPUT_GATE_TIMEOUT'] = override
                module = self.load_hook()
                reply = {'status': 'checked', 'text': '確認済み'}
                with mock.patch.object(module.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, json.dumps(reply).encode())) as run:
                    self.assertEqual(module.run_check({'draft': '原文'}), reply)
                    self.assertEqual(run.call_args.kwargs['timeout'], expected)
                self.assertGreaterEqual(module.STOP_WAIT, expected)
                self.assertGreaterEqual(module.CHECKING_STALE, expected)

    def test_findings_show_the_marked_answer_and_store_the_pair(self):
        out = self.display('全部通ったよ', final=True, FAKE_CHECK_FINDINGS='1')
        self.assertIn('出力ゲート: 次の点は確かめられていません', self.shown(out))
        stored = json.loads(self.session_file(self.pair_name('全部通ったよ') + '.result').read_text(encoding='utf-8'))
        self.assertEqual(stored['agent_message'], '出力ゲートの指摘: 確かめてから答え直して')
        self.assertFalse(self.session_file(self.pair_name('全部通ったよ') + '.checking').exists())

    def test_text_before_a_tool_call_is_checked_by_the_rules_and_passed_as_shown_text(self):
        self.transcript.write_text('', encoding='utf-8')
        self.record(self.user('テストして', 'u1'), self.answer('r1', 'これからテストするね', 'tool_use'),
                    self.call('r1', 'tb1', 'Bash', {'command': 'pytest'}))
        out = self.display('これからテストするね', final=True, message='m1', FAKE_CHECK_FINDINGS='1')
        self.assertEqual(self.shown(out), 'これからテストするね')
        self.assertFalse(self.checker_calls()[0]['final'])
        self.record(self.result('tb1', self.BASH_OK), self.answer('r2', 'テストは通ったよ'))
        self.display('テストは通ったよ', final=True, message='m2')
        last = self.checker_calls()[1]
        self.assertTrue(last['final'])
        self.assertIn('これからテストするね', last['shown_text'])

    def test_previous_turns_are_passed_apart_from_this_turn(self):
        self.transcript.write_text('', encoding='utf-8')
        self.record(self.call('r0', 'p0', 'Bash', {'command': 'old'}), self.result('p0', self.BASH_OK),
                    self.user('テストを走らせて', 'u1', minutes_ago=5),
                    self.call('r1', 'p1', 'Bash', {'command': 'pytest'}), self.result('p1', self.BASH_OK),
                    self.answer('r2', 'テストは通ったよ。次は README を直す計画だよ'),
                    self.user('じゃあ進めて', 'u2'),
                    self.call('r3', 'c1', 'Edit', {'file_path': 'README.md'}), self.result('c1', {'filePath': 'README.md'}))
        self.display('README を直したよ', final=True)
        call = self.checker_calls()[0]
        self.assertEqual([item['id'] for item in call['evidence']], ['c1'])
        self.assertEqual(len(call['previous_evidence']), 1)   # 遡れなかったターン (p0) は入らない
        previous = call['previous_evidence'][0]
        self.assertEqual(([item['id'] for item in previous['items']], previous['turn_id']), (['p1'], 'u1'))
        self.assertTrue(previous['time'])
        self.assertEqual([m['text'] for m in call['turn_start_context']],
                         ['テストを走らせて', 'テストは通ったよ。次は README を直す計画だよ', 'じゃあ進めて'])

    def test_the_first_check_stores_the_text_and_the_message_and_stop_returns_the_message(self):
        out = self.display('全部通ったよ', final=True, FAKE_CHECK_FINDINGS='1')
        self.assertIn('全部通ったよ', self.shown(out))
        decision = self.stop('全部通ったよ')
        self.assertEqual(decision, {'decision': 'block', 'reason': '出力ゲートの指摘: 確かめてから答え直して'})
        self.assertTrue(self.session_file(self.pair_name('全部通ったよ') + '.blocked').exists())

    def test_answers_are_sent_back_until_no_findings_remain(self):
        self.transcript.write_text('', encoding='utf-8')
        self.record(self.user('テストして', 'u1'))
        self.display('全部通ったよ', final=True, message='m1', FAKE_CHECK_FINDINGS='1')
        self.assertEqual(self.stop('全部通ったよ')['decision'], 'block')
        # Claude Code は Stop hook の指摘を isMeta の利用者の行として書く。利用者の入力として扱わない。
        self.record({'type': 'user', 'isMeta': True, 'message': {'role': 'user', 'content': 'Stop hook feedback:\n指摘'}},
                    self.answer('r9', 'テストは未実施だよ'))
        self.display('テストは未実施だよ', final=True, message='m2', FAKE_CHECK_FINDINGS='1')
        second = self.checker_calls()[1]
        self.assertEqual((second['round'], second['latest_user']), (1, 'テストして'))
        self.assertEqual(second['previous_findings'],
                         [{'kind': 'unverified_claim', 'source': 'draft', 'excerpt': '全部通ったよ',
                           'evidence': [{'id': None, 'state': 'absent'}]}])
        # 直させた後の回答にも未達が残れば、また差し戻し、回数を進める。
        self.assertEqual(self.stop('テストは未実施だよ')['decision'], 'block')
        self.assertEqual(json.loads(self.session_file('u1.round.json').read_text(encoding='utf-8'))['round'], 2)
        self.record({'type': 'user', 'isMeta': True, 'message': {'role': 'user', 'content': 'Stop hook feedback:\n指摘'}},
                    self.answer('r10', 'pytest を流して 3 件通ったよ'))
        self.display('pytest を流して 3 件通ったよ', final=True, message='m3', FAKE_CHECK_FINDINGS='1')
        third = self.checker_calls()[2]
        self.assertEqual(third['round'], 2)
        self.assertEqual([f['excerpt'] for f in third['previous_findings']], ['テストは未実施だよ'])
        self.assertEqual(self.stop('pytest を流して 3 件通ったよ')['decision'], 'block')
        # 未達の無い回答は差し戻さない。
        self.record(self.answer('r11', '3 件通ったのを確かめたよ'))
        self.display('3 件通ったのを確かめたよ', final=True, message='m4')
        self.assertEqual(self.checker_calls()[3]['round'], 3)
        self.assertIsNone(self.stop('3 件通ったのを確かめたよ'))

    def test_stop_blocks_a_pair_once_even_after_another_hook_blocked(self):
        self.display('全部通ったよ', final=True, FAKE_CHECK_FINDINGS='1')
        self.assertEqual(self.stop('全部通ったよ', active=True)['decision'], 'block')
        self.assertIsNone(self.stop('全部通ったよ', active=True))
        self.assertIsNone(self.stop('全部通ったよ'))

    def test_checkpoint_from_the_checker_survives_stop_and_the_next_answer(self):
        self.display('全部通ったよ', final=True, FAKE_CHECK_FINDINGS='1')
        path = self.session_file(self.pair_name('全部通ったよ') + '.result')
        result = json.loads(path.read_text(encoding='utf-8'))
        checkpoint = {'round': 0, 'stalled': 0, 'bodies': ['全部通ったよ'], 'findings': [], 'evidence': []}
        result['progress_state'] = checkpoint
        path.write_text(json.dumps(result), encoding='utf-8')
        self.stop('全部通ったよ')
        self.display('まだ確認中だよ', final=True, message='m2', FAKE_CHECK_FINDINGS='1')
        self.assertEqual(self.checker_calls()[-1].get('progress_state'), checkpoint)

    def test_stop_does_not_block_when_its_continuation_state_cannot_be_saved(self):
        module = self.load_hook()
        session = self.session_file('')
        session.mkdir(parents=True, exist_ok=True)
        pair = self.pair_name('全部通ったよ')
        (session / (pair + '.result')).write_text(json.dumps({
            'round': 0, 'turn': 'u1', 'agent_message': '指摘', 'findings': []}), encoding='utf-8')
        shown = []
        module.emit = shown.append
        with mock.patch.object(module, 'write_json', side_effect=OSError('read only')):
            module.stop({'last_assistant_message': '全部通ったよ'}, session)
        self.assertFalse(any(item.get('decision') == 'block' for item in shown))

    def test_transcript_cursor_keeps_distinct_queued_duplicates_without_rescanning(self):
        module = self.load_hook()
        context = self.tmp / 'cursor-context'
        context.mkdir()
        first, _, _, cursor = module.transcript_delta(str(self.transcript), context)
        self.assertTrue(first)
        (context / 'collector-hook.json').write_text(json.dumps(cursor), encoding='utf-8')
        self.record({'type': 'attachment', 'uuid': 'queued-1', 'attachment': {'type': 'queued_command', 'prompt': '同じ入力'}},
                    {'type': 'attachment', 'uuid': 'queued-2', 'attachment': {'type': 'queued_command', 'prompt': '同じ入力'}})
        second, _, latest, second_cursor = module.transcript_delta(str(self.transcript), context)
        self.assertEqual([s['native_id'] for s in second], ['queued-1', 'queued-2'])
        self.assertEqual([s['fields']['text'] for s in second], ['同じ入力', '同じ入力'])
        self.assertTrue(latest.endswith('同じ入力\n\n同じ入力'))
        self.assertEqual(cursor['source_mode'], 'bootstrap')
        self.assertEqual(second_cursor['source_mode'], 'delta')
        second_cursor['invalid'] = True
        (context / 'collector-hook.json').write_text(json.dumps(second_cursor), encoding='utf-8')
        reset, _, _, reset_cursor = module.transcript_delta(str(self.transcript), context)
        self.assertTrue(any(source['kind'] == 'gap' for source in reset))
        self.assertEqual(reset_cursor['source_mode'], 'bootstrap')

    def test_transcript_ingestion_pins_tool_originals_before_legacy_turn_limit(self):
        module = self.load_hook()
        self.transcript.write_text('', encoding='utf-8')
        self.record({'type': 'user', 'uuid': 'old-user', 'message': {'role': 'user', 'content': '古い確認'}},
            {'type': 'assistant', 'message': {'role': 'assistant', 'content': [{'type': 'tool_use', 'id': 'old-call', 'name': 'Bash', 'input': {'command': 'check'}}]}},
            {'type': 'user', 'message': {'role': 'user', 'content': [{'type': 'tool_result', 'tool_use_id': 'old-call', 'is_error': True, 'content': 'FAILED original'}]}})
        for number in range(15):
            self.record({'type': 'user', 'uuid': f'later-{number}', 'message': {'role': 'user', 'content': f'別件 {number}'}})
        sources, _, _, _ = module.transcript_delta(str(self.transcript), self.tmp / 'new-context')
        old = next(source for source in sources if source['native_id'] == 'old-call')
        self.assertEqual(old['fields']['output'], 'FAILED original')
        self.assertTrue(old['metadata']['failed'])
        self.assertEqual(old['turn_id'], 'old-user')
        self.assertLess(old['metadata']['call_position'], old['metadata']['result_position'])

    def test_stop_without_a_pair_does_nothing(self):
        self.assertIsNone(self.stop('関係ない回答'))

    def test_stop_waits_for_a_check_in_progress(self):
        name = self.pair_name('全部通ったよ')
        self.session_file('').mkdir(parents=True, exist_ok=True)
        self.session_file(name + '.checking').write_text('', encoding='utf-8')

        turn = self.load_hook().latest_input_key(str(self.transcript))

        def finish():
            time.sleep(1.0)
            self.session_file(name + '.result').write_text(
                json.dumps({'round': 0, 'turn': turn, 'agent_message': '指摘', 'findings': []}), encoding='utf-8')
            self.session_file(name + '.checking').unlink()
        with ThreadPoolExecutor(max_workers=1) as pool:
            pool.submit(finish)
            self.assertEqual(self.stop('全部通ったよ'), {'decision': 'block', 'reason': '指摘'})

    def test_stop_gives_up_when_the_check_does_not_finish_in_time(self):
        module = self.load_hook()
        module.STOP_WAIT = 0.3
        session_dir = self.session_file('')
        session_dir.mkdir(parents=True, exist_ok=True)
        (session_dir / (self.pair_name('全部通ったよ') + '.checking')).write_text('', encoding='utf-8')
        shown = []
        module.emit = shown.append
        module.stop({'last_assistant_message': '全部通ったよ'}, session_dir)
        self.assertEqual(shown, [])
        log = (session_dir / 'stop.log').read_text(encoding='utf-8')
        self.assertIn('did not finish', log)

    def test_stop_does_nothing_in_a_session_where_the_mod_runs(self):
        self.display('全部通ったよ', final=True, FAKE_CHECK_FINDINGS='1')
        marker = self.state / 'output-gate' / 'claude-mod' / 's1'
        marker.parent.mkdir(parents=True)
        marker.write_text('mod-turn', encoding='utf-8')
        self.assertIsNone(self.stop('全部通ったよ'))

    def test_an_answer_mistaken_for_the_final_one_does_not_advance_the_round(self):
        # 行がまだ書かれていない途中の応答を最終回答と取り違えても、Stop が block していなければ回数は進まない。
        self.transcript.write_text('', encoding='utf-8')
        self.record(self.user('テストして', 'u1'))
        self.display('これからテストするね', final=True, message='m1', FAKE_CHECK_FINDINGS='1')
        self.record(self.answer('r1', 'これからテストするね', 'tool_use'), self.call('r1', 'tb1', 'Bash', {'command': 'pytest'}),
                    self.result('tb1', self.BASH_OK), self.answer('r2', '全部通ったよ'))
        self.display('全部通ったよ', final=True, message='m2', FAKE_CHECK_FINDINGS='1')
        self.assertEqual(self.checker_calls()[1]['round'], 0)
        self.assertEqual(self.stop('全部通ったよ')['decision'], 'block')
        self.assertEqual(json.loads(self.session_file('u1.round.json').read_text(encoding='utf-8'))['round'], 1)

    def test_stop_that_runs_before_the_display_waits_for_the_check(self):
        with ThreadPoolExecutor(max_workers=1) as pool:
            stopped = pool.submit(self.stop, '全部通ったよ')
            time.sleep(0.3)
            self.display('全部通ったよ', final=True, FAKE_CHECK_FINDINGS='1')
            self.assertEqual(stopped.result()['decision'], 'block')

    def test_the_same_answer_in_a_later_turn_does_not_reuse_the_old_result(self):
        self.transcript.write_text('', encoding='utf-8')
        self.record(self.user('テストして', 'u1'))
        self.display('全部通ったよ', final=True, message='m1', FAKE_CHECK_FINDINGS='1')
        self.record(self.user('もう一度', 'u2'))
        self.display('全部通ったよ', final=True, message='m2')
        stored = json.loads(self.session_file(self.pair_name('全部通ったよ') + '.result').read_text(encoding='utf-8'))
        self.assertEqual((stored['turn'], stored['agent_message']), ('u2', None))   # 未達なしの結果も保存する
        self.assertIsNone(self.stop('全部通ったよ'))

    def test_stop_does_not_use_a_result_of_an_earlier_turn(self):
        # 次のターンの Stop hook が、その回答の検査より先に動いても、前のターンの結果で差し戻さない。
        self.transcript.write_text('', encoding='utf-8')
        self.record(self.user('テストして', 'u1'))
        self.display('全部通ったよ', final=True, message='m1', FAKE_CHECK_FINDINGS='1')
        self.record(self.user('もう一度', 'u2'))
        self.assertIsNone(self.stop('全部通ったよ'))

    def test_stop_that_runs_first_ignores_the_result_of_an_earlier_turn_and_waits_for_this_one(self):
        # 前のターンの同じ本文の結果が残っている状態で Stop が先に動いても、今回の検査の結果が出るまで待って差し戻す。
        self.transcript.write_text('', encoding='utf-8')
        self.record(self.user('テストして', 'u1'))
        self.display('全部通ったよ', final=True, message='m1', FAKE_CHECK_FINDINGS='1')
        self.record(self.user('もう一度', 'u2'))
        with ThreadPoolExecutor(max_workers=1) as pool:
            stopped = pool.submit(self.stop, '全部通ったよ')
            time.sleep(0.3)
            self.display('全部通ったよ', final=True, message='m2', FAKE_CHECK_FINDINGS='1')
            self.assertEqual(stopped.result()['decision'], 'block')

    def test_stop_finds_the_pair_when_only_whitespace_differs(self):
        self.display('全部通ったよ', final=True, FAKE_CHECK_FINDINGS='1')
        self.assertEqual(self.stop('全部\n通ったよ ')['decision'], 'block')

    def test_an_unreachable_turn_start_still_keys_the_turn_by_the_latest_input(self):
        self.transcript.write_text('', encoding='utf-8')
        self.record(self.user('調べて', 'u1'), *[self.result(f'old{i}', 'x' * 1000) for i in range(50)])
        module = self.load_hook()
        module.READ_LIMIT = 4000
        session_dir = self.session_file('')
        session_dir.mkdir(parents=True, exist_ok=True)
        env = {'XDG_STATE_HOME': str(self.state), 'FAKE_CHECK_FINDINGS': '1',
               'OUTPUT_GATE_CHECK_CMD': json.dumps([sys.executable, '-I', str(self.checker)])}
        with mock.patch.dict(os.environ, env):
            module.check('全部通ったよ', {'transcript_path': str(self.transcript), 'turn_id': 't1'}, session_dir, None)
        self.assertTrue(self.checker_calls()[0]['evidence'][0]['unavailable'])
        stored = json.loads(self.session_file(self.pair_name('全部通ったよ') + '.result').read_text(encoding='utf-8'))
        self.assertEqual(stored['turn'], 'u1')

    def test_unmet_points_are_told_apart_from_corrections(self):
        # 置き換えの無い回答は訂正版として伝えない。利用者に見せた未達の項目は別の文言で伝える。
        self.display('全部通ったよ', final=True, FAKE_CHECK_FINDINGS='1')
        context = self.hook('prompt', {'hook_event_name': 'UserPromptSubmit', 'prompt': '次'})['hookSpecificOutput'][
            'additionalContext']
        self.assertNotIn('訂正', context)
        self.assertIn('利用者に見せた未達の項目', context)
        self.assertIn('出力ゲート: 次の点は確かめられていません\n- 未確認', context)   # 検査処理の unmet_text
        self.assertFalse(hasattr(self.load_hook(), 'UNMET_SEPARATOR'))   # 未達の段落を自分で切り出さない

    def test_the_real_checker_falls_back_to_the_second_engine_and_records_both(self):
        # 本物の検査処理に偽の検査役をつなぐ。Codex の系統はすぐ失敗し、Claude の系統が未達を返す。
        (self.tmp / 'AGENTS.md').write_text('## 応答\n\n- 口語で話す。\n', encoding='utf-8')
        (self.tmp / 'codex.py').write_text('import sys\nsys.stdin.read()\nsys.exit(1)\n', encoding='utf-8')
        reply = {'replacements': [], 'findings': [{'kind': 'unverified_claim', 'source': 'draft',
                                                   'excerpt': 'テストは全部通ったよ', 'evidence': [{'id': None, 'state': 'absent'}]}]}
        (self.tmp / 'claude.py').write_text(
            'import json, sys, runpy\n'
            f'helper = runpy.run_path({str(REPO / "tests/output-gate-check.py")!r})\n'
            f'reply = helper["protocol_reply"](json.load(sys.stdin), {reply!r}, {{}}, [])\n'
            'print(json.dumps({"is_error": False, "stop_reason": "end_turn", "structured_output": reply}))\n',
            encoding='utf-8')
        (self.tmp / 'gitleaks.py').write_text(
            'import sys\nargs = sys.argv[1:]\nopen(args[args.index("--report-path") + 1], "w").write("[]")\n',
            encoding='utf-8')
        real = REPO / 'agent-shared/bin/output-gate-check.py'
        (self.tmp / 'opposite-first.json').write_text(json.dumps({'first': 'opposite'}), encoding='utf-8')
        out = self.display('テストは全部通ったよ', final=True,
                           OUTPUT_GATE_CHECK_CMD=json.dumps([sys.executable, '-I', str(real)]),
                           OUTPUT_GATE_CODEX_CMD=json.dumps([sys.executable, '-I', str(self.tmp / 'codex.py')]),
                           OUTPUT_GATE_CLAUDE_CMD=json.dumps([sys.executable, '-I', str(self.tmp / 'claude.py')]),
                           OUTPUT_GATE_GITLEAKS=json.dumps([sys.executable, '-I', str(self.tmp / 'gitleaks.py')]),
                           OUTPUT_GATE_RULES=str(self.tmp / 'AGENTS.md'),
                           OUTPUT_GATE_SETTINGS=str(self.tmp / 'opposite-first.json'))
        self.assertIn('出力ゲート: 次の点は確かめられていません', self.shown(out))
        unmet = self.session_file('unmet.txt').read_text(encoding='utf-8').strip()   # 検査処理の unmet_text
        self.assertTrue(unmet.startswith('出力ゲート: 次の点は確かめられていません') and self.shown(out).endswith(unmet))
        stored = json.loads(self.session_file(self.pair_name('テストは全部通ったよ') + '.result').read_text(encoding='utf-8'))
        self.assertEqual(stored['engine']['family'], 'claude')
        self.assertEqual([f['family'] for f in stored['engine_failures']], ['codex'])
        self.assertEqual(stored['dropped'], [])
        record = json.loads(self.session_file('check.log').read_text(encoding='utf-8').splitlines()[-1])
        self.assertEqual((record['engine']['family'], [f['family'] for f in record['engine_failures']]),
                         ('claude', ['codex']))
        self.assertTrue(self.stop('テストは全部通ったよ')['reason'].startswith('出力ゲートの検査結果です'))


if __name__ == '__main__':
    unittest.main()
