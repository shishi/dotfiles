#!/usr/bin/env python3
"""Deterministic context protocol tests; model semantics are tested separately."""
import importlib.util
import hashlib
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
        for name, value in [('mask_secrets', lambda data, path, *args: data), ('response_rules', lambda: ''),
                            ('checked_rules', lambda: [])]:
            p = patch.object(checker, name, value)
            p.start()
            self.addCleanup(p.stop)
        self.payload = {'origin': 'codex', 'session_id': 'session', 'context_dir': self.tmp.name,
                        'draft': 'Done.', 'latest_user': 'Use UTF-8.', 'final': True}

    def packet(self, ready):
        return checker.context.expand_wire(json.loads(ready['prompt']))

    def ready(self, payload=None):
        result = checker.prepare(payload or self.payload)
        self.assertEqual(result['status'], 'ready', result)
        self.assertIn('transaction', result)
        return result

    def reply(self, ready, reply):
        data = self.packet(ready)
        if reply.get('kind') in ('update', 'judgment') and data.get('users'):
            ids = [i['id'] for i in reply.get('additions', []) if i['kind'] != 'fact']
            reply.setdefault('user_assessments', ([{'refs': [r for i in reply.get('additions', []) if i['id'] in ids for r in i['refs']], 'disposition': 'live', 'item_ids': ids, 'resolution_refs': [], 'reason':'fixture live meaning'}] if ids else []) + [{'refs':[data['user_scope']['ref']], 'disposition':'context_only', 'item_ids':[], 'resolution_refs':[], 'reason':'fixture residual context'}])
        return checker.receive({'payload': self.payload, 'transaction': ready['transaction'],
                                'reply': json.dumps(reply), 'engine': {'family': 'test'}})

    def test_unchecked_final_is_withheld_until_repaired_or_stopped(self):
        payload = dict(self.payload, continuation='withhold', draft='Unverified original.')
        result = checker.unchecked(payload, 'engine unavailable')
        self.assertEqual(result['status'], 'unchecked')
        self.assertIsNone(result['bodies'])
        self.assertTrue(result['agent_message'])
        self.assertNotIn('Unverified original.', result['fallback_text'])
        for round in range(1, 4):
            payload.update(round=round, progress_state=result['progress_state'])
            result = checker.unchecked(payload, 'engine unavailable')
        self.assertTrue(result['stopped'])
        self.assertIsNotNone(result['bodies'])
        self.assertNotIn('Unverified original.', result['text'])

    def test_prepare_is_semantic_update(self):
        ready = self.ready()
        data = self.packet(ready)
        self.assertIn(data['stage'], ('update', 'update_and_judge'))
        self.assertEqual(data['users'][0]['text'], 'Use UTF-8.')

    def test_reading_users_without_accounting_for_their_meaning_cannot_pass(self):
        ready = self.ready()
        data = self.packet(ready)
        result = self.reply(ready, {'kind':'update', 'user_coverage':[data['user_scope']['ref']],
            'user_assessments':[], 'catalog_coverage':[], 'decisions':[], 'additions':[], 'unresolved':[], 'focus_refs':[]})
        self.assertEqual(result['status'],'ready')
        self.assertIn('remaining user meaning',self.packet(result)['validation_feedback'])

    def test_live_meaning_cannot_use_a_read_bundle_to_hide_a_different_source(self):
        ready = self.ready()
        data = self.packet(ready)
        user = data['users'][0]['ref']
        item = dict(id='r',kind='constraint',text='Use UTF-8',refs=[user],related=[],target=dict(name='output',revision_refs=[]),validity='current')
        result = self.reply(ready, dict(kind='update',user_coverage=[data['user_scope']['ref']],
            user_assessments=[dict(refs=[data['user_scope']['ref']],disposition='live',item_ids=['r'],resolution_refs=[],reason='read everything')],
            additions=[item],decisions=[],catalog_coverage=[],unresolved=[],focus_refs=[]))
        self.assertIn('original user refs',self.packet(result)['validation_feedback'])

    def test_unverified_aggregate_is_flagged_over_its_entire_original_range(self):
        self.payload['draft']='First result. Second result.'
        ready=self.update(self.ready())
        data=self.packet(ready)
        result=self.judgment(ready,claims=[dict(id='all',answer_ref=data['answers'][0]['ref'],text='both',requirement_ids=[],evidence=[],verdict='unverified')])
        self.assertEqual(result['status'],'checked')
        self.assertTrue(any(f['excerpt']==self.payload['draft'] for f in result['findings']))
        self.assertIsNone(result['text'])

    def test_literal_lookup_merges_overlapping_original_windows(self):
        self.payload['evidence']=[dict(id='op',output='needle '*20)]
        ready=self.ready();source=next(s for s in ready['transaction']['sources'].values() if s['kind']=='evidence')
        ranges,result=checker.context.locate_refs(ready['transaction'],dict(id=source['id'],rev=source['rev'],field='output',literal='needle',after=0))
        self.assertEqual(len(result['matches']),20)
        self.assertEqual(ranges,[checker.context.ref(source,'output')])

    def test_shared_source_lines_are_lossless_without_repeating_the_whole_template(self):
        import random
        rng=random.Random(31)
        common=''.join(rng.choices('あいうえおabcdefghijklmnopqrstuvwxyz',k=6000))+'\n'
        entries=[]
        for n in range(6):
            text='Source template\nprogress='+str(n)+'\n'+common+'counter='+str(n*2)+'\n'
            entries.append(dict(kind='user',ref=dict(id='u'+str(n),rev='r'+str(n),field='text',start=0,end=len(text.encode())),text=text))
        data=dict(users=entries)
        packet=checker.context.wire_value(data)
        self.assertEqual(checker.context.expand_wire(packet),data)
        self.assertLess(len(checker.context.encoded(packet)),len(checker.context.encoded(data))//2)

    def test_nonfinal_rule_input_does_not_grow_with_execution_evidence(self):
        payload=dict(origin='codex',final=False,draft='その表現を整えるよ。',latest_user='文体を続けて',
            recent_messages=[dict(role='user',text='文書の文体を維持して')],shown_text='先ほどの説明')
        sizes=[]
        for count in (1,200):
            evidence=[dict(id=str(n),tool='exec',output='runtime output '*100) for n in range(count)]
            data=checker.build_input(dict(payload,evidence=evidence,previous_evidence=[dict(turn_id='old',items=evidence)],
                previous_findings=[dict(kind='missing_request')],progress_state=dict(round=1,stalled=1,bodies=['old'],findings=[],evidence=evidence)), 'rules')
            self.assertEqual(data['evidence'],[])
            self.assertEqual(data['previous_evidence'],[])
            self.assertNotIn('progress_state',data)
            self.assertNotIn('previous_findings',data)
            self.assertEqual(data['messages'],checker.messages(payload))
            self.assertEqual(data['protected_parts_of_draft'],checker.protected_parts(payload['draft']))
            sizes.append(len(checker.render(data).encode()))
        self.assertEqual(sizes[0],sizes[1])

    def test_raw_judge_generates_without_accepting_state(self):
        ready=self.ready();path=Path(self.tmp.name)/'transaction.json';before=path.read_bytes()
        with patch.object(checker,'run_codex',return_value=('{}',dict(family='codex'))) as run:
            result=checker.raw_judge(dict(payload=self.payload,prompt=ready['prompt'],transaction=ready['transaction']))
        self.assertEqual(result['status'],'answered')
        self.assertEqual(path.read_bytes(),before)
        self.assertFalse((Path(self.tmp.name)/'state.json').exists())
        self.assertEqual(run.call_count,1)
        with patch.object(checker,'run_codex') as run:
            rejected=checker.raw_judge(dict(payload=self.payload,prompt=ready['prompt']+' ',transaction=ready['transaction']))
        self.assertEqual(rejected['status'],'unavailable')
        run.assert_not_called()

    def test_expired_raw_packet_is_not_sent_to_a_model(self):
        ready=self.ready();ready['transaction']['deadline']=0
        checker.context.atomic(Path(self.tmp.name)/'transaction.json',ready['transaction'])
        with patch.object(checker,'run_codex') as run:
            result=checker.raw_judge(dict(payload=self.payload,prompt=ready['prompt'],transaction=ready['transaction']))
        self.assertEqual(result['status'],'unavailable')
        run.assert_not_called()

    def test_nonfinal_primary_has_full_budget_and_records_attempts(self):
        calls=[]
        def run(family,cancel):
            calls.append(family);end=time.monotonic()+0.5
            while time.monotonic()<end:
                if cancel.is_set():raise checker.EngineFailure('cancelled')
                time.sleep(0.005)
            return json.dumps(dict(replacements=[],findings=[],progress=dict(state='unknown',reason='fixture'))),dict(family=family,usage=dict(input_tokens=11,output_tokens=7))
        payload=dict(self.payload,final=False)
        with patch.object(checker,'load_settings',return_value=dict(first='claude',claude={},codex={})), patch.object(checker,'run_claude',side_effect=lambda p,c,w,t,f,cancel:run('claude',cancel)), patch.object(checker,'run_codex',side_effect=lambda p,c,y,w,t,f,cancel:run('codex',cancel)):
            result=checker.check(payload,time.monotonic()+0.8)
        self.assertEqual(result['status'],'checked',result.get('reason'))
        attempts=result['context_metrics']['model_attempts']
        self.assertEqual([a['family'] for a in attempts],['claude','codex'])
        self.assertEqual(attempts[0]['usage'],dict(input_tokens=11,output_tokens=7))
        self.assertEqual(attempts[1]['outcome'],'cancelled')
        self.assertIsNone(attempts[1]['usage'])

    def test_typed_reference_resolution_does_not_depend_on_field_names(self):
        reference=dict(id='source',rev='revision',field='text',start=0,end=12)
        data=dict(new_field=[dict(nested={'$source_ref':'@0'})],literal='@0')
        self.assertEqual(checker.context.expand_references(data,{'@0':reference}),dict(new_field=[dict(nested=reference)],literal='@0'))

    def test_resolved_user_assessment_accepts_the_supplied_compact_ref(self):
        self.live_state()
        self.payload.update(turn_id='cancel-turn',request_id='cancel-request',latest_user='Cancel the UTF-8 constraint.')
        ready=self.ready();wire=json.loads(ready['prompt']);user=wire['users'][0]['ref']
        result=self.reply(ready,dict(kind='update',user_coverage=[user],user_assessments=[dict(refs=[user],disposition='resolved',item_ids=[],resolution_refs=[user],reason='explicit user cancellation')],decisions=[dict(item_id='encoding',action='retire',basis='cancelled',refs=[user],reason='user cancelled')],additions=[],catalog_coverage=[],unresolved=[],focus_refs=[]))
        self.assertEqual(result['status'],'ready')
        self.assertIsNone(self.packet(result)['validation_feedback'])
        self.assertEqual(result['transaction']['candidate_state']['items'],[])

    @unittest.skipUnless(sys.platform.startswith('linux'),'Linux process lifetime inspection')
    def test_raw_judge_stops_descendants_when_its_caller_is_terminated(self):
        import signal
        import subprocess
        ready=self.ready();folder=Path(self.tmp.name)
        rules=folder/'rules.md';rules.write_text('## 応答\n')
        checked=folder/'checked.json';checked.write_text('[]')
        for signum in (signal.SIGTERM,signal.SIGKILL):
            pidfile=folder/('model-'+str(signum)+'.pid')
            fake=folder/('fake-'+str(signum)+'.py')
            fake.write_text('import os,time;open('+repr(str(pidfile))+',"w").write(str(os.getpid()));time.sleep(60)')
            env=dict(os.environ,OUTPUT_GATE_RULES=str(rules),OUTPUT_GATE_CHECKED_RULES=str(checked),OUTPUT_GATE_CODEX_CMD=json.dumps([sys.executable,str(fake)]))
            with tempfile.TemporaryFile() as out,tempfile.TemporaryFile() as err:
                proc=subprocess.Popen([sys.executable,'-I',str(ROOT/'agent-shared/bin/output-gate-check.py'),'--judge'],stdin=subprocess.PIPE,stdout=out,stderr=err,env=env)
                self.addCleanup(lambda p=proc:p.kill() if p.poll() is None else None)
                proc.stdin.write(json.dumps(dict(payload=self.payload,prompt=ready['prompt'],transaction=ready['transaction'])).encode());proc.stdin.close()
                until=time.monotonic()+5
                while not pidfile.exists() and proc.poll() is None and time.monotonic()<until:time.sleep(0.01)
                self.assertTrue(pidfile.exists())
                def cleanup_model(path=pidfile):
                    try:os.kill(int(path.read_text()),signal.SIGKILL)
                    except (OSError,ValueError):pass
                self.addCleanup(cleanup_model)
                started=time.monotonic();proc.send_signal(signum);proc.wait(timeout=5)
                state=Path('/proc')/pidfile.read_text()/'stat'
                while state.exists() and state.read_text().split(') ',1)[1][0]!='Z' and time.monotonic()-started<2:time.sleep(0.01)
                self.assertTrue(not state.exists() or state.read_text().split(') ',1)[1][0]=='Z')
                self.assertLess(time.monotonic()-started,2)

    def test_joint_judgment_retains_new_live_items_without_duplicate_keep_output(self):
        ready=self.ready();data=self.packet(ready);user=data['users'][0]['ref']
        item=dict(id='encoding',kind='constraint',text='Use UTF-8',refs=[user],related=[],target=dict(name='output',revision_refs=[]),validity='current')
        result=self.reply(ready,dict(kind='judgment',additions=[item],decisions=[],catalog_coverage=[],unresolved=[],focus_refs=[],claims=[dict(id='answer',answer_ref=data['answers'][0]['ref'],text='Done.',requirement_ids=['encoding'],evidence=[],verdict='nonfactual')],findings=[],replacements=[],progress=dict(state='unknown',reason='fixture'),focus_candidates=[]))
        self.assertEqual(result['status'],'checked',result.get('reason'))
        self.assertEqual(result['context_state']['items'],[item])
        self.assertEqual(len(result['context_metrics']['inputs']),1)

    def test_claims_cover_both_draft_and_shown_without_duplicate_coverage(self):
        self.payload['shown_text'] = 'Earlier progress.'
        ready = self.ready(); data = self.packet(ready)
        answer = dict(kind='judgment', user_coverage=[data['user_scope']['ref']], additions=[], decisions=[], catalog_coverage=[], unresolved=[], focus_refs=[], item_coverage=[], claims=[dict(id=str(n), answer_ref=a['ref'], text=a['text'], requirement_ids=[], evidence=[], verdict='nonfactual') for n, a in enumerate(data['answers'])], findings=[], replacements=[], focus_candidates=[])
        result = self.reply(ready, answer)
        self.assertEqual(result['status'], 'checked', result.get('reason'))
        self.assertEqual(len(result['context_metrics']['inputs']), 1)

    def test_missing_shown_claims_cannot_pass_even_with_answer_coverage(self):
        self.payload['shown_text'] = 'Earlier progress.'
        ready = self.ready(); data = self.packet(ready)
        draft = next(a for a in data['answers'] if a['text'] == 'Done.')
        result = self.reply(ready, dict(kind='judgment', user_coverage=[data['user_scope']['ref']], additions=[], decisions=[], catalog_coverage=[], unresolved=[], focus_refs=[], answer_coverage=[a['ref'] for a in data['answers']], item_coverage=[], claims=[dict(id='draft', answer_ref=draft['ref'], text=draft['text'], requirement_ids=[], evidence=[], verdict='nonfactual')], findings=[], replacements=[], focus_candidates=[]))
        self.assertEqual(result['status'], 'ready')
        self.assertIn('claim coverage incomplete', self.packet(result)['validation_feedback'])
        self.assertEqual(self.packet(result)['stage'], 'judge')
        self.assertNotIn('users', self.packet(result))

    def test_prepare_masks_normalized_sources_and_all_model_metadata_once(self):
        self.payload.update(progress_state=dict(note='sensitive'), previous_findings=[dict(note='sensitive')], check_obligations=[])
        calls = []
        def mask(data, path, *args):
            calls.append(data)
            return checker.replace_leaves(data, lambda text: text.replace('sensitive', '[REDACTED]'))
        with patch.object(checker, 'mask_secrets', side_effect=mask):
            ready = self.ready()
        self.assertEqual(len(calls), 3)
        tx = ready['transaction']
        self.assertEqual(tx['progress_state']['note'], '[REDACTED]')
        self.assertEqual(tx['previous_findings'][0]['note'], '[REDACTED]')

    def test_unchanged_archived_sources_are_reused_but_packet_is_scanned(self):
        self.ready()
        calls = []
        with patch.object(checker, 'mask_secrets', side_effect=lambda data, path, *args: calls.append(json.loads(json.dumps(data))) or data):
            ready = self.ready()
        self.assertEqual(calls[1]['sources'], [])
        self.assertIn('answers', calls[-1])
        self.assertEqual(ready['status'], 'ready')

    def test_next_request_reuses_validated_user_page_after_timeout(self):
        self.payload.update(recent_messages=[dict(role='user', text='Alpha.', native_id='alpha'), dict(role='user', text='Beta.', native_id='beta')], latest_user='Beta.')
        ready = self.ready(); tx = ready['transaction']; unit = tx['pending_units'][0]
        users = unit['users']; self.assertEqual(len(users), 2)
        tx['pending_units'] = [dict(items=[], users=[user], catalog=[]) for user in users]
        ready = checker.context_ready(tx)
        result = self.reply(ready, dict(kind='update', user_coverage=[users[0]['ref']], additions=[], decisions=[], catalog_coverage=[], unresolved=[], focus_refs=[]))
        self.assertEqual(result['status'], 'ready')
        self.payload['draft'] = 'New answer.'
        next_ready = self.ready(); data = self.packet(next_ready)
        self.assertEqual([u['text'] for u in data['users']], ['Beta.'])
        self.payload['recent_messages'].append(dict(role='user', text='Gamma.', native_id='gamma'))
        self.payload['latest_user'] = 'Gamma.'
        next_ready = self.ready(); data = self.packet(next_ready)
        self.assertEqual([u['text'] for u in data['users']], ['Beta.', 'Gamma.'])
        self.assertEqual(len(next_ready['transaction']['pending_units']), 1)

    def test_empty_coverage_cannot_pass(self):
        result = self.reply(self.ready(), {'kind': 'update', 'user_coverage': [], 'focus_refs': [],
            'catalog_coverage': [], 'decisions': [], 'additions': [], 'unresolved': []})
        self.assertEqual(result['status'], 'ready')
        self.assertIn('coverage', self.packet(result)['validation_feedback'])

    def test_discovery_annotation_does_not_add_a_catalog_obligation(self):
        for has_operation in [False, True]:
            with self.subTest(has_operation=has_operation):
                self.payload['context_dir'] = str(Path(self.tmp.name) / str(has_operation))
                self.payload['evidence'] = [{'id': 'op', 'tool': 'exec', 'output': 'unavailable', 'unavailable': True}] if has_operation else []
                ready = self.ready()
                data = self.packet(ready)
                discovery = data['catalog_refs'][0]
                result = self.reply(ready, {'kind': 'update', 'user_coverage': [u['ref'] for u in data['users']],
                    'catalog_coverage': [{'id': discovery['id'], 'rev': discovery['rev'],
                        'disposition': 'unrelated', 'related_item_ids': [], 'reason': 'Discovery index annotation',
                        'grounding_refs': [discovery]}],
                    'decisions': [], 'additions': [], 'unresolved': [], 'focus_refs': []})
                feedback = self.packet(result).get('validation_feedback')
                if has_operation:
                    self.assertIn('catalog coverage incomplete', feedback)
                else:
                    self.assertIsNone(feedback)

    def test_foreign_reference_is_not_absence(self):
        result = self.reply(self.ready(), {'kind': 'need_refs', 'refs': [
            {'id': 'foreign', 'rev': 'x', 'field': 'text', 'start': 0, 'end': 1}]})
        self.assertEqual(result['status'], 'ready')
        self.assertIn('reference', self.packet(result)['validation_feedback'])

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
        users = self.packet(ready)['users']
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
        ready = {'status': 'ready', 'prompt': '{}', 'transaction': {'source_end': {}, 'metrics': {'inputs':[{}]}}}
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
        ready = {'status': 'ready', 'prompt': '{}', 'transaction': {'source_end': {}, 'metrics': {'inputs':[{}]}}}
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
        data = self.packet(ready)
        return self.reply(ready, {'kind': 'update', 'user_coverage': [x['ref'] for x in data.get('users', [])],
            'focus_refs': data.get('focus', []), 'catalog_coverage': [dict(id=c['id'], rev=c['rev'],
                disposition='unrelated', related_item_ids=[], reason='test fixture unrelated') for c in data.get('catalog', [])],
            'decisions': decisions if decisions is not None else [dict(item_id=i['id'], action='keep', reason='still active') for i in data['items']],
            'additions': additions or [], 'unresolved': []})

    def judgment(self, ready, **changes):
        data = self.packet(ready)
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
        user = self.packet(ready)['users'][0]
        item = {'id': 'encoding', 'kind': 'constraint', 'text': 'Use UTF-8', 'refs': [user['ref']],
                'related': [], 'target': {'name': 'output', 'revision_refs': []}, 'validity': 'current'}
        ready = self.update(ready, [item])
        result = self.judgment(ready)
        self.assertEqual(result['status'], 'checked', result)
        return result

    def test_warm_state_retains_old_constraint_without_resending_user(self):
        first = self.live_state()
        ready = self.ready()
        data = self.packet(ready)
        self.assertEqual(data['stage'], 'judge')
        self.assertEqual(data['items'], first['context_state']['items'])
        self.assertNotIn('users', data)
        self.assertEqual(first['progress_state']['evidence'], [])
        self.assertEqual(first['progress_state']['bodies'], [])

    def test_live_assessment_binds_original_to_existing_obligation_once(self):
        self.live_state()
        self.payload.update(turn_id='follow-up', request_id='follow-up', latest_user='Keep using UTF-8.')
        ready = self.ready(); data = self.packet(ready); user = data['users'][0]['ref']
        result = self.reply(ready, dict(kind='update', user_assessments=[dict(refs=[user], disposition='live', item_ids=['encoding'], resolution_refs=[], reason='Reaffirms the active encoding constraint')], decisions=[dict(item_id='encoding', action='keep', basis='current', refs=[], reason='Still active')], additions=[], catalog_coverage=[], unresolved=[], focus_refs=[]))
        self.assertEqual(result['status'], 'ready')
        self.assertIsNone(self.packet(result)['validation_feedback'])
        self.assertIn(user, result['transaction']['candidate_state']['items'][0]['refs'])

    def test_new_user_cannot_silently_drop_old_constraint(self):
        self.live_state()
        self.payload['recent_messages'] = [{'role': 'user', 'text': 'Use UTF-8.'}, {'role': 'user', 'text': 'What time is it?'}]
        self.payload['latest_user'] = 'What time is it?'
        result = self.update(self.ready(), decisions=[])
        self.assertEqual(result['status'], 'ready')
        self.assertIn('coverage', self.packet(result)['validation_feedback'])

    def test_nonapplicability_does_not_retire_unfinished_item(self):
        self.live_state()
        self.payload['latest_user'] = 'What time is it?'
        ready = self.ready()
        user = self.packet(ready)['users'][0]['ref']
        result = self.update(ready, decisions=[{'item_id': 'encoding', 'action': 'retire', 'basis': 'irrelevant',
            'refs': [user], 'reason': 'topic detour'}])
        self.assertEqual(result['status'], 'ready')
        self.assertIn('non-applicability', self.packet(result)['validation_feedback'])

    def test_cancellation_still_requires_current_check_coverage(self):
        self.live_state()
        self.payload['latest_user'] = 'Cancel UTF-8 requirement.'
        ready = self.ready()
        user = self.packet(ready)['users'][0]['ref']
        ready = self.update(ready, decisions=[{'item_id': 'encoding', 'action': 'retire', 'basis': 'cancelled',
            'refs': [user], 'reason': 'explicit cancellation'}])
        self.assertEqual(self.packet(ready)['items'][0]['id'], 'encoding')
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
        self.assertEqual(self.packet(ready)['retrieved'][0]['text'], 'FAIL')
        self.assertIn(r, ready['transaction']['served_refs'])

    def test_utf8_reference_boundaries_are_validated(self):
        self.payload = {'origin': 'codex', 'final': True, 'draft': 'あ', 'latest_user': 'あ'}
        ready = self.ready()
        user = self.packet(ready)['users'][0]['ref']
        result = self.reply(ready, {'kind': 'need_refs', 'refs': [dict(user, start=1)]})
        self.assertEqual(result['status'], 'ready')
        self.assertIn('UTF-8', self.packet(result)['validation_feedback'])

    def test_new_revision_keeps_source_identity(self):
        self.payload['sources'] = [{'kind': 'user', 'native_id': 'uuid-1', 'fields': {'text': 'First'}}]
        first = self.ready()['transaction']
        self.payload['sources'][0]['fields']['text'] = 'Correction'
        second = self.ready()['transaction']
        old = next(s for s in first['sources'].values() if s['kind'] == 'user')
        new = [s for s in second['sources'].values() if s['kind'] == 'user'][-1]
        self.assertEqual(old['id'], new['id'])
        self.assertNotEqual(old['rev'], new['rev'])

    def test_tool_history_is_lazy_but_current_state_has_a_frontier(self):
        self.payload['evidence'] = [{'id': str(n), 'command': 'operation', 'output': 'result'} for n in range(846)]
        data = checker.context.expand_wire(json.loads(self.ready()['prompt']))
        self.assertEqual(data['catalog'], [])
        self.assertEqual(data['evidence_frontier']['count'], 846)
        self.assertGreater(data['evidence_frontier']['last_seq'], 0)
        self.assertLess(len(json.dumps(data)), 40000)

    def test_archive_lookup_returns_originals_without_loading_the_index(self):
        self.payload['evidence'] = [{'id': 'one', 'command': 'verify release', 'output': 'release abc passed'}]
        ready = self.ready()
        result = self.reply(ready, {'kind': 'need_refs', 'refs': [
            {'scope': 'archive', 'field': 'output', 'literal': 'release abc', 'before_seq': 0}]})
        self.assertEqual(result['status'], 'ready')
        data = self.packet(result)
        self.assertIsNone(data['validation_feedback'])
        self.assertEqual(data['retrieved'][0]['text'], 'release abc passed')
        self.assertEqual(data['retrieved'][0]['kind'], 'evidence')
        checker.context.resolve_refs(result['transaction'], [data['retrieved'][0]['ref']], True)

    def test_old_success_cannot_prove_current_state_past_unreviewed_operations(self):
        self.payload['evidence'] = [{'id': 'one', 'command': 'verify', 'output': 'passed'},
                                    {'id': 'two', 'command': 'run opaque.sh', 'output': 'changed'}]
        ready = self.update(self.ready())
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        old = checker.context.ref(source, 'output')
        ready = self.reply(ready, {'kind': 'need_refs', 'refs': [old]})
        data = self.packet(ready)
        claim = dict(id='current', answer_ref=data['answers'][0]['ref'], text='Done.', requirement_ids=[],
                     evidence=[dict(ref=old, relation='supports')], verdict='supported', temporal_scope='current',
                     freshness=dict(basis='unresolved', through_seq=0, refs=[], reason='not checked'))
        result = self.judgment(ready, claims=[claim])
        self.assertEqual(result['status'], 'ready')
        self.assertIn('freshness', self.packet(result)['validation_feedback'])

    def test_current_aggregate_cannot_hide_a_change_behind_a_newer_other_success(self):
        self.payload['evidence'] = [{'id': 'a', 'command': 'verify A', 'output': 'A passed'},
            {'id': 'change', 'command': 'opaque', 'output': 'A changed'},
            {'id': 'b', 'command': 'verify B', 'output': 'B passed'}]
        ready = self.update(self.ready())
        sources = sorted((s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence'), key=lambda s:s['seq'])
        refs = [checker.context.ref(s, 'output') for s in (sources[0], sources[2])]
        ready = self.reply(ready, dict(kind='need_refs', refs=refs))
        data = self.packet(ready)
        claim = dict(id='aggregate', answer_ref=data['answers'][0]['ref'], text='A and B passed', requirement_ids=[],
            evidence=[dict(ref=r, relation='supports') for r in refs], verdict='supported', temporal_scope='current',
            freshness=dict(basis='unresolved', through_seq=0, refs=[], reason='not checked'))
        result = self.judgment(ready, claims=[claim])
        self.assertIn('freshness', self.packet(result)['validation_feedback'])

    def test_reviewed_truncated_operation_cannot_close_current_state(self):
        self.payload['evidence'] = [{'id':'old', 'command':'verify', 'output':'passed'},
            {'id':'change', 'command':'opaque', 'output':'partial', 'truncated':True}]
        ready = self.update(self.ready())
        sources = sorted((s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence'), key=lambda s:s['seq'])
        old = checker.context.ref(sources[0], 'output')
        later = [checker.context.ref(sources[1], f) for f in ('call','output')]
        ready = self.reply(ready, dict(kind='need_refs', refs=[old,*later]))
        data = self.packet(ready)
        claim = dict(id='current', answer_ref=data['answers'][0]['ref'], text='passed', requirement_ids=[],
            evidence=[dict(ref=old, relation='supports')], verdict='supported', temporal_scope='current',
            freshness=dict(basis='changes_reviewed', through_seq=sources[1]['seq'], refs=later, reason='read stored fields'))
        result = self.judgment(ready, claims=[claim])
        self.assertIn('truncated', self.packet(result)['validation_feedback'])

    def test_exhausted_checker_reports_where_the_context_stopped(self):
        with patch.object(checker, 'context_engine_reply', return_value=(None,None)):
            result = checker.check(self.payload)
        self.assertEqual(result['status'], 'unchecked')
        diagnostic = result['context_diagnostics']
        self.assertEqual(diagnostic['stage'], 'update')
        self.assertEqual(diagnostic['pending_units'], 1)
        self.assertGreater(diagnostic['inputs'][0]['bytes'], 0)

    def test_current_claim_can_review_supplied_operations_without_reciting_every_field(self):
        self.payload['evidence'] = [{'id':'old', 'command':'verify', 'output':'passed'},
            {'id':'later', 'command':'inspect', 'output':'unchanged'}]
        ready = self.update(self.ready())
        sources = sorted((s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence'), key=lambda s:s['seq'])
        old,later = [checker.context.ref(s,'output') for s in sources]
        data = self.packet(ready)
        claim = dict(id='current', answer_ref=data['answers'][0]['ref'], text='passed', requirement_ids=[],
            evidence=[dict(ref=old, relation='supports')], verdict='supported', temporal_scope='current',
            freshness=dict(basis='changes_reviewed', through_seq=sources[1]['seq'], refs=[later], reason='The supplied operation inspected the unchanged target.'))
        result = self.judgment(ready, claims=[claim])
        self.assertEqual(result['status'],'checked',result.get('reason'))

    def test_missing_catalog_disposition_prevents_closure(self):
        self.payload['evidence'] = [{'id': 'call', 'output': 'unavailable', 'unavailable': True}]
        ready = self.ready()
        data = self.packet(ready)
        result = self.reply(ready, {'kind': 'update', 'user_coverage': [u['ref'] for u in data['users']],
            'decisions': [], 'catalog_coverage': [], 'additions': [], 'unresolved': [], 'focus_refs': []})
        self.assertEqual(result['status'], 'ready')
        self.assertIn('catalog coverage', self.packet(result)['validation_feedback'])

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
        self.assertEqual(self.packet(resumed)['stage'], 'judge')

    def test_large_new_user_is_covered_in_bounded_units(self):
        self.payload['latest_user'] = 'a' * 430000
        ready = self.ready()
        coverage = []
        while ready['status'] == 'ready' and self.packet(ready)['stage'] in ('update', 'update_and_judge'):
            data = self.packet(ready)
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
        self.assertEqual(self.packet(second)['stage'], 'judge')
        self.assertEqual(second['transaction']['candidate_state']['items'], first['context_state']['items'])
        self.payload['source_mode'] = 'delta'
        self.payload['sources'][0]['native_id'] = 'different-uuid'
        third = self.ready()
        self.assertIn(self.packet(third)['stage'], ('update', 'update_and_judge'))
        self.assertNotEqual(self.packet(third)['users'][0]['ref']['id'], first['context_state']['items'][0]['refs'][0]['id'])

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
        user = self.packet(ready)['users'][0]['ref']
        item = {'id': 'q', 'kind': 'question', 'text': 'Answer the question', 'refs': [user],
                'related': [], 'target': {'name': 'answer', 'revision_refs': []}, 'validity': 'current'}
        ready = self.update(ready, [item])
        draft = self.packet(ready)['answers'][0]['ref']
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
        draft = self.packet(ready)['answers'][0]['ref']
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
        changed = dict(state['items'][0], text='Now use Shift_JIS', refs=[self.packet(ready)['users'][0]['ref']])
        result = self.update(ready, [changed])
        self.assertEqual(result['status'], 'ready')
        self.assertIn('overwrite', self.packet(result)['validation_feedback'])

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
        self.payload['evidence'] = [{'id': 'call', 'tool': 'exec', 'output': 'unavailable', 'unavailable': True}]
        self.payload['recent_messages'] = [{'role': 'user', 'text': 'first'}, {'role': 'assistant', 'text': 'report'}]
        ready = self.ready()
        data = self.packet(ready)
        result = self.reply(ready, {'kind': 'update', 'user_coverage': [data['user_scope']['ref']],
            'catalog_coverage': [dict(data['catalog_scope'], disposition='unrelated', related_item_ids=[], reason='fixture')],
            'decisions': [], 'additions': [], 'unresolved': [], 'focus_refs': []})
        self.assertEqual(result['status'], 'ready', result)
        self.assertEqual(self.packet(result)['stage'], 'judge')

    def test_large_original_request_is_paged_without_marking_remaining_bytes_served(self):
        import random
        original = ''.join(random.Random(17).choices('あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん', k=230000))
        self.payload['evidence'] = [{'id': 'call', 'tool': 'exec', 'output': original}]
        ready = self.ready()
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        full = checker.context.ref(source, 'output')
        ready = self.reply(ready, {'kind': 'need_refs', 'refs': [full]})
        data = self.packet(ready)
        self.assertTrue(data['remaining_refs'])
        self.assertLessEqual(ready['transaction']['metrics']['inputs'][-1]['bytes'], 400000)
        with self.assertRaisesRegex(ValueError, 'not served'):
            checker.context.resolve_refs(ready['transaction'], [full], True)
        pieces = [e['text'] for e in data['retrieved']]
        observations = [dict(id='prefix-read', kind='unresolved', text='The prefix is read; remaining original bytes are still required.',
                             refs=[data['retrieved'][0]['ref']], related=[],
                             target=dict(name='original', revision_refs=[]), validity='current')]
        while data['remaining_refs']:
            ready = self.reply(ready, {'kind': 'need_refs', 'refs': data['remaining_refs'], 'additions': observations})
            observations = []
            data = self.packet(ready)
            pieces.extend(e['text'] for e in data['retrieved'])
            self.assertLessEqual(ready['transaction']['metrics']['inputs'][-1]['bytes'], 400000)
        self.assertEqual(''.join(pieces), original)
        checker.context.resolve_refs(ready['transaction'], [full], True)

    def test_completed_meaning_update_is_reused_after_draft_changes(self):
        ready = self.update(self.ready())
        self.payload['draft'] = 'A different answer'
        resumed = self.ready()
        data = self.packet(resumed)
        self.assertEqual(data['stage'], 'judge')
        self.assertEqual(data['answers'][0]['text'], 'A different answer')
        self.assertEqual(resumed['transaction']['resumed_update_units'], 1)
        self.assertFalse((Path(self.tmp.name) / 'state.json').exists())

    def test_fetched_original_survives_meaning_update_and_changed_draft(self):
        self.payload['evidence'] = [{'id': 'verification', 'output': 'x' * 10000 + 'VERIFIED' + 'y' * 10000}]
        ready = self.ready()
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        wanted = checker.context.ref(source, 'output', 10000, 10008)
        ready = self.reply(ready, {'kind': 'need_refs', 'refs': [wanted]})
        self.assertEqual(self.packet(ready)['retrieved'][0]['text'], 'VERIFIED')
        ready = self.update(ready)
        self.assertTrue(any(e['ref'] == wanted and e['text'] == 'VERIFIED'
                            for e in self.packet(ready)['retrieved']))
        stale = ready
        self.payload['draft'] = 'Updated answer.'
        self.payload['evidence'].append({'id': 'inspection', 'output': 'No target changes.'})
        resumed = self.ready()
        data = self.packet(resumed)
        self.assertEqual(data['answers'][0]['text'], 'Updated answer.')
        self.assertTrue(any(e['ref'] == wanted and e['text'] == 'VERIFIED' for e in data['retrieved']))
        self.assertEqual(resumed['transaction']['claims'], [])
        checker.context.resolve_refs(resumed['transaction'], [wanted], True)
        self.assertEqual(self.judgment(stale)['status'], 'unchecked')
        self.assertEqual(self.judgment(resumed)['status'], 'checked')

    def test_partial_meaning_update_resumes_with_new_user_without_replaying_prefix(self):
        import random
        old = ''.join(random.Random(31).choices('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', k=430000))
        self.payload['latest_user'] = old
        ready = self.ready()
        covered_end = max(u['ref']['end'] for u in self.packet(ready)['users'])
        ready = self.update(ready)
        self.payload['draft'] = 'Changed draft'
        self.payload['recent_messages'] = [{'role': 'user', 'text': old}, {'role': 'user', 'text': 'Continue'}]
        self.payload['latest_user'] = 'Continue'
        resumed = self.ready()
        data = self.packet(resumed)
        self.assertIn(data['stage'], ('update', 'update_and_judge'))
        self.assertEqual(data['users'][0]['ref']['start'], covered_end)
        self.assertEqual(resumed['transaction']['candidate_state']['meaning_cursor']['user_seq'], 0)
        self.assertFalse((Path(self.tmp.name) / 'state.json').exists())

    def test_small_gap_has_served_original_but_stays_unavailable(self):
        self.payload['evidence'] = [{'id': 'gap', 'unavailable': True, 'note': 'No original result'}]
        ready = self.ready()
        grounds = [g for g in self.packet(ready)['catalog_grounding'] if g['kind'] == 'gap']
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
        self.assertEqual({e['text'] for e in self.packet(ready)['retrieved']}, {'small one', 'small two'})

    def test_repeated_reference_request_gets_content_feedback(self):
        self.payload['evidence'] = [{'id': 'verification', 'output': 'x' * 10000 + 'VERIFIED' + 'y' * 10000}]
        ready = self.update(self.ready())
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        wanted = checker.context.ref(source, 'output', 10000, 10008)
        ready = self.reply(ready, {'kind': 'need_refs', 'refs': [wanted]})
        repeated = self.reply(ready, {'kind': 'need_refs', 'refs': [wanted]})
        self.assertEqual(repeated['status'], 'ready')
        self.assertIn('without context progress', self.packet(repeated)['validation_feedback'] or '')
        self.assertEqual(self.judgment(repeated)['status'], 'checked')

    def test_same_search_for_a_different_claim_advances_its_evidence_scope(self):
        self.payload['draft'] = 'First. Second.'
        self.payload['evidence'] = [{'id': 'verification', 'output': 'tests passed'}]
        ready = self.update(self.ready())
        answer = self.packet(ready)['answers'][0]['ref']
        first = dict(answer, end=6)
        second = dict(answer, start=7)
        query = dict(scope='archive', field='output', literal='tests', before_seq=0)
        ready = self.reply(ready, dict(kind='need_refs', refs=[query], focus_refs=[first]))
        ready = self.reply(ready, dict(kind='need_refs', refs=[query], focus_refs=[second]))
        self.assertIsNone(self.packet(ready)['validation_feedback'])
        self.assertEqual(ready['transaction']['archive_searches'][-1]['focus_refs'], [second])

    def test_regrouping_old_requests_does_not_advance_context(self):
        self.payload['evidence'] = [{'id': 'one', 'output': 'first'}, {'id': 'two', 'output': 'second'}]
        ready = self.update(self.ready())
        refs = [checker.context.ref(s, 'output') for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence']
        ready = self.reply(ready, dict(kind='need_refs', refs=[refs[0]]))
        ready = self.reply(ready, dict(kind='need_refs', refs=[refs[1]]))
        ready = self.reply(ready, dict(kind='need_refs', refs=refs))
        self.assertIn('without context progress', self.packet(ready)['validation_feedback'] or '')

    def test_evidence_supply_frontier_advances_after_the_original_is_read(self):
        import random
        self.payload['evidence'] = [dict(id='verification', output=''.join(random.Random(409).choices('ABCDEFGHIJKLMNOPQRSTUVWXYZ', k=20000)))]
        ready = self.ready()
        self.assertEqual(self.packet(ready)['evidence_frontier'].get('unserved_original_fields'), 1)
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        ready = self.reply(ready, dict(kind='need_refs', refs=[checker.context.ref(source, 'output')]))
        self.assertEqual(self.packet(ready)['evidence_frontier']['unserved_original_fields'], 0)

    def test_paging_preserves_a_grounded_interpretation_before_evicting_evidence(self):
        import random
        rng = random.Random(407)
        self.payload['evidence'] = [dict(id=str(n), output=''.join(rng.choices('ABCDEFGHIJKLMNOPQRSTUVWXYZ', k=size)))
                                    for n, size in enumerate((108000, 70000))]
        ready = self.update(self.ready())
        sources = sorted((s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence'), key=lambda s:s['seq'])
        first, second = [checker.context.ref(s, 'output') for s in sources]
        ready = self.reply(ready, dict(kind='need_refs', refs=[first]))
        rejected = self.reply(ready, dict(kind='need_refs', refs=[second]))
        self.assertIn('grounded observation', self.packet(rejected)['validation_feedback'] or '')
        self.assertTrue(any(e['ref'] == first for e in self.packet(rejected)['retrieved']))
        observation = dict(id='first-fact', kind='fact', text='Inspected the first verification original.',
                           refs=[first], related=[], target=dict(name='verification', revision_refs=[]), validity='current')
        ready = self.reply(rejected, dict(kind='need_refs', refs=[second], additions=[observation]))
        self.assertIsNone(self.packet(ready)['validation_feedback'])
        self.assertTrue(any(e['ref'] == second for e in self.packet(ready)['retrieved']))
        observation = dict(observation, id=ready['transaction']['retrieval_observations'][0]['id'])
        self.assertEqual(ready['transaction']['retrieval_observations'], [observation])
        self.assertFalse(any(e['ref'] == first for e in self.packet(ready)['retrieved']))
        self.payload['draft'] = 'Updated answer after inspecting both originals.'
        resumed = self.ready()
        self.assertEqual(resumed['transaction']['retrieval_observations'], [observation])
        checker.context.resolve_refs(resumed['transaction'], observation['refs'], True)

    def test_validated_interpretation_survives_a_later_paging_feedback(self):
        import random
        rng = random.Random(408)
        self.payload['evidence'] = [dict(id=str(n), output=''.join(rng.choices('ABCDEFGHIJKLMNOPQRSTUVWXYZ', k=size)))
                                    for n, size in enumerate((50000, 50000, 108000))]
        ready = self.update(self.ready())
        sources = sorted((s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence'), key=lambda s:s['seq'])
        first, second, third = [checker.context.ref(s, 'output') for s in sources]
        ready = self.reply(ready, dict(kind='need_refs', refs=[first, second]))
        one = dict(id='one', kind='fact', text='First original was inspected.', refs=[first], related=[],
                   target=dict(name='first', revision_refs=[]), validity='current')
        two = dict(id='two', kind='unresolved', text='Second original needs later verification.', refs=[second], related=[],
                   target=dict(name='second', revision_refs=[]), validity='current')
        for _ in range(2):
            ready = self.reply(ready, dict(kind='need_refs', refs=[third]))
        feedback = self.packet(ready)['validation_feedback']
        self.assertIn(first['id'], feedback)
        self.assertIn(second['id'], feedback)
        ready = self.reply(ready, dict(kind='need_refs', refs=[third], additions=[one]))
        self.assertEqual(ready['status'], 'ready', ready.get('reason'))
        self.assertIn('grounded observation', self.packet(ready)['validation_feedback'] or '')
        one = dict(one, id=ready['transaction']['retrieval_observations'][0]['id'])
        self.assertEqual(ready['transaction']['retrieval_observations'], [one])
        ready = self.reply(ready, dict(kind='need_refs', refs=[third], additions=[two]))
        self.assertIsNone(self.packet(ready)['validation_feedback'])
        two = dict(two, id=ready['transaction']['retrieval_observations'][1]['id'])
        self.assertEqual(ready['transaction']['retrieval_observations'], [one, two])
        self.assertTrue(any(e['ref'] == third for e in self.packet(ready)['retrieved']))

    def test_retained_originals_fit_the_packet_after_a_larger_answer(self):
        import random
        rng = random.Random(405)
        self.payload['latest_user'] = ''.join(rng.choices('abcdefghijklmnopqrstuvwxyz', k=200000))
        self.payload['draft'] = ''
        self.payload['evidence'] = [{'id': 'verification', 'output': ''.join(rng.choices('ABCDEFGHIJKLMNOPQRSTUVWXYZ', k=108000))}]
        ready = self.ready()
        data = self.packet(ready)
        user = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'user')
        user_ref = checker.context.ref(user)
        item = dict(id='requirement', kind='requirement', text='Inspect the required result', refs=[user_ref],
                    related=[], target=dict(name='result', revision_refs=[]), validity='current')
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        wanted = checker.context.ref(source, 'output')
        ready = self.reply(ready, dict(kind='need_refs', refs=[wanted]))
        ready = self.update(ready, additions=[item])
        self.payload['draft'] = ''.join(rng.choices('abcdefghijklmnopqrstuvwxyz', k=55000))
        resumed = self.ready()
        self.assertLessEqual(resumed['transaction']['metrics']['inputs'][-1]['bytes'], 400000)
        self.assertIn(source['id'] + ':' + source['rev'], resumed['transaction']['sources'])

    def test_progressing_check_can_complete_beyond_ten_minutes(self):
        clock = [1000.0]
        calls = []
        self.payload['evidence'] = [{'id': 'verification', 'output': 'x' * 10000 + 'VERIFIED' + 'y' * 10000}]

        def engine(prompt, payload, settings, order, workdir, deadline, failures, attempts):
            calls.append(prompt)
            clock[0] += 250
            if clock[0] >= deadline:
                return None, None
            data = checker.context.expand_wire(json.loads(prompt))
            if len(calls) == 1:
                reply = dict(kind='update', remaining_users=dict(disposition='context_only', reason='fixture'),
                             decisions=[], additions=[], catalog_coverage=[], unresolved=[], focus_refs=[])
            elif len(calls) == 2:
                source = next(s for s in json.loads((Path(self.tmp.name) / 'transaction.json').read_text())['sources'].values()
                              if s['kind'] == 'evidence')
                reply = dict(kind='need_refs', refs=[checker.context.ref(source, 'output', 10000, 10008)])
            else:
                reply = dict(kind='judgment', claims=[dict(id='answer', answer_ref=data['answers'][0]['ref'],
                             text='Done.', requirement_ids=[], evidence=[], verdict='nonfactual')],
                             item_coverage=[], decisions=[], findings=[], replacements=[],
                             progress=dict(state='advanced', reason='Completed evidence acquisition and judgment.'))
            return json.dumps(reply), {'family': 'test'}

        with patch.dict(os.environ, {'OUTPUT_GATE_TIMEOUT': ''}), \
                patch.object(time, 'monotonic', side_effect=lambda: clock[0]), \
                patch.object(time, 'time', side_effect=lambda: clock[0]), \
                patch.object(checker, 'context_engine_reply', side_effect=engine):
            result = checker.check(self.payload)
        self.assertEqual(result['status'], 'checked', result.get('reason'))
        self.assertEqual(result['text'], 'Done.')
        self.assertEqual(len(calls), 3)

    def test_user_meaning_and_planned_evidence_are_ready_before_judgment(self):
        self.payload['evidence']=[dict(id='op',output='actual result')]
        ready=self.ready();data=self.packet(ready)
        self.assertEqual(data['stage'],'update_and_judge')
        self.assertEqual(data['answers'][0]['text'],'Done.')
        source=next(s for s in ready['transaction']['sources'].values() if s['kind']=='evidence')
        wanted=checker.context.ref(source,'output')
        ready=self.reply(ready,dict(kind='update',refs=[wanted],user_coverage=[data['user_scope']['ref']],
            additions=[],decisions=[],catalog_coverage=[],unresolved=[],focus_refs=[]))
        data=self.packet(ready)
        self.assertEqual(data['stage'],'judge')
        self.assertNotIn('users',data)
        self.assertTrue(any(g['ref']==wanted for g in data['retrieved']))
        result=self.judgment(ready)
        self.assertEqual(result['status'],'checked')
        self.assertEqual(len(result['context_metrics']['inputs']),2)

    def test_support_can_use_the_necessary_original_range_without_reading_unrelated_bytes(self):
        prefix = 'x' * 350000
        self.payload['evidence'] = [{'id': 'call', 'tool': 'exec', 'output': prefix + 'target passed' + 'y' * 350000}]
        ready = self.ready()
        source = next(s for s in ready['transaction']['sources'].values() if s['kind'] == 'evidence')
        needed = checker.context.ref(source, 'output', len(prefix), len(prefix) + len('target passed'))
        ready = self.reply(ready, {'kind': 'need_refs', 'refs': [needed]})
        data = self.packet(ready)
        ready = self.reply(ready, {'kind': 'update', 'user_coverage': [u['ref'] for u in data['users']],
            'focus_refs': [], 'catalog_coverage': [{'id': source['id'], 'rev': source['rev'], 'disposition': 'retrieve',
                'related_item_ids': [], 'reason': 'The target result is in this exact original range', 'grounding_refs': [needed]}],
            'decisions': [], 'additions': [], 'unresolved': []})
        data = self.packet(ready)
        answer = data['answers'][0]
        result = self.judgment(ready, claims=[{'id': 'c', 'answer_ref': answer['ref'], 'text': answer['text'],
            'requirement_ids': [], 'evidence': [{'ref': needed, 'relation': 'supports'}], 'verdict': 'supported', 'temporal_scope': 'historical'}])
        self.assertEqual(result['status'], 'checked', result)
        self.assertLess(result['context_metrics']['retrieved_bytes'], len(prefix))

    def test_current_unshown_draft_cannot_retire_an_old_question_during_update(self):
        ready = self.ready()
        user = self.packet(ready)['users'][0]['ref']
        old_answer = self.packet(ready)['answers'][0]['ref']
        item = {'id': 'q', 'kind': 'question', 'text': 'Explain', 'refs': [user], 'related': [],
                'target': {'name': 'answer', 'revision_refs': []}, 'validity': 'current'}
        self.judgment(self.update(ready, [item]))
        self.payload['latest_user'] = 'Continue'
        self.payload['turn_id'] = 'next-turn'
        self.payload['draft'] = 'Not yet displayed'
        ready = self.ready()
        draft = self.packet(ready)['answers'][0]['ref']
        result = self.update(ready, decisions=[{'item_id': 'q', 'action': 'retire', 'basis': 'answered',
            'refs': [draft], 'reason': 'It appears in the draft'}])
        self.assertEqual(result['status'], 'ready')
        self.assertIn('deliverable', self.packet(result)['validation_feedback'])
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
        data = self.packet(ready)
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
        data = self.packet(ready)
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
        result = self.packet(ready)['locator_results'][0]
        self.assertIsNotNone(result['remaining_after'])
        next_ready = self.reply(ready, {'kind': 'need_refs', 'refs': [dict(locator, after=result['remaining_after'])]})
        later = self.packet(next_ready)['locator_results'][0]
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
        source_ref = checker.context.expand_references(data['users'][0]['ref'],ready['transaction']['reference_handles'])
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
        user_ref = self.packet(late)['users'][0]['ref']
        rejected = self.reply(late, {'kind': 'need_refs', 'refs': [user_ref]})
        self.assertEqual(rejected['status'], 'unchecked')
        self.assertIn('CAS', rejected['reason'])
        self.assertEqual(json.loads(path.read_text()), before)

    def test_conflicting_new_item_ids_do_not_silently_drop_a_requirement(self):
        ready = self.ready()
        user_ref = self.packet(ready)['users'][0]['ref']
        first = {'id': 'same-new-id', 'kind': 'requirement', 'text': 'Keep A', 'refs': [user_ref],
                 'related': [], 'target': {'name': 'task', 'revision_refs': []}, 'validity': 'current'}
        result = self.update(ready, [first, dict(first, text='Also do B')])
        self.assertEqual(result['status'], 'ready')
        self.assertIn('identity', self.packet(result)['validation_feedback'])
        self.assertEqual(result['transaction']['candidate_state']['items'], [])

    def test_prefetch_budget_uses_lossless_wire_bytes_and_supplies_the_whole_original(self):
        original = 'x' * 320000 + '\n{"passed":11,"failed":1}\n' + 'y' * 320000
        self.payload['evidence'] = [{'id': 'call', 'tool': 'exec', 'output': original}]
        ready = self.ready()
        packet = json.loads(ready['prompt'])
        output = next(e for e in packet['catalog_grounding'] if checker.context.expand_references(e['ref'],ready['transaction']['reference_handles'])['field'] == 'output')
        self.assertEqual(checker.context.expand_source_text(output['text']), original)
        reference=checker.context.expand_references(output['ref'],ready['transaction']['reference_handles'])
        self.assertEqual(reference['end'], len(original.encode()))
        self.assertLess(len(checker.context.encoded(output)), 8192)
        checker.context.resolve_refs(ready['transaction'], [reference], True)

    def test_contradicted_claim_cannot_be_displayed_without_a_valid_finding(self):
        self.payload['evidence'] = [{'id': 'call', 'tool': 'exec', 'output': '11 passed, 1 failed'}]
        ready = self.update(self.ready())
        data = self.packet(ready)
        result_ref = next(g['ref'] for g in data['catalog_grounding'] if g['ref']['field'] == 'output')
        answer = {'kind': 'judgment', 'user_coverage': [u['ref'] for u in data.get('users', [])],
            'catalog_coverage': [],
            'additions': [], 'decisions': [], 'unresolved': [], 'focus_refs': [], 'focus_resolved': [],
            'item_coverage': [], 'answer_coverage': [a['ref'] for a in data['answers']],
            'claims': [{'id': 'c', 'answer_ref': data['answers'][0]['ref'], 'text': 'all passed', 'requirement_ids': [],
                        'evidence': [{'ref': result_ref, 'relation': 'contradicts'}], 'verdict': 'contradicted'}],
            'findings': [], 'replacements': [], 'progress': {'state': 'unknown', 'reason': 'fixture'}, 'focus_candidates': []}
        rejected = self.reply(ready, answer)
        self.assertEqual(rejected['status'], 'ready')
        self.assertIn('contradicted', self.packet(rejected)['validation_feedback'])
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
        data = self.packet(ready)
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
        self.assertIn('Shall I proceed?', self.packet(ready)['retrieved'][0]['text'])
        user = data['users'][0]
        ready = self.update(ready)
        result = self.judgment(ready, findings=[{'kind': 'missing_request', 'rule': '', 'source': user['ref']['id'],
            'excerpt': user['text'], 'evidence': [{'id': None, 'state': 'absent'}]}])
        self.assertEqual(result['status'], 'checked', result)
        self.assertEqual(result['findings'][0]['source'], user['ref']['id'])

    def test_unverified_status_can_be_reported_honestly_without_a_finding(self):
        self.payload['draft'] = 'The result is still unverified.'
        ready = self.update(self.ready())
        data = self.packet(ready)
        result = self.judgment(ready, claims=[{'id': 'c', 'answer_ref': data['answers'][0]['ref'],
            'text': 'The result is still unverified.', 'requirement_ids': [], 'evidence': [], 'verdict': 'qualified'}])
        self.assertEqual(result['status'], 'checked')
        self.assertEqual(result['text'], self.payload['draft'])
        self.assertEqual(result['findings'], [])

    def test_confirmed_focus_is_prefetched_as_displayed_on_the_next_short_approval(self):
        self.payload['turn_id'] = 'first'
        ready = self.ready()
        ready = self.update(ready)
        answer = self.packet(ready)['answers'][0]['ref']
        result = self.judgment(ready, focus_candidates=[answer])
        checker.context.confirm_display(self.tmp.name, result['display_receipt'], result['text'])
        self.payload.update(turn_id='second', latest_user='Yes', draft='A new answer')
        ready = self.ready()
        data = self.packet(ready)
        focus = next(g for g in data['catalog_grounding'] if g['ref'] == answer)
        self.assertTrue(focus['displayed'])
        self.assertEqual(focus['text'], 'Done.')
        self.assertEqual(data['focus'], [answer])

    def test_explicit_new_native_user_is_not_replaced_by_an_old_positional_identity(self):
        self.payload.update(turn_id='one', latest_user='うん')
        self.judgment(self.update(self.ready()))
        self.payload.update(turn_id='two', recent_messages=[{'role': 'user', 'text': 'うん', 'native_id': 'new-genuine-user-event'}])
        ready = self.ready()
        data = self.packet(ready)
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
        data = self.packet(ready)
        self.assertIn(data['stage'], ('update', 'update_and_judge'))
        self.assertEqual([u['text'] for u in data['users']], ['Repeat the check'])

    def test_uncorrelated_native_snapshot_keeps_active_items_and_cannot_replay_authorization(self):
        self.payload['origin'] = 'claude'
        first = self.live_state()
        self.payload.update(source_collector='claude-hook', source_mode='bootstrap',
            sources=[{'kind': 'user', 'native_id': 'uncorrelated-uuid', 'fields': {'text': 'Use UTF-8.'}}])
        ready = self.ready()
        data = self.packet(ready)
        self.assertTrue(data['users'][0]['identity_gap'])
        self.assertEqual(ready['transaction']['candidate_state']['items'], first['context_state']['items'])
        original = data['users'][0]['ref']
        source = ready['transaction']['sources'][original['id'] + ':' + original['rev']]
        self.assertEqual(source['native_id'], 'uncorrelated-uuid')
        authorization = {'id': 'new-authorization', 'kind': 'authorization', 'text': 'Proceed', 'refs': [original],
            'related': [], 'target': {'name': 'action', 'revision_refs': []}, 'validity': 'current'}
        rejected = self.update(ready, [authorization])
        self.assertIn('uncertain source identity', self.packet(rejected)['validation_feedback'])
        self.assertEqual(rejected['transaction']['candidate_state']['items'], first['context_state']['items'])

    def test_verified_request_coordinate_links_a_native_upgrade_without_replaying_it(self):
        self.payload.update(turn_id='one', request_id='event-one')
        first = self.live_state()
        self.payload['sources'] = [{'kind': 'user', 'native_id': 'physical-one', 'fields': {'text': 'Use UTF-8.'}}]
        ready = self.ready()
        self.assertEqual(self.packet(ready)['stage'], 'judge')
        native = next(s for s in ready['transaction']['sources'].values() if s.get('native_id') == 'physical-one')
        self.assertEqual(native['metadata']['replay_of']['id'], first['context_state']['items'][0]['refs'][0]['id'])
        self.payload['request_id'] = 'event-two'
        self.payload['sources'][0]['native_id'] = 'physical-two'
        ready = self.ready()
        users = self.packet(ready)['users']
        self.assertEqual(len(users), 1)
        self.assertFalse(users[0].get('identity_gap'))


    def test_masked_bootstrap_cannot_replay_an_uncorrelated_authorization(self):
        def mask(data, path, *args):
            return checker.replace_leaves(data, lambda text: text.replace('secret-marker', '[REDACTED]'))
        with patch.object(checker, 'mask_secrets', side_effect=mask):
            self.payload.update(origin='claude', latest_user='Proceed using secret-marker.')
            self.judgment(self.update(self.ready()))
            self.payload.update(source_collector='claude-hook', source_mode='bootstrap',
                sources=[dict(kind='user', native_id='uncorrelated-uuid', fields=dict(text='Proceed using secret-marker.'))])
            ready = self.ready()
            user = self.packet(ready)['users'][0]
            self.assertTrue(user.get('identity_gap'))
            authorization = dict(id='authorization', kind='authorization', text='Proceed', refs=[user['ref']],
                related=[], target=dict(name='action', revision_refs=[]), validity='current')
            rejected = self.update(ready, [authorization])
            self.assertIn('uncertain source identity', self.packet(rejected)['validation_feedback'])
            self.assertEqual(rejected['transaction']['candidate_state']['items'], [])

    def test_rejected_completion_checkpoint_keeps_requirement_after_retry(self):
        ready = self.ready()
        user = self.packet(ready)['users'][0]['ref']
        item = dict(id='req', kind='requirement', text='Do the work', refs=[user], related=[],
            target=dict(name='work', revision_refs=[]), validity='current')
        self.judgment(self.update(ready, [item]))
        self.payload.update(turn_id='next', request_id='next', latest_user='Continue.',
            evidence=[dict(id='operation', tool='exec', output='Operation incomplete')])
        ready = self.ready()
        data = self.packet(ready)
        evidence = next(entry['ref'] for entry in data['catalog_grounding'] if entry['ref']['field'] == 'output')
        claims = [dict(id='claim', answer_ref=a['ref'], text=a['text'], requirement_ids=['req'], evidence=[],
            verdict='unverified') for a in data['answers']]
        rejected = self.reply(ready, dict(kind='judgment', user_coverage=[data['user_scope']['ref']],
            additions=[], decisions=[dict(item_id='req', action='retire', basis='completed', refs=[evidence], reason='operation done')],
            catalog_coverage=[], unresolved=[], focus_refs=[], item_coverage=['req'], claims=claims,
            findings=[], replacements=[], focus_candidates=[]))
        self.assertIn('unverified claim cannot close', self.packet(rejected)['validation_feedback'])
        self.assertEqual(self.packet(rejected)['stage'], 'judge')
        result = self.judgment(rejected, claims=claims)
        self.assertEqual(result['status'], 'checked', result.get('reason'))
        self.assertEqual(result['context_state']['items'], [item])


if __name__ == '__main__':
    unittest.main()
