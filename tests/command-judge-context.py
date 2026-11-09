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

    def test_unrecorded_revocation_before_latest_prompt_is_retained(self):
        self.transcript.write_text('\n'.join(json.dumps(row) for row in [
            self.codex('user', 'permit'), self.codex('assistant', 'origin main?'),
            self.codex('user', 'revoke'), self.codex('user', 'y')]))
        self.record('y', [{'at': 1, 'text': 'permit', 'assistant_context': ''}])
        result = subprocess.run([sys.executable, str(HELPER), '--context', '--since',
            str(self.folder / 'state/prompts/s1')], input=json.dumps({'transcript_path': str(self.transcript)}),
            text=True, capture_output=True)
        self.assertIn('revoke', result.stdout)
        self.assertIn('origin main?', result.stdout)
        self.assertNotIn('permit', result.stdout)

    def test_context_fallback_contains_tool_arguments_and_results(self):
        self.transcript.write_text(json.dumps({'type': 'response_item', 'payload': {
            'type': 'function_call', 'name': 'exec_command', 'arguments': '{"cmd":"destination=remote"}'}}) + '\n' +
            json.dumps({'type': 'response_item', 'payload': {'type': 'function_call_output', 'output': 'duration=18s'}}))
        result = subprocess.run([sys.executable, str(HELPER), '--context'],
            input=json.dumps({'transcript_path': str(self.transcript)}), text=True, capture_output=True)
        self.assertIn('destination=remote', result.stdout)
        self.assertIn('duration=18s', result.stdout)

    def test_large_history_supplies_requested_source_without_resending_tool_bodies(self):
        source = self.folder / 'task.py'
        source.write_text('print("REQUESTED_SOURCE_MARKER")\n')
        self.transcript.write_text(json.dumps({'type': 'response_item', 'payload': {
            'type': 'function_call_output', 'output': 'public unrelated data ' * 70000 + 'UNRELATED_HISTORY_TAIL'}}) + '\n')
        event = {'cwd': str(self.folder), 'transcript_path': str(self.transcript),
                 'context_request': {'files': ['task.py']}}
        result = subprocess.run([sys.executable, str(HELPER), '--context'],
            input=json.dumps(event), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        context = json.loads(result.stdout)
        self.assertLess(len(result.stdout), 100_000)
        self.assertNotIn('UNRELATED_HISTORY_TAIL', result.stdout)
        self.assertEqual(context['files'][0]['content'], source.read_text())
        self.assertIsNone(context['tool_record_count'])
        self.assertTrue(context['tool_index_available'])
        self.assertEqual(context['current_transcript'], [])

    def test_indexed_original_can_be_retrieved_by_reference(self):
        self.transcript.write_text(json.dumps({'type': 'response_item', 'payload': {
            'type': 'function_call_output', 'output': 'EXACT_RETRIEVED_EVIDENCE'}}) + '\n')
        event = {'cwd': str(self.folder), 'transcript_path': str(self.transcript)}
        def context():
            result = subprocess.run([sys.executable, str(HELPER), '--context'],
                input=json.dumps(event), text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)
        index = context()['tool_index']
        event['context_request'] = {'records': [index[0]['ref']]}
        self.assertEqual(context()['tool_records'][0]['content']['output'], 'EXACT_RETRIEVED_EVIDENCE')

    @unittest.skipUnless(hasattr(os, 'mkfifo'), 'requires POSIX FIFO')
    def test_nonregular_source_is_unavailable_without_waiting_for_a_writer(self):
        source = self.folder / 'source.fifo'
        os.mkfifo(source)
        result = subprocess.run([sys.executable, str(HELPER), '--context'],
            input=json.dumps({'cwd': str(self.folder), 'context_request': {'files': ['source.fifo']}}),
            text=True, capture_output=True, timeout=2)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('not a regular source file', json.loads(result.stdout)['files'][0]['unavailable'])

    def test_source_is_masked_before_a_credential_crosses_excerpt_boundaries(self):
        import secrets
        import string
        token = 'ghp_' + ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(36))
        prefix = 'x' * (262140 - len('API_KEY = "')) + 'API_KEY = "'
        source = self.folder / 'source.py'
        source.write_text(prefix + token + '"\n')
        event = {'cwd': str(self.folder), 'context_request': {'files': [
            {'path': 'source.py', 'start': 0, 'end': 262144},
            {'path': 'source.py', 'start': 262144, 'end': 262300}]}}
        result = subprocess.run([sys.executable, str(HELPER), '--context'],
            input=json.dumps(event), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        joined = ''.join(item['content'] for item in json.loads(result.stdout)['files'])
        self.assertTrue(token not in joined, 'source ranges must not reconstruct a credential')
        self.assertIn('[REDACTED]', joined)

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


class StagedJudgeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.bin = self.folder / 'bin'
        self.bin.mkdir()
        self.log = self.folder / 'requests.jsonl'
        self.transcript = self.folder / 'transcript.jsonl'
        self.transcript.write_text(json.dumps({'type': 'response_item', 'payload': {
            'type': 'message', 'role': 'assistant', 'content': [{'type': 'output_text', 'text': 'CONVERSATION_MARKER'}]}}) + '\n')
        stub = self.bin / 'codex'
        stub.write_text('#!' + sys.executable + '\n' + r"""
import json, os, re, sys
text = sys.stdin.read()
if text == 'Reply with exactly: OK':
    print('OK'); sys.exit()
stage = re.search(r'<<<STAGE [^>]+>>>\n(.*?)\n', text)
stage = stage[1] if stage else 'legacy'
with open(os.environ['JUDGE_LOG'], 'a') as f:
    f.write(json.dumps({'stage': stage, 'text': text, 'argv': sys.argv[1:]}) + '\n')
def section(name):
    m = re.search(r'<<<' + name + r' ([^>]+)>>>\n(.*?)\n<<<END ' + name + r' \1>>>', text, re.S)
    return json.loads(m[2]) if m else None
if stage == 'state':
    update = section('UPDATE')
    facts = update['previous'] + [{'sources': [row['ref']], 'purpose': 'task',
        'target': 'origin main', 'effect': 'push', 'scope': row['input'],
        'status': 'denied' if 'revoke' in row['input'] else 'allowed'} for row in update['new_inputs']]
    if os.environ.get('BAD_STATE') == 'sources': facts[-1]['sources'] = ['invented']
    if os.environ.get('BAD_STATE') == 'schema': facts[-1]['scope'] = 42
    print(json.dumps({'facts': facts}))
elif stage.startswith('authorize'):
    if os.environ.get('HOLD_AUTH'):
        import time
        from pathlib import Path
        Path(os.environ['HOLD_AUTH']).write_text('ready')
        deadline = time.monotonic() + 20
        while not Path(os.environ['RELEASE_AUTH']).exists():
            if time.monotonic() > deadline: sys.exit(9)
            time.sleep(0.01)
    facts = section('PERMISSIONS')['facts']
    if stage == 'authorize' and os.environ.get('CHANGE_AT_AUTH'):
        from pathlib import Path
        Path(os.environ['REQUEST_FILE']).write_text('print("changed during authorization")\n')
    revoked = os.environ.get('HONOR_UNRECORDED') and 'UNRECORDED_REVOKE' in json.dumps(section('CONTEXT'))
    if os.environ.get('RACE_JOURNAL'):
        with open(os.environ['RACE_JOURNAL'], 'a') as f: f.write(json.dumps({'at': 2, 'text': 'revoke'}) + '\n')
    print(json.dumps({'user_requested': bool(facts) and facts[-1]['status'] == 'allowed' and not bool(revoked),
        'needs_context': os.environ.get('AUTH_CONTEXT') == '1' and stage != 'authorize-context',
        'context_request': {'files': [os.environ['REQUEST_FILE']], 'conversation': False} if os.environ.get('REQUEST_FILE') else {},
        'reason': 'authorization'}))
else:
    external = os.environ.get('EXTERNAL') == '1'
    needs = os.environ.get('STILL_UNKNOWN') == '1' or ((os.environ.get('NEEDS_CONTEXT') == '1' or bool(os.environ.get('REQUEST_FILE'))) and stage != 'effect-context')
    request = {'files': [os.environ['REQUEST_FILE']], 'conversation': False} if os.environ.get('REQUEST_FILE') else {}
    if os.environ.get('REPAIR_RANGE'):
        if stage == 'effect':
            request['files'] = [{'path': os.environ['REQUEST_FILE'], 'start': 9999, 'end': 10000}]
        elif not any('content' in item for item in section('CONTEXT').get('files', [])):
            needs = True
            request['files'] = [{'path': os.environ['REQUEST_FILE'], 'start': 0, 'end': 100}]
    if stage == 'effect-context' and os.environ.get('CHANGE_SOURCE'):
        from pathlib import Path
        Path(os.environ['REQUEST_FILE']).write_text('print("changed")\n')
    print(json.dumps({'danger': False, 'external': external, 'body_from_file': False,
        'short_cutoff': False, 'context_free': 'true' if os.environ.get('BAD_EFFECT') else not needs, 'needs_context': needs,
        'context_request': request,
        'user_requested': False, 'reason': ''}))
""")
        stub.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        COMMAND_JUDGE_STATE_DIR=str(self.folder / 'state'), JUDGE_LOG=str(self.log))
        self.env.pop('AGENT_DELEGATED_SESSION', None)
        self.env.pop('COMMAND_JUDGE_ACTIVE', None)

    def run_hook(self, event, record=False, **env):
        result = subprocess.run(['bash', str(HOOK), '--cli', 'codex'] + (['--record-prompt'] if record else []),
            input=json.dumps(dict(session_id='stage', **event)), text=True, capture_output=True,
            env=dict(self.env, **env))
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout) if result.stdout else {}

    def record(self, text):
        self.run_hook({'prompt': text, 'transcript_path': str(self.transcript)}, record=True)

    def judge(self, command='git status', **env):
        return self.run_hook({'tool_name': 'Bash', 'tool_input': {'command': command},
            'transcript_path': str(self.transcript)}, **env)

    def requests(self, stage=None):
        rows = [json.loads(line) for line in self.log.read_text().splitlines()]
        return [r for r in rows if stage is None or r['stage'] == stage]

    def test_ordinary_operation_never_sends_history_and_reuses_context_free_verdict(self):
        self.record('USER_HISTORY_MARKER' * 1000)
        self.judge()
        request = self.requests()[0]['text']
        self.assertNotIn('USER_HISTORY_MARKER', request)
        self.assertNotIn('CONVERSATION_MARKER', request)
        self.record('unrelated progress')
        self.judge()
        self.assertEqual(len(self.requests()), 1)

    def test_other_hook_state_cannot_validate_an_older_authorization(self):
        import time
        self.record('permit origin main')
        held, release = self.folder / 'held', self.folder / 'release'
        event = {'session_id': 'stage', 'tool_name': 'Bash',
                 'tool_input': {'command': 'git push origin main'},
                 'transcript_path': str(self.transcript)}
        process = subprocess.Popen(['bash', str(HOOK), '--cli', 'codex'],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            env=dict(self.env, EXTERNAL='1', HOLD_AUTH=str(held), RELEASE_AUTH=str(release)))
        try:
            process.stdin.write(json.dumps(event))
            process.stdin.close()
            deadline = time.monotonic() + 20
            while not held.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(held.exists(), 'the first hook must reach authorization')
            self.record('revoke origin main')
            newer = self.judge('git push origin main', EXTERNAL='1')
            self.assertEqual(newer['hookSpecificOutput']['permissionDecision'], 'deny')
            release.write_text('continue')
            process.wait(timeout=20)
            self.assertEqual(process.returncode, 0, process.stderr.read())
            output = process.stdout.read()
            self.assertTrue(output, 'the older hook must reject its stale verdict')
            self.assertEqual(json.loads(output)['hookSpecificOutput']['permissionDecision'], 'deny')
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
            process.stderr.close()

    def test_classifier_uses_dedicated_role_without_skill_catalog(self):
        self.judge()
        args = self.requests()[0]['argv']
        self.assertIn('skills.include_instructions=false', args)
        setting = next(arg for arg in args if arg.startswith('model_instructions_file='))
        path = Path(json.loads(setting.split('=', 1)[1]))
        self.assertTrue(path.is_file())
        self.assertLess(len(path.read_bytes()), 1024)

    def test_needs_context_fetches_originals_without_caching_contextual_verdict(self):
        self.record('TIMING_EVIDENCE_MARKER')
        self.judge('timeout 30 tests', NEEDS_CONTEXT='1')
        self.assertEqual([r['stage'] for r in self.requests()], ['effect', 'effect-context'])
        self.assertNotIn('TIMING_EVIDENCE_MARKER', self.requests()[0]['text'])
        self.assertIn('TIMING_EVIDENCE_MARKER', self.requests()[1]['text'])
        self.assertIn('CONVERSATION_MARKER', self.requests()[1]['text'])
        self.judge('timeout 30 tests', NEEDS_CONTEXT='1')
        self.assertEqual(len(self.requests()), 4)

    def test_requested_script_is_supplied_without_large_unrelated_history(self):
        script = self.folder / 'task.py'
        script.write_text('print("CALL_SITE_EVIDENCE")\n')
        self.transcript.write_text(json.dumps({'type': 'response_item', 'payload': {
            'type': 'function_call_output', 'output': 'x' * 2_100_000}}) + '\n')
        out = self.run_hook({'cwd': str(self.folder), 'tool_name': 'Bash',
            'tool_input': {'command': 'python3 task.py'}, 'transcript_path': str(self.transcript)}, REQUEST_FILE=str(script))
        self.assertEqual(out, {})
        self.assertEqual([r['stage'] for r in self.requests()], ['effect', 'effect-context'])
        request = self.requests('effect-context')[0]['text']
        self.assertIn('CALL_SITE_EVIDENCE', request)
        self.assertLess(len(request), 100_000)

    def test_source_changed_during_judgment_is_not_allowed(self):
        script = self.folder / 'task.py'
        script.write_text('print("before")\n')
        out = self.run_hook({'cwd': str(self.folder), 'tool_name': 'Bash',
            'tool_input': {'command': 'python3 task.py'}, 'transcript_path': str(self.transcript)},
            REQUEST_FILE=str(script), CHANGE_SOURCE='1')
        self.assertEqual(out['hookSpecificOutput']['permissionDecision'], 'deny')
        self.assertIn('ファイルの版が変わった', out['hookSpecificOutput']['permissionDecisionReason'])

    def test_corrected_range_does_not_keep_an_unavailable_source_as_a_version(self):
        script = self.folder / 'task.py'
        script.write_text('print(1)\n')
        out = self.run_hook({'cwd': str(self.folder), 'tool_name': 'Bash',
            'tool_input': {'command': 'python3 task.py'}, 'transcript_path': str(self.transcript)},
            REQUEST_FILE=str(script), REPAIR_RANGE='1')
        self.assertEqual(out, {})
        self.assertEqual([r['stage'] for r in self.requests()], ['effect', 'effect-context', 'effect-context'])

    @unittest.skipIf(os.name == 'nt', 'observes POSIX executable process ancestry')
    def test_initial_authorization_context_runs_under_the_shared_deadline_manager(self):
        trace = self.folder / 'python-trace.jsonl'
        wrapper = self.bin / 'python3'
        wrapper.write_text('#!' + sys.executable + '\n' +
            'import json,os,sys\n' +
            'with open(' + repr(str(trace)) + ',"a") as f: f.write(json.dumps({"pid":os.getpid(),"parent":os.getppid(),"args":sys.argv[1:]})+"\\n")\n' +
            'os.execv(' + repr(sys.executable) + ',[' + repr(sys.executable) + ',*sys.argv[1:]])\n')
        wrapper.chmod(0o755)
        self.record('permit origin main')
        self.assertEqual(self.judge('git push origin main', EXTERNAL='1'), {})
        rows = [json.loads(line) for line in trace.read_text().splitlines()]
        managers = {row['pid'] for row in rows if any(arg.endswith('/run-judge.py') for arg in row['args'])}
        children = [row for row in rows if '--since' in row['args'] and
                    any(arg.endswith('/command-judge-context.py') for arg in row['args']) and
                    not any(arg.endswith('/run-judge.py') for arg in row['args'])]
        self.assertTrue(children, 'the normal authorization path must read withdrawal context')
        self.assertTrue(all(row['parent'] in managers for row in children),
                        'the context reader must be a child of the shared deadline manager')
        since_managers = [row for row in rows if row['pid'] in managers and '--since' in row['args']]
        for row in since_managers:
            position = next(i for i, arg in enumerate(row['args']) if arg.endswith('/run-judge.py'))
            self.assertGreater(float(row['args'][position + 1]), 0)
            self.assertLessEqual(float(row['args'][position + 1]), 137)

    def test_authorization_retrieval_does_not_replace_effect_source_version(self):
        self.record('permit origin main')
        script = self.folder / 'task.py'
        script.write_text('print("effect source")\n')
        out = self.run_hook({'cwd': str(self.folder), 'tool_name': 'Bash',
            'tool_input': {'command': 'python3 task.py'}, 'transcript_path': str(self.transcript)},
            REQUEST_FILE=str(script), EXTERNAL='1', AUTH_CONTEXT='1', CHANGE_AT_AUTH='1')
        self.assertEqual(out['hookSpecificOutput']['permissionDecision'], 'deny')
        self.assertIn('ファイルの版が変わった', out['hookSpecificOutput']['permissionDecisionReason'])

    def test_files_only_authorization_retrieval_retains_unrecorded_revocation(self):
        self.record('permit origin main')
        with self.transcript.open('a') as transcript:
            transcript.write(json.dumps({'type': 'attachment', 'attachment': {'type': 'queued_command',
                'origin': {'kind': 'human'}, 'prompt': 'UNRECORDED_REVOKE'}}) + '\n')
        script = self.folder / 'task.py'
        script.write_text('print("source evidence")\n')
        out = self.run_hook({'cwd': str(self.folder), 'tool_name': 'Bash',
            'tool_input': {'command': 'python3 task.py'}, 'transcript_path': str(self.transcript)},
            REQUEST_FILE=str(script), EXTERNAL='1', AUTH_CONTEXT='1', HONOR_UNRECORDED='1')
        self.assertEqual(out['hookSpecificOutput']['permissionDecision'], 'deny')
        followup = self.requests('authorize-context')[0]['text']
        self.assertIn('UNRECORDED_REVOKE', followup)
        self.assertEqual(followup.count('\n<<<CONTEXT '), 1)

    def test_authorization_updates_only_new_inputs_and_revocation_is_not_cached(self):
        self.record('permit origin main')
        self.assertEqual(self.judge('git push origin main', EXTERNAL='1'), {})
        self.assertEqual(self.judge('git push origin main', EXTERNAL='1'), {})
        self.assertEqual(len(self.requests('state')), 1)
        self.assertEqual(len(self.requests('authorize')), 2)
        self.record('revoke origin main')
        out = self.judge('git push origin main', EXTERNAL='1')
        self.assertEqual(out['hookSpecificOutput']['permissionDecision'], 'deny')
        updates = self.requests('state')
        self.assertEqual(len(updates), 2)
        import re
        data = re.search(r'\n<<<UPDATE ([^>]+)>>>\n(.*?)\n<<<END UPDATE \1>>>', updates[-1]['text'], re.S)[2]
        self.assertEqual([r['input'] for r in json.loads(data)['new_inputs']], ['revoke origin main'])

    def test_forged_source_or_wrong_schema_cannot_authorize(self):
        self.record('permit origin main')
        for mode in ('sources', 'schema'):
            with self.subTest(mode=mode):
                out = self.judge('git push origin main', EXTERNAL='1', BAD_STATE=mode)
                self.assertEqual(out['hookSpecificOutput']['permissionDecision'], 'deny')

    def test_unknown_effect_and_malformed_boolean_are_not_treated_as_safe(self):
        for env in ({'STILL_UNKNOWN': '1'}, {'BAD_EFFECT': '1'}):
            with self.subTest(env=env):
                out = self.judge('invoke unresolved_session', **env)
                self.assertEqual(out['hookSpecificOutput']['permissionDecision'], 'deny')

    def test_authorization_can_retrieve_originals_without_duplicate_context_sections(self):
        self.record('permit origin main')
        self.assertEqual(self.judge('git push origin main', EXTERNAL='1', AUTH_CONTEXT='1'), {})
        request = self.requests('authorize-context')[0]['text']
        self.assertIn('permit origin main', request)
        self.assertEqual(request.count('\n<<<CONTEXT '), 1)
        self.assertEqual(request.count('\n<<<USER '), 1)

    def test_corrupt_cached_schema_rebuilds_from_sources(self):
        self.record('permit origin main')
        self.judge('git push origin main', EXTERNAL='1')
        cache = self.folder / 'state/permissions/codex-stage'
        state = json.loads(cache.read_text())
        state['facts'][0]['scope'] = 42
        cache.write_text(json.dumps(state))
        self.assertEqual(self.judge('git push origin main', EXTERNAL='1'), {})
        self.assertEqual(len(self.requests('state')), 2)
        self.assertIsInstance(json.loads(cache.read_text())['facts'][0]['scope'], str)

    def test_new_input_during_authorization_invalidates_the_allow(self):
        self.record('permit origin main')
        out = self.judge('git push origin main', EXTERNAL='1',
            RACE_JOURNAL=str(self.folder / 'state/prompts/stage'))
        self.assertEqual(out['hookSpecificOutput']['permissionDecision'], 'deny')
        self.assertIn('判定中に本人入力が変わった', out['hookSpecificOutput']['permissionDecisionReason'])

    def test_replaced_journal_rebuilds_state_and_delegation_cannot_reuse_it(self):
        self.record('permit origin main')
        self.judge('git push origin main', EXTERNAL='1')
        journal = self.folder / 'state/prompts/stage'
        journal.write_text(json.dumps({'at': 1, 'text': 'revoke origin main'}) + '\n')
        out = self.judge('git push origin main', EXTERNAL='1')
        self.assertEqual(out['hookSpecificOutput']['permissionDecision'], 'deny')
        self.record('permit origin main')
        out = self.judge('git push origin main', EXTERNAL='1', AGENT_DELEGATED_SESSION='1')
        self.assertEqual(out['hookSpecificOutput']['permissionDecision'], 'deny')


if __name__ == '__main__':
    unittest.main()
