#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / 'agent-shared/bin/output_gate_codex_native.py'
spec = importlib.util.spec_from_file_location('native', MODULE)
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


def event(item, stamp='2026-11-09T00:00:01Z', turn='turn-one', phase='item_completed'):
    return {'timestamp': stamp, 'type': 'event_msg', 'payload': {
        'type': phase, 'thread_id': 'root', 'turn_id': turn, 'item': item}}


def command(status='completed', code=0, output='ok\n', ident='cmd'):
    return {'type': 'CommandExecution', 'id': ident, 'command': ['bash', '-lc', 'check'],
            'cwd': 'file:///work', 'status': status, 'exit_code': code,
            'aggregated_output': output, 'process_id': '41', 'duration': {'secs': 0, 'nanos': 4}}


class NativeReader(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.sessions = self.home / 'sessions/2026/11/09'
        self.sessions.mkdir(parents=True)

    def log(self, sid, rows):
        path = self.sessions / ('rollout-' + sid + '.jsonl')
        path.write_text(''.join(json.dumps(r) + '\n' for r in [
            {'type': 'session_meta', 'payload': {'id': sid, 'session_id': 'root'}}, *rows]))
        return path

    def append(self, path, rows):
        with path.open('a') as stream:
            for row in rows:
                stream.write(json.dumps(row) + '\n')

    def collect(self, cursor=None):
        return native.collect_session('root', self.home, cursor)

    def test_status_changes_keep_identity_and_terminal_result(self):
        path = self.log('root', [event(command('in_progress', None, 'starting'))])
        rows, cursor = self.collect()
        self.assertIsNone(rows[0]['metadata']['failed'])
        self.assertEqual(rows[0]['metadata']['status'], 'in_progress')
        first = rows[0]['native_id']
        self.append(path, [event(command(), '2026-11-09T00:00:02Z'),
                           event(command('failed', 7, 'broken', 'bad'), '2026-11-09T00:00:03Z')])
        rows, cursor = self.collect(cursor)
        self.assertEqual(rows[0]['native_id'], first)
        self.assertEqual(rows[0]['fields']['output'], 'ok\n')
        self.assertFalse(rows[0]['metadata']['failed'])
        self.assertEqual(rows[0]['metadata']['exit_code'], 0)
        self.assertTrue(rows[1]['metadata']['failed'])
        self.assertEqual(json.loads(rows[0]['fields']['call'])['command'], ['bash', '-lc', 'check'])
        self.assertEqual(self.collect(cursor)[0], [])
        self.log('root', [event(command('completed', 2, 'failure despite completed'))])
        self.assertTrue(self.collect()[0][0]['metadata']['failed'])
        self.log('root', [event(command('completed', None))])
        self.assertIsNone(self.collect()[0][0]['metadata']['failed'])
        self.log('root', [event(command('in_progress', None)), event(command())])
        self.assertEqual(len(self.collect()[0]), 1)

    def test_partial_line_and_reset_and_missing_observed_path_are_gaps(self):
        path = self.log('root', [])
        raw = json.dumps(event(command())).encode()
        with path.open('ab') as stream:
            stream.write(raw[:30])
        rows, cursor = self.collect()
        self.assertEqual(rows, [])
        with path.open('ab') as stream:
            stream.write(raw[30:] + b'\n')
        rows, cursor = self.collect(cursor)
        self.assertEqual(rows[0]['metadata']['exit_code'], 0)
        self.log('root', [event(command(output='replacement' * 100))])
        reset_rows, _ = self.collect(cursor)
        self.assertTrue(any(r['kind'] == 'gap' for r in reset_rows))
        self.assertTrue(any(r['fields'].get('output') == 'replacement' * 100 for r in reset_rows))
        self.log('root', [])
        rows, cursor = self.collect(cursor)
        self.assertEqual(rows[0]['kind'], 'gap')
        path.unlink()
        self.assertEqual(self.collect(cursor)[0][0]['kind'], 'gap')
        self.assertEqual(self.collect()[0], [])

    def test_mismatch_and_reasoning_are_never_imported(self):
        path = self.log('root', [event(command())])
        path.write_text(json.dumps({'type': 'session_meta', 'payload': {'id': 'other'}}) + '\n' + json.dumps(event(command())) + '\n')
        rows, _ = self.collect()
        self.assertEqual([r['kind'] for r in rows], ['gap'])
        self.log('root', [event({'type': 'Reasoning', 'id': 'secret', 'content': 'REASONING_CANARY'}),
                          {'type': 'response_item', 'payload': {'type': 'reasoning', 'raw_content': 'REASONING_CANARY'}},
                          event({'type': 'UserMessage', 'id': 'u', 'content': [{'type': 'text', 'text': 'COMMAND SUCCESS CANARY'}]}),
                          event(command())])
        rows, cursor = self.collect()
        self.assertNotIn('CANARY', json.dumps([rows, cursor]))

    def test_mcp_and_file_change_preserve_machine_results(self):
        result = {'content': [{'type': 'text', 'text': 'rejected'}], 'isError': True}
        changes = {'/work/file': {'type': 'add', 'content': 'actual content'}}
        self.log('root', [event({'type': 'McpToolCall', 'id': 'm', 'server': 'repo', 'tool': 'read',
                                'arguments': {'path': 'a'}, 'status': 'completed', 'result': result}),
                          event({'type': 'FileChange', 'id': 'f', 'status': 'completed', 'changes': changes,
                                 'stdout': 'updated', 'stderr': ''})])
        rows, _ = self.collect()
        self.assertEqual(json.loads(rows[0]['fields']['output']), result)
        self.assertTrue(rows[0]['metadata']['failed'])
        self.assertEqual(json.loads(rows[1]['fields']['output'])['changes'], changes)

    def test_linked_child_has_model_task_report_and_primary_operations(self):
        activity = {'type': 'SubAgentActivity', 'id': 'delegate', 'kind': 'started', 'model': 'gpt-6-astra',
                    'reasoning_effort': 'high', 'agent_thread_id': 'child', 'agent_path': '/root/review'}
        self.log('root', [event(activity)])
        child = self.log('child', [event({'type': 'UserMessage', 'id': 'task', 'content': [{'type': 'text', 'text': 'Review the actual patch.'}]}),
                                  event(command(output='accepted\n'), '2026-11-09T00:00:02Z'),
                                  event({'type': 'AgentMessage', 'id': 'final', 'phase': 'final_answer', 'content': [{'type': 'Text', 'text': 'No blocking findings.'}]}, '2026-11-09T00:00:03Z')])
        self.append(self.sessions / 'rollout-root.jsonl', [
            {'timestamp': '2026-11-09T00:00:04Z', 'type': 'response_item',
             'payload': {'type': 'agent_message', 'id': 'callback', 'author': '/root/review',
                         'recipient': '/root', 'content': [{'type': 'input_text', 'text': 'ACTUAL_CALLBACK_REPORT'}]}}])
        unrelated = self.log('unrelated', [event(command(output='UNRELATED_CANARY'))])
        rows, cursor = self.collect()
        rendered = json.dumps(rows)
        for literal in ('gpt-6-astra', 'Review the actual patch.', 'No blocking findings.', 'accepted\\n', 'ACTUAL_CALLBACK_REPORT'):
            self.assertIn(literal, rendered)
        self.assertNotIn('UNRELATED_CANARY', rendered)
        childcmd = next(r for r in rows if r['metadata'].get('producer_session_id') == 'child' and r['metadata'].get('native_event_type') == 'CommandExecution')
        self.assertEqual(childcmd['metadata']['parent_session_id'], 'root')
        self.assertEqual(childcmd['metadata']['model'], 'gpt-6-astra')
        self.assertEqual(self.collect(cursor)[0], [])
        self.append(child, [event({'type': 'SubAgentActivity', 'id': 'cycle', 'kind': 'started',
                                   'agent_thread_id': 'root', 'agent_path': '/root'})])
        cycle_rows, cycle_cursor = self.collect(cursor)
        self.assertTrue(cycle_rows)
        self.assertEqual(self.collect(cycle_cursor)[0], [])
        self.assertNotIn('Review the actual patch.', json.dumps(cursor))
        self.append(child, [event({'type': 'AgentMessage', 'id': 'second-final', 'phase': 'final_answer', 'content': [{'type': 'Text', 'text': 'Follow-up complete.'}]}, '2026-11-09T00:00:04Z')])
        updated, _ = self.collect(cursor)
        self.assertIn('Follow-up complete.', json.dumps(updated))
        self.assertEqual([r['metadata']['timestamp'] for r in rows], sorted(r['metadata']['timestamp'] for r in rows))

    def test_typed_spawn_role_and_incoming_task_ids_do_not_duplicate_scope_text(self):
        spawn = {'timestamp': '2026-11-09T00:00:00Z', 'type': 'response_item', 'payload': {
            'type': 'function_call', 'namespace': 'collaboration', 'name': 'spawn_agent',
            'call_id': 'delegate', 'arguments': json.dumps({'agent_type': 'correctness-reviewer',
                'task_name': 'review', 'model': 'gpt-6-astra', 'reasoning_effort': 'high',
                'fork_turns': 'none', 'message': {'encrypted_content': 'CIPHERTEXT_CANARY'}})}}
        activity = {'type': 'SubAgentActivity', 'id': 'delegate', 'kind': 'started',
                    'agent_thread_id': 'child', 'agent_path': '/root/review'}
        self.log('root', [spawn, event(activity)])
        def incoming(ident, text, turn, encrypted=False):
            content = [{'type': 'input_text', 'text': text}]
            if encrypted:
                content.append({'type': 'encrypted_content', 'encrypted_content': 'CIPHERTEXT_CANARY'})
            return {'timestamp': '2026-11-09T00:00:01Z', 'type': 'response_item', 'payload': {
                'type': 'agent_message', 'id': ident, 'author': '/root', 'recipient': '/root/review',
                'content': content, 'internal_chat_message_metadata_passthrough': {'turn_id': turn}}}
        self.log('child', [incoming('task-one', 'Review first target.', 'turn-one'),
                          event(command(ident='first'), turn='turn-one'),
                          incoming('opaque', 'Message Type: NEW_TASK\nPayload:\n', 'opaque-turn', True),
                          event(command(ident='opaque-command'), turn='opaque-turn'),
                          incoming('task-two', 'Review second target.', 'turn-two'),
                          event(command(ident='second'), turn='turn-two'),
                          event({'type': 'AgentMessage', 'id': 'report', 'phase': 'final_answer',
                                 'content': [{'type': 'Text', 'text': 'Checked second target.'}]}, turn='turn-two'),
                          incoming('task-three', 'Review third target.', 'turn-three')])
        rows, cursor = self.collect()
        commands = {r['metadata']['native_event_id']: r for r in rows if r['metadata']['native_event_type'] == 'CommandExecution'}
        for row in commands.values():
            self.assertEqual(row['metadata']['agent_type'], 'correctness-reviewer')
            self.assertEqual(row['metadata']['model'], 'gpt-6-astra')
            self.assertNotIn('Review first target.', json.dumps(row))
            self.assertNotIn('Review second target.', json.dumps(row))
        self.assertEqual(commands['first']['metadata']['task_scope_ids'], ['codex-native:child:task-one'])
        self.assertEqual(commands['second']['metadata']['task_scope_ids'], ['codex-native:child:task-two'])
        self.assertFalse(commands['opaque-command']['producer_truncated'])
        self.assertTrue(commands['opaque-command']['available'])
        self.assertNotIn('task_scope_available', commands['opaque-command']['metadata'])
        opaque = next(r for r in rows if r['native_id'] == 'codex-native:child:opaque')
        self.assertTrue(opaque['producer_truncated'])
        task = next(r for r in rows if r['native_id'] == 'codex-native:child:task-two')
        self.assertEqual(task['kind'], 'assistant')
        self.assertEqual(task['metadata']['context_kind'], 'delegated_task')
        self.assertFalse(task['metadata']['displayed'])
        self.assertEqual(task['fields']['text'], 'Review second target.')
        report = next(r for r in rows if r['native_id'] == 'codex-native:child:report')
        self.assertEqual(report['metadata']['task_scope_ids'], ['codex-native:child:task-two'])
        self.assertNotIn('CIPHERTEXT_CANARY', json.dumps([rows, cursor]))
        self.assertEqual(self.collect(cursor)[0], [])

    def test_later_child_report_cannot_rewrite_historical_activity(self):
        activity = {'type': 'SubAgentActivity', 'id': 'activity-one', 'kind': 'started',
                    'model': 'gpt-6-astra', 'agent_thread_id': 'child', 'agent_path': '/root/review'}
        self.log('root', [event(activity)])
        child = self.log('child', [])
        first, cursor = self.collect()
        original = next(r for r in first if r['native_id'] == 'codex-native:root:activity-one')
        self.assertEqual(json.loads(original['fields']['output'])['kind'], 'started')
        self.append(child, [event({'type': 'AgentMessage', 'id': 'report-two', 'phase': 'final_answer',
                                  'content': [{'type': 'Text', 'text': 'SECOND_REPORT_BODY'}]}, '2026-11-09T00:00:05Z')])
        delta, _ = self.collect(cursor)
        self.assertFalse(any(r['native_id'] == original['native_id'] for r in delta))
        report = next(r for r in delta if r['native_id'] == 'codex-native:child:report-two')
        self.assertEqual(report['fields']['output'], 'SECOND_REPORT_BODY')
        bootstrap, _ = self.collect()
        historical = next(r for r in bootstrap if r['native_id'] == original['native_id'])
        self.assertEqual(historical, original)
        self.assertNotIn('SECOND_REPORT_BODY', json.dumps(historical))

    def test_late_read_failure_preserves_cursor_for_retry(self):
        path = self.log('root', [])
        self.log('child', [])
        _, before = self.collect()
        activity = {'type': 'SubAgentActivity', 'id': 'late-activity', 'kind': 'started',
                    'agent_thread_id': 'child', 'agent_path': '/root/review'}
        self.append(path, [event(command()), event(activity)])
        original_record_at = native._record_at
        def fail_late(record_path, offset):
            if record_path == path and offset > 0:
                raise OSError('injected late activity read failure')
            return original_record_at(record_path, offset)
        with patch.object(native, '_record_at', side_effect=fail_late):
            partial, failed_cursor = self.collect(before)
        self.assertTrue(any(row['kind'] == 'gap' for row in partial))
        self.assertFalse(any(row['native_id'] == 'codex-native:root:late-activity' for row in partial))
        self.assertEqual(failed_cursor['sessions']['root'], before['sessions']['root'])
        recovered, after = self.collect(failed_cursor)
        self.assertTrue(any(row['native_id'] == 'codex-native:root:late-activity' for row in recovered))
        self.assertGreater(after['sessions']['root']['offset'], before['sessions']['root']['offset'])

    def test_interaction_cannot_steal_sibling_agent_ownership(self):
        self.log('root', [event({'type': 'SubAgentActivity', 'id': 'spawn-a', 'kind': 'started',
                                'agent_thread_id': 'a', 'agent_path': '/root/a', 'model': 'review-a'}),
                          event({'type': 'SubAgentActivity', 'id': 'spawn-b', 'kind': 'started',
                                 'agent_thread_id': 'b', 'agent_path': '/root/b', 'model': 'review-b'})])
        self.log('a', [event({'type': 'SubAgentActivity', 'id': 'message-b', 'kind': 'interacted',
                             'agent_thread_id': 'b', 'agent_path': '/root/b', 'model': None})])
        self.log('b', [event(command(ident='cmd-b'))])
        rows, cursor = self.collect()
        executed = next(row for row in rows if row['native_id'] == 'codex-native:b:cmd-b')
        self.assertEqual(executed['metadata']['parent_session_id'], 'root')
        self.assertEqual(executed['metadata']['parent_event_id'], 'spawn-b')
        self.assertEqual(executed['metadata']['model'], 'review-b')
        interaction = next(row for row in rows if row['native_id'] == 'codex-native:a:message-b')
        self.assertEqual(json.loads(interaction['fields']['output'])['kind'], 'interacted')
        self.assertNotIn('parent_session_id', interaction['metadata'])
        self.assertEqual(self.collect(cursor)[0], [])


if __name__ == '__main__':
    unittest.main()
