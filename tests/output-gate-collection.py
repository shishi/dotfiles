import importlib.util
from pathlib import Path
import tempfile
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
