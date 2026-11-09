import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location('fixtures', Path(__file__).with_name('output-gate-context.py'))
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)


class NativeIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.f = fixtures.ContextTests()
        self.f.setUp()
        self.addCleanup(self.f.doCleanups)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.log = self.home / 'sessions/rollout-native-session.jsonl'
        self.log.parent.mkdir()
        self.log.write_text(json.dumps(dict(type='session_meta', payload=dict(id='native-session'))) + '\n')
        p = patch.dict(os.environ, CODEX_HOME=str(self.home))
        p.start()
        self.addCleanup(p.stop)
        self.f.payload.update(session_id='native-session', source_collector='codex-relay', turn_id='turn',
                              evidence=[dict(id='wrapper', tool='exec', output='Opaque aggregate output.')])

    def command(self, output='NATIVE RESULT', code=0):
        item = dict(type='CommandExecution', id='command', command=['verify'], cwd='file:///work',
                    status='completed' if code == 0 else 'failed', exit_code=code, aggregated_output=output)
        row = dict(type='event_msg', timestamp='2026-11-09T00:00:00Z',
                   payload=dict(type='item_completed', turn_id='turn', item=item))
        with self.log.open('a') as stream:
            stream.write(json.dumps(row) + '\n')

    def test_native_result_is_masked_and_keeps_api_evidence(self):
        self.command('NATIVE SECRET')
        seen = []
        def mask(data, *args):
            wire = json.dumps(data)
            seen.append('NATIVE SECRET' in wire)
            return json.loads(wire.replace('NATIVE SECRET', '[REDACTED]'))
        with patch.object(fixtures.checker, 'mask_secrets', mask):
            ready = self.f.ready()
        sources = ready['transaction']['sources'].values()
        native = [s for s in sources if s.get('metadata', {}).get('native_event_type') == 'CommandExecution']
        self.assertEqual(len(native), 1)
        self.assertEqual(native[0]['fields']['output'], '[REDACTED]')
        self.assertEqual(native[0]['metadata']['exit_code'], 0)
        self.assertIs(native[0]['metadata']['failed'], False)
        self.assertTrue(any(s.get('native_id') == 'wrapper' for s in sources))
        self.assertTrue(any(seen))
        cursor = Path(self.f.tmp.name) / 'native-cursor.json'
        self.assertTrue(cursor.exists())
        self.assertNotIn('NATIVE SECRET', cursor.read_text())

    def test_archive_import_precedes_cursor_advance_and_is_idempotent(self):
        self.command()
        self.f.ready()
        cursor = Path(self.f.tmp.name) / 'native-cursor.json'
        self.assertTrue(cursor.exists())
        previous = cursor.read_bytes()
        manifest = (Path(self.f.tmp.name) / 'manifest.json').read_bytes()
        self.f.ready()
        self.assertEqual(cursor.read_bytes(), previous)
        self.assertEqual((Path(self.f.tmp.name) / 'manifest.json').read_bytes(), manifest)

    def test_failed_import_does_not_consume_native_results(self):
        self.command()
        with patch.object(fixtures.checker, 'mask_secrets', side_effect=OSError('scanner unavailable')):
            result = fixtures.checker.prepare(self.f.payload)
        self.assertEqual(result['status'], 'unchecked')
        self.assertFalse((Path(self.f.tmp.name) / 'native-cursor.json').exists())
        ready = self.f.ready()
        self.assertTrue(any(s.get('metadata', {}).get('native_event_type') == 'CommandExecution'
                            for s in ready['transaction']['sources'].values()))

    def test_missing_native_session_keeps_existing_api_path(self):
        self.log.unlink()
        ready = self.f.ready()
        self.assertTrue(any(s.get('native_id') == 'wrapper' for s in ready['transaction']['sources'].values()))
        self.assertFalse((Path(self.f.tmp.name) / 'native-cursor.json').exists())

    def test_delegated_task_context_is_not_saved_as_parent_conversation(self):
        child = self.home / 'sessions/rollout-child.jsonl'
        task = dict(type='response_item', timestamp='2026-11-09T00:00:01Z', payload=dict(type='agent_message', id='task',
                    author='/root', recipient='/root/reviewer', turn_id='child-turn',
                    content=[dict(type='input_text', text='Review the source without executing it.')]))
        child.write_text(json.dumps(dict(type='session_meta', payload=dict(id='child', session_id='native-session'))) + '\n' + json.dumps(task) + '\n')
        activity = dict(type='event_msg', timestamp='2026-11-09T00:00:00Z', payload=dict(type='item_completed', turn_id='turn',
                        item=dict(type='SubAgentActivity', id='delegate', kind='started', agent_thread_id='child',
                                  agent_path='/root/reviewer', model='review-model', reasoning_effort='high')))
        with self.log.open('a') as stream:
            stream.write(json.dumps(activity) + '\n')
        result = fixtures.checker.ingest(self.f.payload)
        self.assertEqual(result['status'], 'ingested', result)
        manifest = json.loads((Path(self.f.tmp.name) / 'manifest.json').read_text())
        tasks = [s for s in manifest if s.get('metadata', {}).get('context_kind') == 'delegated_task']
        self.assertEqual(len(tasks), 1)
        self.assertNotIn(tasks[0]['id'], {r['id'] for r in result['source_refs']})


if __name__ == '__main__':
    unittest.main()
