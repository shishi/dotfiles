import importlib.util
from pathlib import Path
import tempfile
import threading
import time
import unittest


spec = importlib.util.spec_from_file_location('relay', Path(__file__).resolve().parents[1] / 'agent-shared/bin/output-gate-relay.py')
relay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(relay)
spec = importlib.util.spec_from_file_location('checker', Path(__file__).resolve().parents[1] / 'agent-shared/bin/output-gate-check.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class CollectionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        relay.Settings.state_dir = Path(self.tmp.name)
        self.first = dict(type='message', role='user', content=[dict(type='input_text', text='Run the check.')])
        self.second = dict(type='message', role='user', content=[dict(type='input_text', text='What is the result?')])
        self.call = dict(type='function_call', name='exec', call_id='verification', arguments='run check')
        self.output = dict(type='function_call_output', call_id='verification', output='PASS=51 FAIL=0')

    def archive_first_turn(self, output=True):
        relay.record_turn('session', 'first', [self.first, self.call, *([self.output] if output else [])])
        path = relay.Settings.state_dir / 'turns/session/first.json'
        saved = relay.read_json(path)
        saved['time'] = time.time() - relay.STATE_TTL - 1
        relay.write_json(path, saved)
        relay.sweep(force=True)
        directory = relay.Settings.state_dir / 'context/session'
        current, previous = relay.turn_evidence('session', 'second')
        payload = dict(origin='codex', session_id='session', context_dir=str(directory), turn_id='second', draft='',
                       latest_user='Continue.', evidence=current, previous_evidence=previous)
        payload = checker.with_pending_sources(payload)
        checker.context.begin(payload, checker.messages, checker.evidence_parts, lambda data: data, '', [], directory, archive_only=True)
        self.assertFalse((directory / 'pending-turns/first.json').exists())
        return directory

    def test_ingested_archived_records_are_not_reimported_as_an_unknown_turn(self):
        self.archive_first_turn()
        relay.record_turn('session', 'second', [self.first, self.call, self.output, self.second])
        current, previous = relay.turn_evidence('session', 'second')
        self.assertEqual(current, [])
        self.assertFalse(any(item.get('native_id') == 'verification' for turn in previous for item in turn['items']))

    def test_result_after_archive_retirement_keeps_its_original_call_and_turn(self):
        self.archive_first_turn(output=False)
        relay.record_turn('session', 'second', [self.first, self.call, self.output, self.second])
        current, previous = relay.turn_evidence('session', 'second')
        evidence = [(turn['turn_id'], item) for turn in previous for item in turn['items'] if item.get('native_id') == 'verification']
        self.assertEqual(len(evidence), 1)
        self.assertEqual(evidence[0][0], 'first')
        self.assertEqual(evidence[0][1]['input'], 'run check')
        self.assertEqual(evidence[0][1]['output'], 'PASS=51 FAIL=0')

    def test_existing_archive_without_record_index_does_not_gain_new_operations(self):
        directory = self.archive_first_turn()
        (directory / 'record-index.json').unlink()
        before = checker.context.read(directory / 'manifest.json')
        relay.record_turn('session', 'second', [self.first, self.call, self.output, self.second])
        current, previous = relay.turn_evidence('session', 'second')
        payload = dict(origin='codex', session_id='session', turn_id='second', latest_user='Continue.',
                       draft='', evidence=current, previous_evidence=previous)
        checker.context.begin(payload, checker.messages, checker.evidence_parts, lambda data: data, '', [], directory, archive_only=True)
        self.assertEqual(checker.context.read(directory / 'manifest.json'), before)

    def test_existing_archive_can_pair_a_late_result_without_replaying_the_call(self):
        directory = self.archive_first_turn(output=False)
        (directory / 'record-index.json').unlink()
        relay.record_turn('session', 'second', [self.first, self.second, self.output])
        current, previous = relay.turn_evidence('session', 'second')
        evidence = [(turn['turn_id'], item) for turn in previous for item in turn['items'] if item.get('native_id') == 'verification']
        self.assertEqual(evidence[0][0], 'first')
        self.assertEqual(evidence[0][1]['input'], 'run check')
        self.assertEqual(evidence[0][1]['output'], 'PASS=51 FAIL=0')

    def test_filtered_records_do_not_block_archive_retirement(self):
        self.call = dict(self.call, name='gate_findings')
        directory = self.archive_first_turn()
        self.assertEqual(checker.context.read(directory / 'record-index.json'), {})

    def test_unknown_turn_has_one_owner_for_archived_and_new_records(self):
        relay.record_turn('session', 'second', [self.first, self.call, self.second])
        path = relay.Settings.state_dir / 'turns/session/unknown.json'
        record = relay.read_json(path)
        record['time'] = time.time() - relay.STATE_TTL - 1
        relay.write_json(path, record)
        relay.sweep(force=True)
        directory = relay.Settings.state_dir / 'context/session'
        current, previous = relay.turn_evidence('session', 'second')
        payload = dict(origin='codex', session_id='session', turn_id='second', latest_user='Continue.', draft='',
                       evidence=current, previous_evidence=previous)
        checker.context.begin(checker.with_pending_sources(dict(payload, context_dir=str(directory))), checker.messages,
                              checker.evidence_parts, lambda data: data, '', [], directory, archive_only=True)
        another = dict(self.call, call_id='another', arguments='another operation')
        third = dict(self.second, content=[dict(type='input_text', text='Continue again.')])
        relay.record_turn('session', 'third', [self.first, self.call, self.output, self.second, another, third])
        current, previous = relay.turn_evidence('session', 'third')
        sent = checker.with_pending_sources(dict(context_dir=str(directory), turn_id='third', previous_evidence=previous))
        native_ids = {item['native_id'] for turn in sent['previous_evidence'] for item in turn['items']}
        self.assertTrue({'verification', 'another'} <= native_ids)

    def test_turn_transfer_waits_for_the_context_transaction(self):
        relay.record_turn('session', 'first', [self.first, self.call])
        path = relay.Settings.state_dir / 'turns/session/first.json'
        value = relay.read_json(path)
        value['time'] = time.time() - relay.STATE_TTL - 1
        relay.write_json(path, value)
        finished = threading.Event()
        failures = []
        def transfer():
            try:
                relay.sweep(force=True)
            except Exception as error:
                failures.append(error)
            finally:
                finished.set()
        worker = threading.Thread(target=transfer)
        with checker.context.locked(relay.Settings.state_dir / 'context/session'):
            worker.start()
            self.assertFalse(finished.wait(0.2))
            self.assertTrue(path.exists())
        worker.join(2)
        self.assertTrue(finished.is_set())
        self.assertEqual(failures, [])
        self.assertFalse(path.exists())

    def test_result_before_a_steering_message_is_attached_to_its_known_call(self):
        relay.record_turn('session', 'first', [self.first, self.call])
        snapshot = [self.first, self.call, self.output, self.second]
        relay.record_turn('session', 'second', snapshot)
        relay.record_turn('session', 'second', snapshot)
        current, previous = relay.turn_evidence('session', 'second')
        evidence = [e for turn in previous for e in turn['items'] if e['native_id'] == 'verification']
        self.assertEqual(len(evidence), 1)
        self.assertEqual(evidence[0].get('output'), 'PASS=51 FAIL=0')
        self.assertEqual(evidence[0]['input'], 'run check')

    def test_unseen_call_and_result_before_steering_are_not_dropped(self):
        relay.record_turn('session', 'first', [self.first])
        relay.record_turn('session', 'second', [self.first, self.call, self.output, self.second])
        current, previous = relay.turn_evidence('session', 'second')
        evidence = [e for turn in previous for e in turn['items'] if e['native_id'] == 'verification']
        self.assertEqual(len(evidence), 1)
        self.assertEqual(evidence[0].get('output'), 'PASS=51 FAIL=0')

    def test_result_after_steering_still_completes_its_original_turn(self):
        relay.record_turn('session', 'first', [self.first, self.call])
        relay.record_turn('session', 'second', [self.first, self.call, self.second, self.output])
        current, previous = relay.turn_evidence('session', 'second')
        evidence = [e for turn in previous for e in turn['items'] if e['native_id'] == 'verification']
        self.assertEqual(evidence[0].get('output'), 'PASS=51 FAIL=0')
        self.assertEqual(current, [])

    def test_later_call_metadata_completes_an_already_collected_result(self):
        items = relay.evidence_items(relay.records_from([self.output, self.call]), 'e')
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]['tool'], 'exec')
        self.assertEqual(items[0]['input'], 'run check')
        self.assertEqual(items[0]['output'], 'PASS=51 FAIL=0')

    def test_backfilled_archived_result_reaches_the_checker(self):
        relay.record_turn('session', 'first', [self.first, self.call])
        path = relay.Settings.state_dir / 'turns/session/first.json'
        saved = relay.read_json(path)
        saved['time'] = time.time() - relay.STATE_TTL - 1
        relay.write_json(path, saved)
        relay.sweep(force=True)
        context = relay.Settings.state_dir / 'context/session'
        self.assertTrue((context / 'pending-turns/first.json').exists())
        relay.record_turn('session', 'second', [self.first, self.call, self.output, self.second])
        current, previous = relay.turn_evidence('session', 'second')
        payload = checker.with_pending_sources(dict(context_dir=str(context), turn_id='second', previous_evidence=previous))
        evidence = [e for turn in payload['previous_evidence'] for e in turn['items'] if e['native_id'] == 'verification']
        self.assertEqual(len(evidence), 1)
        self.assertEqual(evidence[0].get('output'), 'PASS=51 FAIL=0')


if __name__ == '__main__':
    unittest.main()
