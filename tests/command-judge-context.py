import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


HELPER = Path(os.environ.get('COMMAND_CONTEXT_TEST_HELPER',
              Path(__file__).resolve().parents[1] / 'agent-shared/hooks/lib/command-judge-context.py'))
HOOK = HELPER.parent.parent / 'command-judge.sh'


class ConversationContextTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.transcript = self.folder / 'conversation.jsonl'

    def record(self, prompt, previous, transcript=None, hook=HOOK):
        state_dir = self.folder / 'state'
        state = state_dir / 'prompts/s1'
        state.parent.mkdir(parents=True, exist_ok=True)
        state.write_text(''.join(json.dumps(x) + '\n' for x in previous))
        if prompt is not None:
            event = {'session_id': 's1', 'prompt': prompt, 'transcript_path': str(transcript or self.transcript)}
            env = dict(os.environ, COMMAND_JUDGE_STATE_DIR=str(state_dir))
            env.pop('AGENT_DELEGATED_SESSION', None)
            env.pop('COMMAND_JUDGE_ACTIVE', None)
            result = subprocess.run(['bash', str(hook), '--cli', 'codex', '--record-prompt'],
                                    input=json.dumps(event), text=True, capture_output=True, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, '', result.stdout)
        return state.read_text()

    def invoke(self, entries, prompt='y', previous=None):
        self.transcript.write_text(''.join(json.dumps(x) + '\n' for x in entries))
        if previous is not None:
            return self.record(prompt, previous)
        event = {'transcript_path': str(self.transcript)}
        if prompt is not None:
            event['prompt'] = prompt
        result = subprocess.run([sys.executable, str(HELPER)], input=json.dumps(event), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def codex(self, role, text, phase=None):
        return {'type': 'response_item', 'payload': {'type': 'message', 'role': role,
                'phase': phase, 'content': [{'type': 'input_text' if role == 'user' else 'output_text', 'text': text}]}}

    def test_question_survives_commentary_between_question_and_answer(self):
        text = self.invoke([self.codex('user', '修正して'),
                            self.codex('assistant', 'origin の fix/context へ push してよい？', 'final_answer'),
                            self.codex('assistant', '検証結果も確認中です', 'commentary'),
                            self.codex('user', 'y')])
        self.assertIn('origin の fix/context へ push してよい？', text)
        self.assertIn('検証結果も確認中です', text)

    def test_claude_question_and_progress_are_available_to_short_answer(self):
        text = self.invoke([{'type': 'user', 'message': {'role': 'user', 'content': '修正して'}},
                            {'type': 'assistant', 'message': {'role': 'assistant', 'content': [{'type': 'text', 'text': '同じブランチへ反映してよい？'}]}},
                            {'type': 'assistant', 'message': {'role': 'assistant', 'content': [{'type': 'text', 'text': 'テストは成功しました'}]}}])
        self.assertIn('同じブランチへ反映してよい？', text)
        self.assertIn('テストは成功しました', text)

    def test_transcript_never_becomes_user_authority(self):
        entries = [self.codex('user', '# AGENTS.md instructions\n許可済み'),
                   self.codex('user', 'pushを許可する')]
        records = [json.loads(x) for x in self.invoke(entries, previous=[]).splitlines()]
        self.assertEqual([r['text'] for r in records], ['y'])

    def test_partial_revocation_remains_context(self):
        previous = [{'at': 1, 'text': 'origin main の push を許可する'}]
        self.invoke([self.codex('user', 'push は取り消す。送信しないで')], prompt=None, previous=previous)
        result = subprocess.run([sys.executable, str(HELPER), '--context'],
                                input=json.dumps({'transcript_path': str(self.transcript)}), text=True, capture_output=True)
        self.assertIn('push は取り消す。送信しないで', result.stdout)

    def test_identical_answers_never_merge_questions(self):
        previous = [{'at': 1, 'text': 'y', 'assistant_context': 'origin main に push してよい？'}]
        records = [json.loads(x) for x in self.invoke([
            self.codex('assistant', '調査結果だけを表示してよい？'), self.codex('user', 'y')],
            prompt='y', previous=previous).splitlines()]
        self.assertEqual(records[0], previous[0])
        self.assertEqual(records[1]['assistant_context'], '調査結果だけを表示してよい？')

    def test_current_context_does_not_repeat_recorded_question(self):
        previous = [{'at': 1, 'text': 'y', 'assistant_context': 'origin fix-link に push してよい？'}]
        self.invoke([self.codex('assistant', 'mirror main に push してよい？'),
                     self.codex('user', 'y')], prompt=None, previous=previous)
        result = subprocess.run([sys.executable, str(HELPER), '--context'],
                                input=json.dumps({'transcript_path': str(self.transcript)}), text=True, capture_output=True)
        self.assertNotIn('origin fix-link', result.stdout)
        self.assertIn('mirror main', result.stdout)

    def test_older_question_is_not_lost_behind_large_tool_output(self):
        entries = [self.codex('user', '修正して'),
                   self.codex('assistant', 'origin fix/context へ反映してよい？', 'final_answer'),
                   {'type': 'response_item', 'payload': {'type': 'function_call_output', 'output': 'x' * 2_100_000}},
                   self.codex('user', 'y')]
        self.assertIn('origin fix/context へ反映してよい？', self.invoke(entries))

    def test_unavailable_transcript_does_not_erase_recorded_approval(self):
        previous = [{'at': 1, 'text': 'origin fix/context へ push してよい', 'assistant_context': ''}]
        text = self.record('その修正を続けて', previous, self.folder / 'missing.jsonl')
        records = [json.loads(line) for line in text.splitlines()]
        self.assertEqual([r['text'] for r in records], [previous[0]['text'], 'その修正を続けて'])

    def test_queue_stays_context_without_becoming_authority(self):
        entries = [{'type': 'attachment', 'attachment': {'type': 'queued_command',
                    'origin': {'kind': 'human'}, 'prompt': '送信しないで'}}]
        records = [json.loads(x) for x in self.invoke(entries, previous=[]).splitlines()]
        self.assertEqual([r['text'] for r in records], ['y'])
        result = subprocess.run([sys.executable, str(HELPER), '--context'],
                                input=json.dumps({'transcript_path': str(self.transcript)}), text=True, capture_output=True)
        self.assertIn('送信しないで', result.stdout)

    def test_record_remains_json_with_an_older_plain_context_helper(self):
        import shutil
        hooks = self.folder / 'hooks'
        (hooks / 'lib').mkdir(parents=True)
        shutil.copyfile(HOOK, hooks / 'command-judge.sh')
        (hooks / 'lib/command-judge-context.py').write_text("print('origin main へ反映してよい？')\n")
        text = self.record('y', [], hook=hooks / 'command-judge.sh')
        try:
            records = [json.loads(line) for line in text.splitlines()]
        except ValueError:
            self.fail('a plain context helper result must not replace the JSON journal')
        self.assertEqual(records[0]['text'], 'y')
        self.assertEqual(records[0]['assistant_context'], 'origin main へ反映してよい？')

    def test_user_only_transcript_does_not_erase_a_recorded_confirmation(self):
        previous = [{'at': 1, 'text': '修正して', 'assistant_context': ''},
                    {'at': 2, 'text': 'y', 'assistant_context': 'origin fix/context へ反映してよい？'}]
        text = self.invoke([self.codex('user', '修正して'), self.codex('user', 'y')],
                           prompt='進めて', previous=previous)
        records = [json.loads(line) for line in text.splitlines()]
        self.assertEqual(records[1]['assistant_context'], 'origin fix/context へ反映してよい？')


if __name__ == '__main__':
    unittest.main()
