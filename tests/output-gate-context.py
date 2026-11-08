#!/usr/bin/env python3
"""Deterministic context protocol tests; model semantics are tested separately."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'agent-shared/bin'))
spec = importlib.util.spec_from_file_location('checker', ROOT / 'agent-shared/bin/output-gate-check.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class ContextTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        for name, value in [('mask_secrets', lambda data, path: data), ('response_rules', lambda: ''),
                            ('checked_rules', lambda: [])]:
            p = patch.object(checker, name, value)
            p.start()
            self.addCleanup(p.stop)
        self.payload = {'origin': 'codex', 'session_id': 'session', 'context_dir': self.tmp.name,
                        'draft': 'Done.', 'latest_user': 'Use UTF-8.', 'final': True}

    def ready(self, payload=None):
        result = checker.prepare(payload or self.payload)
        self.assertEqual(result['status'], 'ready', result)
        self.assertIn('transaction', result)
        return result

    def reply(self, ready, reply):
        return checker.receive({'payload': self.payload, 'transaction': ready['transaction'],
                                'reply': json.dumps(reply), 'engine': {'family': 'test'}})

    def test_prepare_is_semantic_update(self):
        ready = self.ready()
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        self.assertIn(data['stage'], ('update', 'update_and_judge'))
        self.assertEqual(data['users'][0]['text'], 'Use UTF-8.')

    def test_empty_coverage_cannot_pass(self):
        result = self.reply(self.ready(), {'kind': 'update', 'user_coverage': [], 'focus_refs': [],
            'catalog_coverage': [], 'decisions': [], 'additions': [], 'unresolved': []})
        self.assertEqual(result['status'], 'ready')
        self.assertIn('coverage', json.loads(result['prompt'])['validation_feedback'])

    def test_foreign_reference_is_not_absence(self):
        result = self.reply(self.ready(), {'kind': 'need_refs', 'refs': [
            {'id': 'foreign', 'rev': 'x', 'field': 'text', 'start': 0, 'end': 1}]})
        self.assertEqual(result['status'], 'ready')
        self.assertIn('reference', json.loads(result['prompt'])['validation_feedback'])

    def test_archive_ingestion_is_not_user_meaning_coverage(self):
        ready = self.ready()
        state = ready['transaction']['candidate_state']
        self.assertEqual(state['meaning_cursor']['user_seq'], 0)
        self.assertGreater(state['archive_cursor']['seq'], 0)

    def test_archive_only_ingestion_preserves_the_active_transaction(self):
        self.ready()
        path = Path(self.tmp.name) / 'transaction.json'
        before = path.read_bytes()
        result = checker.ingest(dict(self.payload, latest_user='Another original'))
        self.assertEqual(result['status'], 'ingested', result)
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(len(result['source_refs']), 1)

    def test_irrelevant_tool_body_not_sent(self):
        self.payload['evidence'] = [{'id': 'call', 'tool': 'exec', 'output': 'noise' * 1000000}]
        ready = self.ready()
        self.assertLess(len(ready['prompt'].encode()), 400000)
        self.assertNotIn('noise' * 100, ready['prompt'])

    def test_same_text_occurrences_have_distinct_ids(self):
        self.payload['recent_messages'] = [{'role': 'user', 'text': 'Again'}, {'role': 'user', 'text': 'Again'}]
        ready = self.ready()
        users = json.loads(ready['prompt'])['users']
        self.assertEqual(len({x['ref']['id'] for x in users}), len(users))

    def test_expired_shared_deadline_refuses_reply(self):
        ready = self.ready()
        ready['transaction']['deadline'] = 0
        result = self.reply(ready, {'kind': 'need_refs', 'refs': []})
        self.assertEqual(result['status'], 'unchecked')
        self.assertIn('deadline', result['reason'])

    def test_healthy_primary_keeps_its_remaining_deadline(self):
        calls, cancelled = [], []
        def run(family, timeout, cancel=None):
            calls.append(family)
            end = time.monotonic() + 0.5
            expires = time.monotonic() + timeout
            while time.monotonic() < end:
                if cancel is not None and cancel.is_set():
                    cancelled.append(family)
                    raise checker.EngineFailure('cancelled')
                if time.monotonic() >= expires:
                    raise checker.EngineFailure('deadline')
                time.sleep(0.005)
            return '{"kind":"judgment"}', {'family': family}
        ready = {'status': 'ready', 'prompt': '{}', 'transaction': {'source_end': {}}}
        settings = {'first': 'claude', 'claude': {}, 'codex': {}}
        with patch.object(checker, 'prepare', return_value=ready), \
             patch.object(checker, 'load_settings', return_value=settings), \
             patch.object(checker, 'run_claude', side_effect=lambda p, c, w, t, f, cancel=None: run('claude', t, cancel)), \
             patch.object(checker, 'run_codex', side_effect=lambda p, c, y, w, t, f, cancel=None: run('codex', t, cancel)), \
             patch.object(checker, 'receive', side_effect=lambda r: {'status': 'checked', 'engine': r['engine']}):
            started = time.monotonic()
            result = checker.check(self.payload, started + 0.8)
        self.assertEqual(result['status'], 'checked', result)
        self.assertEqual(result['engine']['family'], 'claude')
        self.assertEqual(calls, ['claude', 'codex'])
        self.assertIn('codex', cancelled)
        self.assertLess(time.monotonic() - started, 0.75)

    def test_cancelled_primary_remains_available_for_the_next_stage(self):
        counts = {'claude': 0, 'codex': 0}
        def claude(p, c, w, t, f, cancel=None):
            counts['claude'] += 1
            if counts['claude'] == 1:
                while not cancel.is_set():
                    time.sleep(0.005)
                raise checker.EngineFailure('cancelled')
            return '{"kind":"judgment"}', {'family': 'claude'}
        def codex(p, c, y, w, t, f, cancel=None):
            counts['codex'] += 1
            if counts['codex'] > 1:
                raise checker.EngineFailure('unavailable')
            return '{"kind":"need_refs"}', {'family': 'codex'}
        ready = {'status': 'ready', 'prompt': '{}', 'transaction': {'source_end': {}}}
        def receive(request):
            return ready if counts['codex'] == 1 else {'status': 'checked', 'engine': request['engine']}
        with patch.object(checker, 'prepare', return_value=ready), \
             patch.object(checker, 'load_settings', return_value={'first': 'claude', 'claude': {}, 'codex': {}}), \
             patch.object(checker, 'run_claude', side_effect=claude), \
             patch.object(checker, 'run_codex', side_effect=codex), \
             patch.object(checker, 'receive', side_effect=receive):
            result = checker.check(self.payload, time.monotonic() + 0.8)
        self.assertEqual(result['status'], 'checked', result)
        self.assertEqual(result['engine']['family'], 'claude')

    @unittest.skipUnless(sys.platform.startswith('linux'), 'Linux process state inspection')
    def test_cancelled_runner_terminates_its_model_process(self):
        pidfile = Path(self.tmp.name) / 'model.pid'
        cancel = threading.Event()
        def stop_after_start():
            expires = time.monotonic() + 1
            while not pidfile.exists() and time.monotonic() < expires:
                time.sleep(0.005)
            cancel.set()
        watcher = threading.Thread(target=stop_after_start)
        watcher.start()
        started = time.monotonic()
        code, _ = checker.run_judge([sys.executable, '-c',
            'import os,time;open(' + repr(str(pidfile)) + ',"w").write(str(os.getpid()));time.sleep(60)'],
            '', Path(self.tmp.name), 1, os.environ.copy(), cancel)
        watcher.join()
        self.assertNotEqual(code, 0)
        self.assertLess(time.monotonic() - started, 0.7)
        state = Path('/proc') / pidfile.read_text() / 'stat'
        self.assertTrue(not state.exists() or state.read_text().split(') ', 1)[1][0] == 'Z')

    def update(self, ready, additions=None, decisions=None):
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        return self.reply(ready, {'kind': 'update', 'user_coverage': [x['ref'] for x in data.get('users', [])],
            'focus_refs': data.get('focus', []), 'catalog_coverage': [dict(id=c['id'], rev=c['rev'],
                disposition='unrelated', related_item_ids=[], reason='test fixture unrelated') for c in data.get('catalog', [])],
            'decisions': decisions if decisions is not None else [dict(item_id=i['id'], action='keep', reason='still active') for i in data['items']],
            'additions': additions or [], 'unresolved': []})

    def judgment(self, ready, **changes):
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        answer = {'kind': 'judgment', 'answer_coverage': [a['ref'] for a in data['answers']],
            'item_coverage': [i['id'] for i in data['items']],
            'decisions': [dict(item_id=i['id'], action='keep', basis='current', refs=[], reason='fixture active') for i in data['items']], 'claims': [dict(id=str(n), answer_ref=a['ref'],
                text=a['text'], requirement_ids=[i['id'] for i in data['items']], evidence=[], verdict='nonfactual')
                for n,a in enumerate(data['answers'])], 'findings': [], 'replacements': [],
            'progress': {'state': 'unknown', 'reason': 'fixture'}, 'focus_candidates': []}
        answer.update(changes)
        return self.reply(ready, answer)

    def live_state(self):
        ready = self.ready()
        user = json.loads(ready['prompt'])['users'][0]
        item = {'id': 'encoding', 'kind': 'constraint', 'text': 'Use UTF-8', 'refs': [user['ref']],
                'related': [], 'target': {'name': 'output', 'revision_refs': []}, 'validity': 'current'}
        ready = self.update(ready, [item])
        result = self.judgment(ready)
        self.assertEqual(result['status'], 'checked', result)
        return result

    def test_warm_state_retains_old_constraint_without_resending_user(self):
        first = self.live_state()
        ready = self.ready()
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        self.assertEqual(data['stage'], 'judge')
        self.assertEqual(data['items'], first['context_state']['items'])
        self.assertNotIn('users', data)
        self.assertEqual(first['progress_state']['evidence'], [])
        self.assertEqual(first['progress_state']['bodies'], [])

    def test_new_user_cannot_silently_drop_old_constraint(self):
        self.live_state()
        self.payload['recent_messages'] = [{'role': 'user', 'text': 'Use UTF-8.'}, {'role': 'user', 'text': 'What time is it?'}]
        self.payload['latest_user'] = 'What time is it?'
        result = self.update(self.ready(), decisions=[])
        self.assertEqual(result['status'], 'ready')
        self.assertIn('coverage', json.loads(result['prompt'])['validation_feedback'])

    def test_nonapplicability_does_not_retire_unfinished_item(self):
        self.live_state()
        self.payload['latest_user'] = 'What time is it?'
        ready = self.ready()
        user = json.loads(ready['prompt'])['users'][0]['ref']
        result = self.update(ready, decisions=[{'item_id': 'encoding', 'action': 'retire', 'basis': 'irrelevant',
            'refs': [user], 'reason': 'topic detour'}])
        self.assertEqual(result['status'], 'ready')
        self.assertIn('non-applicability', json.loads(result['prompt'])['validation_feedback'])

    def test_cancellation_still_requires_current_check_coverage(self):
        self.live_state()
        self.payload['latest_user'] = 'Cancel UTF-8 requirement.'
        ready = self.ready()
        user = json.loads(ready['prompt'])['users'][0]['ref']
        ready = self.update(ready, decisions=[{'item_id': 'encoding', 'action': 'retire', 'basis': 'cancelled',
            'refs': [user], 'reason': 'explicit cancellation'}])
        self.assertEqual(json.loads(ready['prompt'])['items'][0]['id'], 'encoding')
        result = self.judgment(ready)
        self.assertEqual(result['context_state']['items'], [])

    def test_stale_snapshot_cannot_overwrite_newer_generation(self):
        ready1 = self.ready()
        ready2 = self.ready()
        self.assertEqual(self.judgment(self.update(ready1))['status'], 'checked')
        result = self.update(ready2)
        if result['status'] == 'ready':
            result = self.judgment(result)
        self.assertEqual(result['status'], 'unchecked')
        self.assertIn('CAS', result['reason'])

    def test_middle_original_reference_is_exact_and_served(self):
        self.payload['evidence'] = [{'id': 'call', 'tool': 'exec', 'output': 'x' * 500000 + 'FAIL' + 'x' * 500000}]
        ready = self.ready()
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        r = checker.context.ref(source, 'output', 500000, 500004)
        ready = self.reply(ready, {'kind': 'need_refs', 'refs': [r]})
        self.assertEqual(json.loads(ready['prompt'])['retrieved'][0]['text'], 'FAIL')
        self.assertIn(r, ready['transaction']['served_refs'])

    def test_utf8_reference_boundaries_are_validated(self):
        self.payload = {'origin': 'codex', 'final': True, 'draft': 'あ', 'latest_user': 'あ'}
        ready = self.ready()
        user = json.loads(ready['prompt'])['users'][0]['ref']
        result = self.reply(ready, {'kind': 'need_refs', 'refs': [dict(user, start=1)]})
        self.assertEqual(result['status'], 'ready')
        self.assertIn('UTF-8', json.loads(result['prompt'])['validation_feedback'])

    def test_new_revision_keeps_source_identity(self):
        self.payload['sources'] = [{'kind': 'user', 'native_id': 'uuid-1', 'fields': {'text': 'First'}}]
        first = self.ready()['transaction']
        self.payload['sources'][0]['fields']['text'] = 'Correction'
        second = self.ready()['transaction']
        old = next(s for s in first['sources'].values() if s['kind'] == 'user')
        new = [s for s in second['sources'].values() if s['kind'] == 'user'][-1]
        self.assertEqual(old['id'], new['id'])
        self.assertNotEqual(old['rev'], new['rev'])

    def test_missing_catalog_disposition_prevents_closure(self):
        self.payload['evidence'] = [{'id': 'call', 'output': 'FAILED'}]
        ready = self.ready()
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        result = self.reply(ready, {'kind': 'update', 'user_coverage': [u['ref'] for u in data['users']],
            'decisions': [], 'catalog_coverage': [], 'additions': [], 'unresolved': [], 'focus_refs': []})
        self.assertEqual(result['status'], 'ready')
        self.assertIn('catalog coverage', json.loads(result['prompt'])['validation_feedback'])

    def test_new_sources_make_older_judgment_stale(self):
        ready = self.update(self.ready())
        self.payload['latest_user'] = 'Correction'
        self.ready()
        self.payload['latest_user'] = 'Use UTF-8.'
        result = self.judgment(ready)
        self.assertEqual(result['status'], 'unchecked')
        self.assertIn('CAS', result['reason'])

    def test_interrupted_transaction_resumes_validated_units(self):
        ready = self.update(self.ready())
        saved = json.loads((Path(self.tmp.name) / 'transaction.json').read_text())
        self.assertEqual(saved['stage'], 'judge')
        resumed = self.ready()
        self.assertEqual(resumed['transaction']['id'], ready['transaction']['id'])
        self.assertEqual(json.loads(resumed['prompt'])['stage'], 'judge')

    def test_large_new_user_is_covered_in_bounded_units(self):
        self.payload['latest_user'] = 'a' * 430000
        ready = self.ready()
        coverage = []
        while ready['status'] == 'ready' and json.loads(ready['prompt'])['stage'] in ('update', 'update_and_judge'):
            data = checker.context.expand_wire(json.loads(ready['prompt']))
            coverage.extend(u['ref'] for u in data['users'])
            self.assertLess(ready['transaction']['metrics']['inputs'][-1]['bytes'], 400000)
            ready = self.update(ready)
        self.assertEqual(sum(r['end'] - r['start'] for r in coverage), 430000)
        self.assertEqual(self.judgment(ready)['status'], 'checked')

    def test_claude_collector_handoff_does_not_repeat_user_meaning(self):
        self.payload['origin'] = 'claude'
        self.payload['source_collector'] = 'claude-mod'
        self.payload['sources'] = [{'kind': 'user', 'native_id': 'real-uuid', 'fields': {'text': 'Use UTF-8.'}}]
        first = self.live_state()
        self.payload['source_collector'] = 'claude-hook'
        self.payload['sources'] = [{'kind': 'user', 'native_id': 'real-uuid', 'fields': {'text': 'Use UTF-8.'}}]
        second = self.ready()
        self.assertEqual(json.loads(second['prompt'])['stage'], 'judge')
        self.assertEqual(second['transaction']['candidate_state']['items'], first['context_state']['items'])
        self.payload['source_mode'] = 'delta'
        self.payload['sources'][0]['native_id'] = 'different-uuid'
        third = self.ready()
        self.assertIn(json.loads(third['prompt'])['stage'], ('update', 'update_and_judge'))
        self.assertNotEqual(json.loads(third['prompt'])['users'][0]['ref']['id'], first['context_state']['items'][0]['refs'][0]['id'])

    def test_input_schema_is_strict_at_every_object(self):
        schema = self.ready()['schema']
        def visit(node):
            if isinstance(node, dict):
                if node.get('type') == 'object':
                    self.assertFalse(node['additionalProperties'])
                    self.assertEqual(set(node['required']), set(node['properties']))
                for value in node.values():
                    visit(value)
            elif isinstance(node, list):
                for value in node:
                    visit(value)
        visit(schema)

    def test_display_receipt_confirms_answer_completion_and_focus(self):
        ready = self.ready()
        user = json.loads(ready['prompt'])['users'][0]['ref']
        item = {'id': 'q', 'kind': 'question', 'text': 'Answer the question', 'refs': [user],
                'related': [], 'target': {'name': 'answer', 'revision_refs': []}, 'validity': 'current'}
        ready = self.update(ready, [item])
        draft = json.loads(ready['prompt'])['answers'][0]['ref']
        result = self.judgment(ready, decisions=[dict(item_id='q', action='retire', basis='answered',
            refs=[draft], reason='actual response delivered')], focus_candidates=[draft])
        self.assertEqual(result['status'], 'checked', result)
        self.assertEqual(len(result['context_state']['items']), 1)
        self.assertEqual(result['context_state']['focus'], [])
        with self.assertRaisesRegex(ValueError, 'emitted text'):
            checker.context.confirm_display(self.tmp.name, result['display_receipt'], 'failed display')
        confirmed = checker.context.confirm_display(self.tmp.name, result['display_receipt'], result['text'])
        self.assertEqual(confirmed['context_state']['items'], [])
        self.assertEqual(confirmed['context_state']['focus'], [draft])
        self.assertEqual(confirmed['context_state']['pending_display'], {})

    def test_withheld_draft_does_not_become_focus(self):
        ready = self.update(self.ready())
        draft = json.loads(ready['prompt'])['answers'][0]['ref']
        result = self.judgment(ready, focus_candidates=[draft], findings=[{'kind': 'unverified_claim', 'rule': '',
            'source': 'draft', 'excerpt': 'Done.', 'evidence': [{'id': None, 'state': 'absent'}]}])
        self.assertEqual(result['status'], 'checked')
        self.assertIsNone(result['text'])
        self.assertEqual(result['context_state']['focus'], [])
        self.assertNotIn('display_receipt', result)

    def test_original_source_cannot_be_replaced_through_additions_only(self):
        state = self.live_state()['context_state']
        self.payload['latest_user'] = 'New unrelated request'
        ready = self.ready()
        changed = dict(state['items'][0], text='Now use Shift_JIS', refs=[json.loads(ready['prompt'])['users'][0]['ref']])
        result = self.update(ready, [changed])
        self.assertEqual(result['status'], 'ready')
        self.assertIn('overwrite', json.loads(result['prompt'])['validation_feedback'])

    def test_windows_lock_does_not_require_fcntl(self):
        import types
        calls = []
        fake = types.SimpleNamespace(LK_LOCK=1, LK_UNLCK=2, locking=lambda *args: calls.append(args[1:]))
        windows_os = types.SimpleNamespace(name='nt', SEEK_END=checker.context.os.SEEK_END)
        with patch.dict(sys.modules, {'msvcrt': fake}), patch.object(checker.context, 'os', windows_os):
            with checker.context.locked(Path(self.tmp.name)):
                self.assertEqual(calls, [(1, 1)])
        self.assertEqual(calls, [(1, 1), (2, 1)])

    def test_scope_coverage_expands_only_the_visible_users_and_catalog(self):
        self.payload['evidence'] = [{'id': 'call', 'tool': 'exec', 'output': 'A result'}]
        self.payload['recent_messages'] = [{'role': 'user', 'text': 'first'}, {'role': 'assistant', 'text': 'report'}]
        ready = self.ready()
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        result = self.reply(ready, {'kind': 'update', 'user_coverage': [data['user_scope']['ref']],
            'catalog_coverage': [dict(data['catalog_scope'], disposition='unrelated', related_item_ids=[], reason='fixture')],
            'decisions': [], 'additions': [], 'unresolved': [], 'focus_refs': []})
        self.assertEqual(result['status'], 'ready', result)
        self.assertEqual(json.loads(result['prompt'])['stage'], 'judge')

    def test_large_original_request_is_paged_without_marking_remaining_bytes_served(self):
        import random
        original = ''.join(random.Random(17).choices('あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん', k=230000))
        self.payload['evidence'] = [{'id': 'call', 'tool': 'exec', 'output': original}]
        ready = self.ready()
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        full = checker.context.ref(source, 'output')
        ready = self.reply(ready, {'kind': 'need_refs', 'refs': [full]})
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        self.assertTrue(data['remaining_refs'])
        self.assertLessEqual(ready['transaction']['metrics']['inputs'][-1]['bytes'], 400000)
        with self.assertRaisesRegex(ValueError, 'not served'):
            checker.context.resolve_refs(ready['transaction'], [full], True)
        pieces = [e['text'] for e in data['retrieved']]
        while data['remaining_refs']:
            ready = self.reply(ready, {'kind': 'need_refs', 'refs': data['remaining_refs']})
            data = checker.context.expand_wire(json.loads(ready['prompt']))
            pieces.extend(e['text'] for e in data['retrieved'])
            self.assertLessEqual(ready['transaction']['metrics']['inputs'][-1]['bytes'], 400000)
        self.assertEqual(''.join(pieces), original)
        checker.context.resolve_refs(ready['transaction'], [full], True)

    def test_completed_meaning_update_is_reused_after_draft_changes(self):
        ready = self.update(self.ready())
        self.payload['draft'] = 'A different answer'
        resumed = self.ready()
        data = checker.context.expand_wire(json.loads(resumed['prompt']))
        self.assertEqual(data['stage'], 'judge')
        self.assertEqual(data['answers'][0]['text'], 'A different answer')
        self.assertEqual(resumed['transaction']['resumed_update_units'], 1)
        self.assertFalse((Path(self.tmp.name) / 'state.json').exists())

    def test_partial_meaning_update_resumes_with_new_user_without_replaying_prefix(self):
        import random
        old = ''.join(random.Random(31).choices('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', k=430000))
        self.payload['latest_user'] = old
        ready = self.ready()
        covered_end = max(u['ref']['end'] for u in json.loads(ready['prompt'])['users'])
        ready = self.update(ready)
        self.payload['draft'] = 'Changed draft'
        self.payload['recent_messages'] = [{'role': 'user', 'text': old}, {'role': 'user', 'text': 'Continue'}]
        self.payload['latest_user'] = 'Continue'
        resumed = self.ready()
        data = checker.context.expand_wire(json.loads(resumed['prompt']))
        self.assertIn(data['stage'], ('update', 'update_and_judge'))
        self.assertEqual(data['users'][0]['ref']['start'], covered_end)
        self.assertEqual(resumed['transaction']['candidate_state']['meaning_cursor']['user_seq'], 0)
        self.assertFalse((Path(self.tmp.name) / 'state.json').exists())

    def test_small_gap_has_served_original_but_stays_unavailable(self):
        self.payload['evidence'] = [{'id': 'gap', 'unavailable': True, 'note': 'No original result'}]
        ready = self.ready()
        grounds = [g for g in json.loads(ready['prompt'])['catalog_grounding'] if g['kind'] == 'gap']
        self.assertTrue(grounds)
        self.assertTrue(all(not g['available'] for g in grounds))
        for ground in grounds:
            checker.context.resolve_refs(ready['transaction'], [ground['ref']], True)

    def test_validation_feedback_retries_without_advancing_and_can_recover(self):
        ready = self.ready()
        bad = {'kind': 'need_refs', 'refs': [{'id': 'foreign', 'rev': 'x', 'field': 'text', 'start': 0, 'end': 1}]}
        rejected = self.reply(ready, bad)
        self.assertEqual(rejected['transaction']['candidate_state'], ready['transaction']['candidate_state'])
        self.assertEqual(rejected['transaction']['completed_units'], [])
        self.assertEqual(self.judgment(self.update(rejected))['status'], 'checked')

    def test_same_invalid_reference_does_not_loop_indefinitely(self):
        ready = self.ready()
        bad = {'kind': 'need_refs', 'refs': [{'id': 'foreign', 'rev': 'x', 'field': 'text', 'start': 0, 'end': 1}]}
        for _ in range(3):
            ready = self.reply(ready, bad)
        self.assertEqual(ready['status'], 'unchecked')
        self.assertIn('reference', ready['reason'])

    def test_small_originals_remain_available_across_retrieval_requests(self):
        self.payload['evidence'] = [{'id': 'one', 'tool': 'exec', 'output': 'small one'}, {'id': 'two', 'tool': 'exec', 'output': 'small two'}]
        ready = self.ready()
        sources = [s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence']
        first, second = [checker.context.ref(s, 'output') for s in sources]
        ready = self.reply(ready, {'kind': 'need_refs', 'refs': [first]})
        ready = self.reply(ready, {'kind': 'need_refs', 'refs': [second]})
        self.assertEqual({e['text'] for e in json.loads(ready['prompt'])['retrieved']}, {'small one', 'small two'})

    def test_final_meaning_unit_and_judgment_can_close_in_one_reply(self):
        ready = self.ready()
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        self.assertEqual(data['stage'], 'update_and_judge')
        reply = {'kind': 'judgment', 'user_coverage': [u['ref'] for u in data['users']],
            'catalog_coverage': [], 'decisions': [], 'additions': [], 'unresolved': [], 'focus_refs': [],
            'answer_coverage': [a['ref'] for a in data['answers']], 'item_coverage': [],
            'claims': [dict(id=str(n), answer_ref=a['ref'], text=a['text'], requirement_ids=[], evidence=[], verdict='nonfactual') for n,a in enumerate(data['answers'])],
            'findings': [], 'replacements': [], 'progress': {'state': 'unknown', 'reason': 'fixture'}, 'focus_candidates': []}
        result = self.reply(ready, reply)
        self.assertEqual(result['status'], 'checked', result)
        self.assertGreater(result['context_state']['meaning_cursor']['user_seq'], 0)
        self.assertEqual(len(result['context_metrics']['inputs']), 1)

    def test_support_can_use_the_necessary_original_range_without_reading_unrelated_bytes(self):
        prefix = 'x' * 350000
        self.payload['evidence'] = [{'id': 'call', 'tool': 'exec', 'output': prefix + 'target passed' + 'y' * 350000}]
        ready = self.ready()
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        needed = checker.context.ref(source, 'output', len(prefix), len(prefix) + len('target passed'))
        ready = self.reply(ready, {'kind': 'need_refs', 'refs': [needed]})
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        ready = self.reply(ready, {'kind': 'update', 'user_coverage': [u['ref'] for u in data['users']],
            'focus_refs': [], 'catalog_coverage': [{'id': source['id'], 'rev': source['rev'], 'disposition': 'retrieve',
                'related_item_ids': [], 'reason': 'The target result is in this exact original range', 'grounding_refs': [needed]}],
            'decisions': [], 'additions': [], 'unresolved': []})
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        answer = data['answers'][0]
        result = self.judgment(ready, claims=[{'id': 'c', 'answer_ref': answer['ref'], 'text': answer['text'],
            'requirement_ids': [], 'evidence': [{'ref': needed, 'relation': 'supports'}], 'verdict': 'supported'}])
        self.assertEqual(result['status'], 'checked', result)
        self.assertLess(result['context_metrics']['retrieved_bytes'], len(prefix))

    def test_current_unshown_draft_cannot_retire_an_old_question_during_update(self):
        ready = self.ready()
        user = json.loads(ready['prompt'])['users'][0]['ref']
        old_answer = json.loads(ready['prompt'])['answers'][0]['ref']
        item = {'id': 'q', 'kind': 'question', 'text': 'Explain', 'refs': [user], 'related': [],
                'target': {'name': 'answer', 'revision_refs': []}, 'validity': 'current'}
        self.judgment(self.update(ready, [item]))
        self.payload['latest_user'] = 'Continue'
        self.payload['turn_id'] = 'next-turn'
        self.payload['draft'] = 'Not yet displayed'
        ready = self.ready()
        draft = json.loads(ready['prompt'])['answers'][0]['ref']
        result = self.update(ready, decisions=[{'item_id': 'q', 'action': 'retire', 'basis': 'answered',
            'refs': [draft], 'reason': 'It appears in the draft'}])
        self.assertEqual(result['status'], 'ready')
        self.assertIn('deliverable', json.loads(result['prompt'])['validation_feedback'])
        self.assertEqual(result['transaction']['candidate_state']['items'][0]['id'], 'q')
        ready = self.reply(result, {'kind': 'need_refs', 'refs': [old_answer]})
        ready = self.update(ready)
        result = self.judgment(ready, decisions=[{'item_id': 'q', 'action': 'retire', 'basis': 'answered',
            'refs': [old_answer], 'reason': 'An older unshown response exists'}])
        self.assertEqual(result['status'], 'ready', result)
        self.assertEqual(result['transaction']['candidate_state']['items'][0]['id'], 'q')

    def test_tampered_source_file_cannot_keep_its_old_revision(self):
        ready = self.ready()
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'user')
        path = Path(self.tmp.name) / 'sources' / (checker.context.digest([source['id'], source['rev']]) + '.json')
        changed = json.loads(path.read_text())
        changed['fields']['text'] = 'A different instruction'
        path.write_text(json.dumps(changed))
        result = checker.prepare(self.payload)
        self.assertEqual(result['status'], 'unchecked')
        self.assertIn('archive revision', result['reason'])

    def test_model_chosen_literal_locates_original_middle_without_full_output(self):
        output = 'x' * 320000 + '\n{"passed":11,"failed":1}\n' + 'y' * 320000
        self.payload['evidence'] = [{'id': 'call', 'tool': 'exec', 'output': output}]
        ready = self.ready()
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        locator = {'id': source['id'], 'rev': source['rev'], 'field': 'output', 'literal': '"failed"', 'after': 0}
        ready = self.reply(ready, {'kind': 'need_refs', 'refs': [locator]})
        self.assertEqual(ready['status'], 'ready', ready)
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        self.assertIsNone(data['validation_feedback'])
        self.assertIn('"failed":1', ''.join(r['text'] for r in data['retrieved']))
        self.assertLess(sum(len(r['text'].encode()) for r in data['retrieved']), 10000)
        self.assertTrue(data['locator_results'][0]['matches'])
        for r in data['retrieved']:
            checker.context.resolve_refs(ready['transaction'], [r['ref']], True)

    def test_locator_no_match_is_not_original_coverage_or_success(self):
        import random
        original = ''.join(random.Random(73).choices('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', k=300000))
        self.payload['evidence'] = [{'id': 'call', 'tool': 'exec', 'output': original}]
        ready = self.ready()
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        locator = {'id': source['id'], 'rev': source['rev'], 'field': 'output', 'literal': 'f.*ed', 'after': 0}
        ready = self.reply(ready, {'kind': 'need_refs', 'refs': [locator]})
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        self.assertTrue(data['locator_results'][0]['not_found'])
        self.assertEqual(data['locator_results'][0]['matches'], [])
        with self.assertRaisesRegex(ValueError, 'not served'):
            checker.context.resolve_refs(ready['transaction'], [checker.context.ref(source, 'output')], True)
        self.assertEqual(ready['transaction']['completed_units'], [])

    def test_locator_matches_page_without_changing_the_source_revision(self):
        self.payload['evidence'] = [{'id': 'call', 'tool': 'exec', 'output': ('needle' + 'z' * 5000) * 50}]
        ready = self.ready()
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        locator = {'id': source['id'], 'rev': source['rev'], 'field': 'output', 'literal': 'needle', 'after': 0}
        ready = self.reply(ready, {'kind': 'need_refs', 'refs': [locator]})
        result = json.loads(ready['prompt'])['locator_results'][0]
        self.assertIsNotNone(result['remaining_after'])
        next_ready = self.reply(ready, {'kind': 'need_refs', 'refs': [dict(locator, after=result['remaining_after'])]})
        later = json.loads(next_ready['prompt'])['locator_results'][0]
        self.assertGreater(later['matches'][0]['start'], result['matches'][-1]['start'])
        self.assertEqual(later['matches'][0]['rev'], source['rev'])

    def test_lossless_source_wire_codec_preserves_original_refs_and_important_repeated_condition(self):
        text = 'Keep UTF-8. Do not publish. ' * 200
        self.payload['latest_user'] = text
        ready = self.ready()
        data = json.loads(ready['prompt'])
        wire_text = data['users'][0]['text']
        self.assertIsInstance(wire_text, dict)
        self.assertEqual(checker.context.expand_source_text(wire_text), text)
        source_ref = data['users'][0]['ref']
        self.assertEqual(source_ref['end'], len(text.encode()))
        self.assertEqual(checker.context.resolve_refs(ready['transaction'], [source_ref], True)[0]['text'], text)
        source = ready['transaction']['sources'][source_ref['id'] + ':' + source_ref['rev']]
        self.assertEqual(source['fields']['text'], text)

    def test_stale_reply_cannot_roll_back_validated_transaction_progress(self):
        first = self.ready()
        late = self.ready()
        self.update(first)
        path = Path(self.tmp.name) / 'transaction.json'
        before = json.loads(path.read_text())
        user_ref = json.loads(late['prompt'])['users'][0]['ref']
        rejected = self.reply(late, {'kind': 'need_refs', 'refs': [user_ref]})
        self.assertEqual(rejected['status'], 'unchecked')
        self.assertIn('CAS', rejected['reason'])
        self.assertEqual(json.loads(path.read_text()), before)

    def test_conflicting_new_item_ids_do_not_silently_drop_a_requirement(self):
        ready = self.ready()
        user_ref = json.loads(ready['prompt'])['users'][0]['ref']
        first = {'id': 'same-new-id', 'kind': 'requirement', 'text': 'Keep A', 'refs': [user_ref],
                 'related': [], 'target': {'name': 'task', 'revision_refs': []}, 'validity': 'current'}
        result = self.update(ready, [first, dict(first, text='Also do B')])
        self.assertEqual(result['status'], 'ready')
        self.assertIn('identity', json.loads(result['prompt'])['validation_feedback'])
        self.assertEqual(result['transaction']['candidate_state']['items'], [])

    def test_prefetch_budget_uses_lossless_wire_bytes_and_supplies_the_whole_original(self):
        original = 'x' * 320000 + '\n{"passed":11,"failed":1}\n' + 'y' * 320000
        self.payload['evidence'] = [{'id': 'call', 'tool': 'exec', 'output': original}]
        ready = self.ready()
        packet = json.loads(ready['prompt'])
        output = next(e for e in packet['catalog_grounding'] if e['ref']['field'] == 'output')
        self.assertEqual(checker.context.expand_source_text(output['text']), original)
        self.assertEqual(output['ref']['end'], len(original.encode()))
        self.assertLess(len(checker.context.encoded(output)), 8192)
        checker.context.resolve_refs(ready['transaction'], [output['ref']], True)

    def test_contradicted_claim_cannot_be_displayed_without_a_valid_finding(self):
        self.payload['evidence'] = [{'id': 'call', 'tool': 'exec', 'output': '11 passed, 1 failed'}]
        ready = self.ready()
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        result_ref = next(g['ref'] for g in data['catalog_grounding'] if g['ref']['field'] == 'output')
        answer = {'kind': 'judgment', 'user_coverage': [u['ref'] for u in data['users']],
            'catalog_coverage': [dict(data['catalog_scope'], disposition='retrieve', related_item_ids=[], reason='contradiction', grounding_refs=[result_ref])],
            'additions': [], 'decisions': [], 'unresolved': [], 'focus_refs': [], 'focus_resolved': [],
            'item_coverage': [], 'answer_coverage': [a['ref'] for a in data['answers']],
            'claims': [{'id': 'c', 'answer_ref': data['answers'][0]['ref'], 'text': 'all passed', 'requirement_ids': [],
                        'evidence': [{'ref': result_ref, 'relation': 'contradicts'}], 'verdict': 'contradicted'}],
            'findings': [], 'replacements': [], 'progress': {'state': 'unknown', 'reason': 'fixture'}, 'focus_candidates': []}
        rejected = self.reply(ready, answer)
        self.assertEqual(rejected['status'], 'ready')
        self.assertIn('contradicted', json.loads(rejected['prompt'])['validation_feedback'])
        self.assertFalse((Path(self.tmp.name) / 'state.json').exists())
        answer['findings'] = [{'kind': 'unverified_claim', 'rule': '', 'source': 'draft', 'excerpt': 'Done.',
                              'evidence': [{'id': 'call', 'state': 'failed'}]}]
        result = self.reply(rejected, answer)
        self.assertEqual(result['status'], 'checked', result)
        self.assertIsNone(result['text'])
        self.assertEqual(len(result['findings']), 1)

    def test_assistant_discovery_and_stable_user_findings_need_no_eager_history_aliases(self):
        self.payload['recent_messages'] = [{'role': 'user', 'text': 'Do A and B'},
            {'role': 'assistant', 'text': 'Plan: A then B. Shall I proceed?'},
            {'role': 'assistant', 'text': 'A progress report'}, {'role': 'user', 'text': 'Yes'}]
        self.payload['latest_user'] = 'Yes'
        ready = self.ready()
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        self.assertEqual(data['catalog'], [])
        self.assertFalse(any(k.startswith(('recent-', 'start-')) for k in data['aliases']))
        self.assertEqual(data['catalog_summary']['assistant'], 4)
        catalog = next(g for g in data['catalog_grounding'] if g['kind'] == 'catalog')
        entries = [json.loads(line) for line in catalog['text'].splitlines()]
        proposals = [c for c in entries if c['kind'] == 'assistant']
        self.assertEqual(len(proposals), 2)
        proposal = proposals[0]
        proposal_ref = {'id': proposal['id'], 'rev': proposal['rev'], 'field': 'text', 'start': 0, 'end': proposal['fields']['text']}
        ready = self.reply(ready, {'kind': 'need_refs', 'refs': [proposal_ref]})
        self.assertIn('Shall I proceed?', checker.context.expand_wire(json.loads(ready['prompt']))['retrieved'][0]['text'])
        user = data['users'][0]
        ready = self.update(ready)
        result = self.judgment(ready, findings=[{'kind': 'missing_request', 'rule': '', 'source': user['ref']['id'],
            'excerpt': user['text'], 'evidence': [{'id': None, 'state': 'absent'}]}])
        self.assertEqual(result['status'], 'checked', result)
        self.assertEqual(result['findings'][0]['source'], user['ref']['id'])

    def test_unverified_status_can_be_reported_honestly_without_a_finding(self):
        self.payload['draft'] = 'The result is still unverified.'
        ready = self.update(self.ready())
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        result = self.judgment(ready, claims=[{'id': 'c', 'answer_ref': data['answers'][0]['ref'],
            'text': 'The result is still unverified.', 'requirement_ids': [], 'evidence': [], 'verdict': 'unverified'}])
        self.assertEqual(result['status'], 'checked')
        self.assertEqual(result['text'], self.payload['draft'])
        self.assertEqual(result['findings'], [])

    def test_confirmed_focus_is_prefetched_as_displayed_on_the_next_short_approval(self):
        self.payload['turn_id'] = 'first'
        ready = self.ready()
        ready = self.update(ready)
        answer = checker.context.expand_wire(json.loads(ready['prompt']))['answers'][0]['ref']
        result = self.judgment(ready, focus_candidates=[answer])
        checker.context.confirm_display(self.tmp.name, result['display_receipt'], result['text'])
        self.payload.update(turn_id='second', latest_user='Yes', draft='A new answer')
        ready = self.ready()
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        focus = next(g for g in data['catalog_grounding'] if g['ref'] == answer)
        self.assertTrue(focus['displayed'])
        self.assertEqual(focus['text'], 'Done.')
        self.assertEqual(data['focus'], [answer])

    def test_explicit_new_native_user_is_not_replaced_by_an_old_positional_identity(self):
        self.payload.update(turn_id='one', latest_user='うん')
        self.judgment(self.update(self.ready()))
        self.payload.update(turn_id='two', recent_messages=[{'role': 'user', 'text': 'うん', 'native_id': 'new-genuine-user-event'}])
        ready = self.ready()
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        self.assertIn(data['stage'], ('update', 'update_and_judge'))
        self.assertEqual(len(data['users']), 1)
        source = ready['transaction']['sources'][data['users'][0]['ref']['id'] + ':' + data['users'][0]['ref']['rev']]
        self.assertEqual(source['native_id'], 'new-genuine-user-event')
        self.assertFalse(data['users'][0].get('identity_gap'))

    def test_new_turn_without_native_id_still_delivers_an_identical_current_request(self):
        self.payload.update(turn_id='one', latest_user='Repeat the check')
        self.judgment(self.update(self.ready()))
        self.payload.update(turn_id='two', recent_messages=[{'role': 'user', 'text': 'Repeat the check'}])
        ready = self.ready()
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        self.assertIn(data['stage'], ('update', 'update_and_judge'))
        self.assertEqual([u['text'] for u in data['users']], ['Repeat the check'])

    def test_uncorrelated_native_snapshot_keeps_active_items_and_cannot_replay_authorization(self):
        self.payload['origin'] = 'claude'
        first = self.live_state()
        self.payload.update(source_collector='claude-hook', source_mode='bootstrap',
            sources=[{'kind': 'user', 'native_id': 'uncorrelated-uuid', 'fields': {'text': 'Use UTF-8.'}}])
        ready = self.ready()
        data = checker.context.expand_wire(json.loads(ready['prompt']))
        self.assertTrue(data['users'][0]['identity_gap'])
        self.assertEqual(ready['transaction']['candidate_state']['items'], first['context_state']['items'])
        original = data['users'][0]['ref']
        source = ready['transaction']['sources'][original['id'] + ':' + original['rev']]
        self.assertEqual(source['native_id'], 'uncorrelated-uuid')
        authorization = {'id': 'new-authorization', 'kind': 'authorization', 'text': 'Proceed', 'refs': [original],
            'related': [], 'target': {'name': 'action', 'revision_refs': []}, 'validity': 'current'}
        rejected = self.update(ready, [authorization])
        self.assertIn('uncertain source identity', json.loads(rejected['prompt'])['validation_feedback'])
        self.assertEqual(rejected['transaction']['candidate_state']['items'], first['context_state']['items'])

    def test_verified_request_coordinate_links_a_native_upgrade_without_replaying_it(self):
        self.payload.update(turn_id='one', request_id='event-one')
        first = self.live_state()
        self.payload['sources'] = [{'kind': 'user', 'native_id': 'physical-one', 'fields': {'text': 'Use UTF-8.'}}]
        ready = self.ready()
        self.assertEqual(json.loads(ready['prompt'])['stage'], 'judge')
        native = next(s for s in ready['transaction']['sources'].values() if s.get('native_id') == 'physical-one')
        self.assertEqual(native['metadata']['replay_of']['id'], first['context_state']['items'][0]['refs'][0]['id'])
        self.payload['request_id'] = 'event-two'
        self.payload['sources'][0]['native_id'] = 'physical-two'
        ready = self.ready()
        users = checker.context.expand_wire(json.loads(ready['prompt']))['users']
        self.assertEqual(len(users), 1)
        self.assertFalse(users[0].get('identity_gap'))


if __name__ == '__main__':
    unittest.main()
